import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/attendance.dart';
import '../models/audit_log.dart';
import '../models/cash_flow.dart';
import '../models/cash_register.dart';
import '../models/customer.dart';
import '../models/customer_credit.dart';
import '../models/customer_debt.dart';
import '../models/inventory_movement.dart';
import '../models/printer_device.dart';
import '../models/product.dart';
import '../models/product_batch.dart';
import '../models/product_unit.dart';
import '../models/promo.dart';
import '../models/purchase.dart';
import '../models/return_exchange_item.dart';
import '../models/return_item.dart';
import '../models/return_order.dart';
import '../models/return_settlement.dart';
import '../models/service_order.dart';
import '../models/shift.dart';
import '../models/stock_opname.dart';
import '../models/tiered_price.dart';
import '../models/transaction.dart';
import '../models/transaction_item.dart';
import '../models/transaction_void.dart';
import '../models/user.dart';
import '../models/warehouse_doc.dart';
import '../utils/security_helper.dart';

enum AuthAttemptStatus {
  success,
  invalidCredentials,
  lockedOut,
  inactive,
}

class AuthAttemptResult {
  final AuthAttemptStatus status;
  final UserModel? user;
  final String message;
  final int retryAfterSeconds;

  const AuthAttemptResult({
    required this.status,
    this.user,
    this.message = '',
    this.retryAfterSeconds = 0,
  });

  bool get isSuccess => status == AuthAttemptStatus.success && user != null;
}

class _TerminalRateState {
  int failedCount = 0;
  DateTime? lockedUntil;

  _TerminalRateState();
}

class ProductScanMatch {
  final ProductModel product;
  final ProductUnitModel? matchedUnit;

  ProductScanMatch({required this.product, this.matchedUnit});
}

class BarcodeConflictResult {
  final ProductModel conflictingProduct;
  final String matchedOn; // 'product_barcode' | 'product_code' | 'unit_barcode'

  BarcodeConflictResult({
    required this.conflictingProduct,
    required this.matchedOn,
  });
}

class DatabaseHelper {
  static const int dbVersion = 6;
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;
  static String? _testDbPath;

  final Map<String, _TerminalRateState> _terminalRateLimits = {};
  static bool _autoConfiguredTestIterations = false;
  static String? _cachedSeedSignature;
  static List<Map<String, dynamic>>? _cachedTestSeedUsers;

  /// Optional real-time broadcaster attached by the Phase 2 LAN Server to emit
  /// WebSocket events when local Admin mutations change catalog, promos, settings,
  /// users, shifts, or transactions.
  void Function(String eventType, Map<String, dynamic> data)? onMultiDeviceEvent;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null && _database!.isOpen) return _database!;
    _database = await _initDB(_testDbPath ?? 'kasirtoko.db');
    return _database!;
  }

  /// Resets the singleton database connection (essential after restore).
  Future<void> resetConnection() async {
    if (_database != null && _database!.isOpen) {
      await _database!.close();
    }
    _database = null;
  }

  Future<void> _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
    await db.rawQuery('PRAGMA busy_timeout = 5000');
    if (db.path != inMemoryDatabasePath) {
      try {
        await db.rawQuery('PRAGMA journal_mode = WAL');
      } catch (_) {
        // Ignore if runtime does not support WAL (e.g., certain virtual FS)
      }
    }
  }

  /// Creates and verifies a pre-migration backup before upgrading an existing on-disk DB.
  /// Returns the verified backup path if a backup was created/verified, or null if new DB.
  Future<String?> _prepareAndVerifyPreMigrationBackup(
    String dbPath, {
    required String backupFileName,
  }) async {
    if (dbPath == inMemoryDatabasePath) return null;
    final dbFile = File(dbPath);
    if (!await dbFile.exists()) return null;

    // Inspect current schema version and checkpoint WAL safely before copying
    int existingVersion = 0;
    Database? probe;
    try {
      probe = await openDatabase(dbPath, singleInstance: false);
      final verRows = await probe.rawQuery('PRAGMA user_version');
      existingVersion = (verRows.first.values.first as num?)?.toInt() ?? 0;
      try {
        await probe.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
      } catch (_) {}
    } finally {
      await probe?.close();
    }

    if (existingVersion >= dbVersion) {
      return null;
    }

    final resolvedFileName = existingVersion <= 4
        ? backupFileName
        : '${p.basenameWithoutExtension(dbPath)}_pre_v${dbVersion}_backup.db';
    final backupPath = p.join(p.dirname(dbPath), resolvedFileName);
    final backupFile = File(backupPath);
    // Refresh pre-migration backup before touching live database
    await dbFile.copy(backupPath);

    if (!await backupFile.exists() || await backupFile.length() <= 0) {
      throw StateError('Backup pra-migrasi gagal dibuat ($backupPath). Migrasi dibatalkan.');
    }

    // Verify backup SQLite integrity strictly before touching live database
    Database? checkDb;
    try {
      checkDb = await openReadOnlyDatabase(backupPath, singleInstance: false);
      final checkRows = await checkDb.rawQuery('PRAGMA integrity_check');
      final status = checkRows.isNotEmpty
          ? (checkRows.first.values.first?.toString().toLowerCase() ?? '')
          : '';
      if (status != 'ok') {
        throw StateError('Verifikasi integritas backup pra-migrasi gagal: $status');
      }
    } finally {
      await checkDb?.close();
    }

    return backupPath;
  }

  Future<void> _restoreFromBackupFile(String dbPath, String backupPath) async {
    await resetConnection();
    for (final suffix in ['-wal', '-shm']) {
      final sideFile = File('$dbPath$suffix');
      if (await sideFile.exists()) {
        try {
          await sideFile.delete();
        } catch (_) {}
      }
    }
    final backupFile = File(backupPath);
    if (await backupFile.exists()) {
      await backupFile.copy(dbPath);
    }
  }

  @visibleForTesting
  Future<Database> openTestDatabase({
    String path = inMemoryDatabasePath,
    bool deleteIfExists = true,
  }) async {
    await resetConnection();
    _terminalRateLimits.clear();
    _testDbPath = path;
    // Host-side regression fixtures that do not explicitly test 600k iterations use fast PBKDF2 rounds
    // to prevent 30s Dart JIT software-SHA256 timeouts across multi-hash tests. Production always runs 600,000.
    if (!SecurityHelper.hasTestIterationOverride) {
      // ignore: invalid_use_of_visible_for_testing_member
      SecurityHelper.configureForTesting(iterations: SecurityHelper.testFixturePbkdf2Iterations);
      _autoConfiguredTestIterations = true;
    } else {
      _autoConfiguredTestIterations = false;
    }
    if (deleteIfExists && path != inMemoryDatabasePath) {
      try {
        final f = File(path);
        if (await f.exists()) await f.delete();
        for (final suffix in ['-wal', '-shm']) {
          final sf = File('$path$suffix');
          if (await sf.exists()) await sf.delete();
        }
      } catch (_) {}
    }

    String? verifiedPreV5Backup;
    if (!deleteIfExists && path != inMemoryDatabasePath && await File(path).exists()) {
      verifiedPreV5Backup = await _prepareAndVerifyPreMigrationBackup(
        path,
        backupFileName: '${p.basenameWithoutExtension(path)}_pre_v5_backup.db',
      );
    }

    try {
      _database = await openDatabase(
        path,
        version: dbVersion,
        onConfigure: _onConfigure,
        onCreate: _createDB,
        onUpgrade: _onUpgrade,
      );
    } catch (e) {
      if (verifiedPreV5Backup != null) {
        await _restoreFromBackupFile(path, verifiedPreV5Backup);
      }
      rethrow;
    }
    return _database!;
  }

  @visibleForTesting
  Future<void> closeTestDatabase() async {
    await resetConnection();
    _terminalRateLimits.clear();
    _testDbPath = null;
    if (_autoConfiguredTestIterations) {
      // ignore: invalid_use_of_visible_for_testing_member
      SecurityHelper.resetTestConfiguration();
      _autoConfiguredTestIterations = false;
    }
  }

  Future<Database> _initDB(String filePath) async {
    String path = filePath;
    if (filePath != inMemoryDatabasePath && !p.isAbsolute(filePath)) {
      final dbDir = await getApplicationDocumentsDirectory();
      path = p.join(dbDir.path, filePath);

      // Preserve legacy safety backups if upgrading from earlier versions
      final dbFile = File(path);
      final preV3Backup = File(p.join(dbDir.path, 'kasirtoko_pre_v3_backup.db'));
      if (await dbFile.exists() && !await preV3Backup.exists()) {
        try {
          await dbFile.copy(preV3Backup.path);
        } catch (_) {}
      }
      final preV4Backup = File(p.join(dbDir.path, 'kasirtoko_pre_v4_backup.db'));
      if (await dbFile.exists() && !await preV4Backup.exists()) {
        try {
          await dbFile.copy(preV4Backup.path);
        } catch (_) {}
      }
    }

    final verifiedPreV5Backup = await _prepareAndVerifyPreMigrationBackup(
      path,
      backupFileName: 'kasirtoko_pre_v5_backup.db',
    );

    try {
      return await openDatabase(
        path,
        version: dbVersion,
        onConfigure: _onConfigure,
        onCreate: _createDB,
        onUpgrade: _onUpgrade,
      );
    } catch (e) {
      if (verifiedPreV5Backup != null) {
        await _restoreFromBackupFile(path, verifiedPreV5Backup);
      }
      rethrow;
    }
  }

  Future<bool> _tableExists(DatabaseExecutor db, String table) async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
      [table],
    );
    return rows.isNotEmpty;
  }

  Future<void> _addColumnIfMissing(
    DatabaseExecutor db,
    String table,
    String columnName,
    String definition,
  ) async {
    final cols = await db.rawQuery('PRAGMA table_info($table)');
    final exists = cols.any((c) => c['name'] == columnName);
    if (!exists) {
      await db.execute('ALTER TABLE $table ADD COLUMN $columnName $definition');
    }
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // 1. Upgrade users table non-destructively
      await _addColumnIfMissing(db, 'users', 'username', 'TEXT');
      await _addColumnIfMissing(db, 'users', 'password_hash', "TEXT NOT NULL DEFAULT ''");
      await _addColumnIfMissing(db, 'users', 'password_salt', "TEXT NOT NULL DEFAULT ''");
      await _addColumnIfMissing(db, 'users', 'pin_hash', "TEXT NOT NULL DEFAULT ''");
      await _addColumnIfMissing(db, 'users', 'phone', "TEXT NOT NULL DEFAULT ''");
      await _addColumnIfMissing(db, 'users', 'photo_path', 'TEXT');
      await _addColumnIfMissing(db, 'users', 'permissions_json', "TEXT NOT NULL DEFAULT ''");

      // Migrate legacy plaintext PINs into salted hashed secrets while keeping existing users functional
      final existingUsers = await db.query('users');
      for (final row in existingUsers) {
        final id = row['id'] as int;
        final rawPin = (row['pin'] ?? '').toString();
        final existingSalt = (row['password_salt'] ?? '').toString();
        final existingPinHash = (row['pin_hash'] ?? '').toString();
        final existingUsername = (row['username'] ?? '').toString();
        final role = (row['role'] ?? AppRoles.cashier).toString();
        final name = (row['name'] ?? 'user$id').toString();

        if (existingSalt.isEmpty || existingPinHash.isEmpty) {
          final salt = SecurityHelper.generateSalt();
          final pinToHash = rawPin.isNotEmpty ? rawPin : '1234';
          final hashedPin = SecurityHelper.hashLegacyV1Secret(pinToHash, salt);
          // Default initial password matches PIN so migrated users can log in cleanly and later update password
          final hashedPw = SecurityHelper.hashLegacyV1Secret(pinToHash, salt);
          final safeUsername = existingUsername.isNotEmpty
              ? existingUsername
              : '${name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '')}_$id';

          final defaultPerms = AppPermissions.defaultForRole(role);
          await db.update(
            'users',
            {
              'username': safeUsername,
              'password_salt': salt,
              'password_hash': hashedPw,
              'pin_hash': hashedPin,
              'pin': '', // Clear plaintext PIN from storage
              'permissions_json': UserModel(name: name, role: role, permissions: defaultPerms).toMap()['permissions_json'],
            },
            where: 'id = ?',
            whereArgs: [id],
          );
        }
      }

      // 2. Upgrade products table
      await _addColumnIfMissing(db, 'products', 'brand', "TEXT NOT NULL DEFAULT ''");
      await _addColumnIfMissing(db, 'products', 'model', "TEXT NOT NULL DEFAULT ''");
      await _addColumnIfMissing(db, 'products', 'condition_type', "TEXT NOT NULL DEFAULT 'baru'");
      await _addColumnIfMissing(db, 'products', 'imei_or_sn', "TEXT NOT NULL DEFAULT ''");
      await _addColumnIfMissing(db, 'products', 'warranty_info', "TEXT NOT NULL DEFAULT ''");
      await _addColumnIfMissing(db, 'products', 'description', "TEXT NOT NULL DEFAULT ''");

      // 3. Upgrade transactions table
      await _addColumnIfMissing(db, 'transactions', 'tax_amount', 'REAL NOT NULL DEFAULT 0.0');
      await _addColumnIfMissing(db, 'transactions', 'promo_name', "TEXT NOT NULL DEFAULT ''");
      await _addColumnIfMissing(db, 'transactions', 'printer_snapshot_json', "TEXT NOT NULL DEFAULT ''");

      // 4. Upgrade shifts table
      await _addColumnIfMissing(db, 'shifts', 'total_sales_qris', 'REAL NOT NULL DEFAULT 0.0');
      await _addColumnIfMissing(db, 'shifts', 'total_sales_transfer', 'REAL NOT NULL DEFAULT 0.0');
      await _addColumnIfMissing(db, 'shifts', 'total_sales_kasbon', 'REAL NOT NULL DEFAULT 0.0');

      // 5. Upgrade warehouse_docs table
      await _addColumnIfMissing(db, 'warehouse_docs', 'delivery_date', 'TEXT');

      // 6. Create new v2 tables
      await _createV2NewTables(db);
    }

    if (oldVersion < 3) {
      await _addColumnIfMissing(db, 'products', 'track_stock', 'INTEGER NOT NULL DEFAULT 1');
      await db.rawUpdate('UPDATE products SET track_stock = 0 WHERE is_service = 1');

      await _addColumnIfMissing(db, 'transactions', 'customer_id', 'INTEGER');
      await _addColumnIfMissing(db, 'transactions', 'shift_id', 'INTEGER');
      await _addColumnIfMissing(db, 'customer_debts', 'customer_id', 'INTEGER');

      await _addColumnIfMissing(db, 'purchases', 'cash_paid', 'REAL NOT NULL DEFAULT 0.0');
      await _addColumnIfMissing(db, 'purchases', 'transfer_paid', 'REAL NOT NULL DEFAULT 0.0');
      await _addColumnIfMissing(db, 'purchases', 'credit_amount', 'REAL NOT NULL DEFAULT 0.0');
      await _addColumnIfMissing(db, 'purchases', 'transfer_account', "TEXT NOT NULL DEFAULT ''");
      await _addColumnIfMissing(db, 'purchases', 'transfer_ref', "TEXT NOT NULL DEFAULT ''");
      await _addColumnIfMissing(db, 'purchases', 'due_date', 'TEXT');
      await _addColumnIfMissing(db, 'purchases', 'status', "TEXT NOT NULL DEFAULT 'completed'");
      await _addColumnIfMissing(db, 'purchases', 'shift_id', 'INTEGER');
      await db.rawUpdate(
        "UPDATE purchases SET cash_paid = total_amount WHERE payment_method = 'kas_laci' AND cash_paid = 0",
      );
      await db.rawUpdate(
        "UPDATE purchases SET transfer_paid = total_amount WHERE payment_method = 'transfer' AND transfer_paid = 0",
      );
      await db.rawUpdate(
        "UPDATE purchases SET credit_amount = total_amount WHERE payment_method = 'hutang' AND credit_amount = 0",
      );

      await _addColumnIfMissing(db, 'cash_flows', 'payment_method', "TEXT NOT NULL DEFAULT 'tunai'");
      await _addColumnIfMissing(db, 'cash_flows', 'account_name', "TEXT NOT NULL DEFAULT 'Laci Kasir'");
      await _addColumnIfMissing(db, 'cash_flows', 'source_type', "TEXT NOT NULL DEFAULT 'manual'");
      await _addColumnIfMissing(db, 'cash_flows', 'source_id', "TEXT NOT NULL DEFAULT ''");
      await _addColumnIfMissing(db, 'cash_flows', 'is_internal_transfer', 'INTEGER NOT NULL DEFAULT 0');

      await _addColumnIfMissing(db, 'attendances', 'device_info', "TEXT NOT NULL DEFAULT ''");
      await _addColumnIfMissing(db, 'attendances', 'is_corrected', 'INTEGER NOT NULL DEFAULT 0');
      await _addColumnIfMissing(db, 'attendances', 'correction_note', "TEXT NOT NULL DEFAULT ''");

      await _addColumnIfMissing(db, 'audit_logs', 'module', "TEXT NOT NULL DEFAULT ''");
      await _addColumnIfMissing(db, 'audit_logs', 'object_id', "TEXT NOT NULL DEFAULT ''");
      await _addColumnIfMissing(db, 'audit_logs', 'before_value', "TEXT NOT NULL DEFAULT ''");
      await _addColumnIfMissing(db, 'audit_logs', 'after_value', "TEXT NOT NULL DEFAULT ''");

      await _createV3NewTables(db);
    }

    if (oldVersion < 4) {
      // Non-destructive v4 forensic return & stock ledger upgrade
      await _addColumnIfMissing(db, 'products', 'quarantine_stock', 'REAL NOT NULL DEFAULT 0.0');
      await _addColumnIfMissing(db, 'products', 'damaged_stock', 'REAL NOT NULL DEFAULT 0.0');

      await _addColumnIfMissing(db, 'transactions', 'credit_used', 'REAL NOT NULL DEFAULT 0.0');
      await _addColumnIfMissing(db, 'shifts', 'total_sales_credit', 'REAL NOT NULL DEFAULT 0.0');

      await _addColumnIfMissing(db, 'return_orders', 'customer_id', 'INTEGER');
      await _addColumnIfMissing(db, 'return_orders', 'customer_name', "TEXT NOT NULL DEFAULT 'Pelanggan Umum'");
      await _addColumnIfMissing(db, 'return_orders', 'reason', "TEXT NOT NULL DEFAULT ''");
      await _addColumnIfMissing(db, 'return_orders', 'status', "TEXT NOT NULL DEFAULT 'completed'");
      await _addColumnIfMissing(db, 'return_orders', 'exchange_total', 'REAL NOT NULL DEFAULT 0.0');
      await _addColumnIfMissing(db, 'return_orders', 'difference_amount', 'REAL NOT NULL DEFAULT 0.0');
      await _addColumnIfMissing(db, 'return_orders', 'difference_payment_method', "TEXT NOT NULL DEFAULT ''");
      await _addColumnIfMissing(db, 'return_orders', 'idempotency_key', 'TEXT');
      await _addColumnIfMissing(db, 'return_orders', 'voided_at', 'TEXT');
      await _addColumnIfMissing(db, 'return_orders', 'voided_by', 'INTEGER');
      await _addColumnIfMissing(db, 'return_orders', 'voided_by_name', "TEXT NOT NULL DEFAULT ''");
      await _addColumnIfMissing(db, 'return_orders', 'void_reason', "TEXT NOT NULL DEFAULT ''");

      await _addColumnIfMissing(db, 'return_items', 'sku', "TEXT NOT NULL DEFAULT ''");
      await _addColumnIfMissing(db, 'return_items', 'cost_price', 'REAL NOT NULL DEFAULT 0.0');
      await _addColumnIfMissing(db, 'return_items', 'purchased_qty', 'REAL NOT NULL DEFAULT 0.0');
      await _addColumnIfMissing(db, 'return_items', 'previously_returned_qty', 'REAL NOT NULL DEFAULT 0.0');
      await _addColumnIfMissing(db, 'return_items', 'stock_treatment', "TEXT NOT NULL DEFAULT 'restock_sellable'");

      // Backfill stock_treatment on legacy rows accurately without altering historical stock balances
      await db.rawUpdate(
        "UPDATE return_items SET stock_treatment = CASE WHEN condition = 'baik' THEN 'restock_sellable' ELSE 'damaged' END WHERE stock_treatment IS NULL OR stock_treatment = '' OR (condition != 'baik' AND stock_treatment = 'restock_sellable')",
      );

      // Backfill customer_id & customer_name onto legacy return_orders from transactions when missing
      await db.rawUpdate('''
        UPDATE return_orders
        SET customer_id = COALESCE(
              customer_id,
              (SELECT t.customer_id FROM transactions t WHERE t.id = return_orders.transaction_id)
            ),
            customer_name = COALESCE(
              NULLIF(customer_name, ''),
              (SELECT t.customer_name FROM transactions t WHERE t.id = return_orders.transaction_id),
              'Pelanggan Umum'
            )
      ''');

      await _createV4NewTables(db);
    }

    if (oldVersion < 5) {
      // Guard: broken/foreign databases lacking core POS tables must abort so pre-v5 backup restores cleanly
      final hasTransactions = await _tableExists(db, 'transactions');
      final hasShifts = await _tableExists(db, 'shifts');
      if (!hasTransactions || !hasShifts) {
        throw StateError('Skema pra-v5 tidak valid: tabel inti transactions/shifts tidak ditemukan.');
      }

      // Ensure auxiliary/v2-v4 tables exist even on partial test/legacy schemas
      await db.execute('''
        CREATE TABLE IF NOT EXISTS users (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          username TEXT,
          password_hash TEXT NOT NULL DEFAULT '',
          password_salt TEXT NOT NULL DEFAULT '',
          pin TEXT NOT NULL DEFAULT '',
          pin_hash TEXT NOT NULL DEFAULT '',
          role TEXT NOT NULL,
          phone TEXT NOT NULL DEFAULT '',
          photo_path TEXT,
          permissions_json TEXT NOT NULL DEFAULT '',
          is_active INTEGER NOT NULL DEFAULT 1
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS cash_flows (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          shift_id INTEGER,
          type TEXT NOT NULL,
          category TEXT NOT NULL,
          amount REAL NOT NULL,
          payment_method TEXT NOT NULL DEFAULT 'tunai',
          account_name TEXT NOT NULL DEFAULT 'Laci Kasir',
          source_type TEXT NOT NULL DEFAULT 'manual',
          source_id TEXT NOT NULL DEFAULT '',
          is_internal_transfer INTEGER NOT NULL DEFAULT 0,
          note TEXT,
          date TEXT NOT NULL,
          cashier_name TEXT NOT NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS return_settlements (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          return_order_id INTEGER NOT NULL,
          settlement_type TEXT NOT NULL,
          direction TEXT NOT NULL,
          method TEXT NOT NULL,
          amount REAL NOT NULL,
          account_name TEXT NOT NULL DEFAULT '',
          reference_number TEXT NOT NULL DEFAULT '',
          shift_id INTEGER,
          customer_id INTEGER,
          cash_flow_id INTEGER,
          note TEXT NOT NULL DEFAULT '',
          created_at TEXT NOT NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS audit_logs (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          timestamp TEXT NOT NULL,
          user_id INTEGER NOT NULL,
          user_name TEXT NOT NULL,
          user_role TEXT NOT NULL DEFAULT '',
          action_type TEXT NOT NULL,
          module TEXT NOT NULL DEFAULT '',
          object_id TEXT NOT NULL DEFAULT '',
          before_value TEXT NOT NULL DEFAULT '',
          after_value TEXT NOT NULL DEFAULT '',
          details TEXT NOT NULL
        )
      ''');
      await _addColumnIfMissing(db, 'audit_logs', 'user_role', "TEXT NOT NULL DEFAULT ''");
      await _addColumnIfMissing(db, 'audit_logs', 'module', "TEXT NOT NULL DEFAULT ''");
      await _addColumnIfMissing(db, 'audit_logs', 'object_id', "TEXT NOT NULL DEFAULT ''");
      await _addColumnIfMissing(db, 'audit_logs', 'before_value', "TEXT NOT NULL DEFAULT ''");
      await _addColumnIfMissing(db, 'audit_logs', 'after_value', "TEXT NOT NULL DEFAULT ''");

      await db.execute('''
        CREATE TABLE IF NOT EXISTS store_settings (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS printers (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          category TEXT NOT NULL DEFAULT 'thermal',
          connection_type TEXT NOT NULL DEFAULT 'system',
          address TEXT NOT NULL DEFAULT '',
          port INTEGER NOT NULL DEFAULT 9100,
          paper_size TEXT NOT NULL DEFAULT '58mm',
          protocol TEXT NOT NULL DEFAULT 'pdf',
          is_default INTEGER NOT NULL DEFAULT 0,
          auto_cut INTEGER NOT NULL DEFAULT 1,
          open_drawer INTEGER NOT NULL DEFAULT 1
        )
      ''');

      // Non-destructive v5 upgrade: KDF v2 credential metadata, multi-register/shift, idempotency & void settlement
      await _addColumnIfMissing(db, 'users', 'pin_salt', "TEXT NOT NULL DEFAULT ''");
      await _addColumnIfMissing(db, 'users', 'hash_version', "TEXT NOT NULL DEFAULT 'legacy_v1'");
      await _addColumnIfMissing(db, 'users', 'pin_lookup_hash', "TEXT NOT NULL DEFAULT ''");
      await _addColumnIfMissing(db, 'users', 'failed_pin_count', 'INTEGER NOT NULL DEFAULT 0');
      await _addColumnIfMissing(db, 'users', 'pin_locked_until', 'TEXT');

      await db.rawUpdate('''
        UPDATE users
        SET hash_version = CASE
          WHEN pin_hash LIKE '\$pbkdf2-sha256\$%' OR password_hash LIKE '\$pbkdf2-sha256\$%'
            THEN '${SecurityHelper.hashVersionV2Pbkdf2}'
          ELSE '${SecurityHelper.hashVersionLegacyV1}'
        END
        WHERE hash_version IS NULL OR hash_version = ''
      ''');

      await _addColumnIfMissing(db, 'transactions', 'terminal_id', "TEXT NOT NULL DEFAULT 'ADMIN'");
      await _addColumnIfMissing(db, 'transactions', 'cash_register_id', 'INTEGER NOT NULL DEFAULT 1');
      await _addColumnIfMissing(db, 'transactions', 'idempotency_key', 'TEXT');

      await db.rawUpdate(
        "UPDATE transactions SET terminal_id = 'ADMIN' WHERE terminal_id IS NULL OR TRIM(terminal_id) = ''",
      );
      await db.rawUpdate(
        'UPDATE transactions SET cash_register_id = 1 WHERE cash_register_id IS NULL OR cash_register_id <= 0',
      );

      await _addColumnIfMissing(db, 'shifts', 'terminal_id', "TEXT NOT NULL DEFAULT 'ADMIN'");
      await _addColumnIfMissing(db, 'shifts', 'cash_register_id', 'INTEGER NOT NULL DEFAULT 1');
      await _addColumnIfMissing(db, 'shifts', 'drawer_mode', "TEXT NOT NULL DEFAULT '${DrawerMode.sharedDrawer}'");

      await db.rawUpdate(
        "UPDATE shifts SET terminal_id = 'ADMIN' WHERE terminal_id IS NULL OR TRIM(terminal_id) = ''",
      );
      await db.rawUpdate(
        'UPDATE shifts SET cash_register_id = 1 WHERE cash_register_id IS NULL OR cash_register_id <= 0',
      );
      await db.rawUpdate(
        "UPDATE shifts SET drawer_mode = '${DrawerMode.sharedDrawer}' WHERE drawer_mode IS NULL OR TRIM(drawer_mode) = ''",
      );

      await _addColumnIfMissing(db, 'cash_flows', 'terminal_id', "TEXT NOT NULL DEFAULT 'ADMIN'");
      await _addColumnIfMissing(db, 'cash_flows', 'cash_register_id', 'INTEGER NOT NULL DEFAULT 1');
      await db.rawUpdate('''
        UPDATE cash_flows
        SET terminal_id = COALESCE(
              NULLIF(TRIM(terminal_id), ''),
              (SELECT s.terminal_id FROM shifts s WHERE s.id = cash_flows.shift_id),
              'ADMIN'
            ),
            cash_register_id = COALESCE(
              NULLIF(cash_register_id, 0),
              (SELECT s.cash_register_id FROM shifts s WHERE s.id = cash_flows.shift_id),
              1
            )
      ''');

      await _addColumnIfMissing(db, 'return_settlements', 'settlement_shift_id', 'INTEGER');
      await _addColumnIfMissing(db, 'return_settlements', 'settlement_cash_register_id', 'INTEGER');
      await db.rawUpdate('''
        UPDATE return_settlements
        SET settlement_shift_id = COALESCE(settlement_shift_id, shift_id),
            settlement_cash_register_id = COALESCE(
              settlement_cash_register_id,
              (SELECT s.cash_register_id FROM shifts s WHERE s.id = return_settlements.shift_id)
            )
        WHERE shift_id IS NOT NULL
      ''');

      await _createV5NewTables(db);
      await _normalizePreV5OpenShifts(db);
      await _ensureV5Indexes(db);

      await db.insert(
        'store_settings',
        {'key': 'drawer_mode', 'value': DrawerMode.sharedDrawer},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }

    if (oldVersion < 6) {
      await _applyV6Upgrade(db);
    }
  }

  Future<void> _applyV6Upgrade(DatabaseExecutor db) async {
    final nowIso = DateTime.now().toIso8601String();

    if (await _tableExists(db, 'products')) {
      await _addColumnIfMissing(db, 'products', 'updated_at', "TEXT NOT NULL DEFAULT ''");
      await _addColumnIfMissing(db, 'products', 'sync_version', 'INTEGER NOT NULL DEFAULT 1');
      await db.rawUpdate(
        "UPDATE products SET updated_at = ? WHERE updated_at IS NULL OR TRIM(updated_at) = ''",
        [nowIso],
      );
      await db.rawUpdate(
        'UPDATE products SET sync_version = 1 WHERE sync_version IS NULL OR sync_version <= 0',
      );
      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_products_sync_version
        ON products (sync_version, id)
      ''');
    }

    if (await _tableExists(db, 'promos')) {
      await _addColumnIfMissing(db, 'promos', 'updated_at', "TEXT NOT NULL DEFAULT ''");
      await _addColumnIfMissing(db, 'promos', 'sync_version', 'INTEGER NOT NULL DEFAULT 1');
      await db.rawUpdate(
        "UPDATE promos SET updated_at = ? WHERE updated_at IS NULL OR TRIM(updated_at) = ''",
        [nowIso],
      );
    }

    if (await _tableExists(db, 'customers')) {
      await _addColumnIfMissing(db, 'customers', 'updated_at', "TEXT NOT NULL DEFAULT ''");
      await _addColumnIfMissing(db, 'customers', 'sync_version', 'INTEGER NOT NULL DEFAULT 1');
      await db.rawUpdate(
        "UPDATE customers SET updated_at = ? WHERE updated_at IS NULL OR TRIM(updated_at) = ''",
        [nowIso],
      );
    }

    if (await _tableExists(db, 'paired_terminals')) {
      await _addColumnIfMissing(db, 'paired_terminals', 'terminal_code', "TEXT NOT NULL DEFAULT ''");
      await _addColumnIfMissing(db, 'paired_terminals', 'device_uuid', "TEXT NOT NULL DEFAULT ''");
      await _addColumnIfMissing(db, 'paired_terminals', 'device_secret_enc', "TEXT NOT NULL DEFAULT ''");
      await _addColumnIfMissing(db, 'paired_terminals', 'allow_auto_open_drawer', 'INTEGER NOT NULL DEFAULT 0');
      await _addColumnIfMissing(db, 'paired_terminals', 'allow_manual_open_drawer', 'INTEGER NOT NULL DEFAULT 0');
      await _addColumnIfMissing(db, 'paired_terminals', 'default_printer_id', 'INTEGER');
      await db.rawUpdate('''
        UPDATE paired_terminals
        SET terminal_code = CASE WHEN TRIM(terminal_code) = '' THEN terminal_id ELSE terminal_code END,
            allow_auto_open_drawer = COALESCE(allow_open_cash_drawer, 0),
            allow_manual_open_drawer = COALESCE(allow_open_cash_drawer, 0)
      ''');
      await db.execute('''
        CREATE UNIQUE INDEX IF NOT EXISTS idx_paired_terminals_device_uuid
        ON paired_terminals (device_uuid)
        WHERE device_uuid IS NOT NULL AND device_uuid != ''
      ''');
    }

    if (await _tableExists(db, 'print_jobs')) {
      await _addColumnIfMissing(db, 'print_jobs', 'invoice_number', "TEXT NOT NULL DEFAULT ''");
      await _addColumnIfMissing(db, 'print_jobs', 'job_type', "TEXT NOT NULL DEFAULT 'receipt'");
      await _addColumnIfMissing(db, 'print_jobs', 'is_reprint', 'INTEGER NOT NULL DEFAULT 0');
      await _addColumnIfMissing(db, 'print_jobs', 'drawer_pulse_sent', 'INTEGER NOT NULL DEFAULT 0');
      await _addColumnIfMissing(db, 'print_jobs', 'idempotency_key', 'TEXT');
      await _addColumnIfMissing(db, 'print_jobs', 'payload_json', "TEXT NOT NULL DEFAULT ''");
      await db.execute('''
        CREATE UNIQUE INDEX IF NOT EXISTS idx_print_jobs_idempotency
        ON print_jobs (idempotency_key)
        WHERE idempotency_key IS NOT NULL AND idempotency_key != ''
      ''');
      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_print_jobs_status_printer
        ON print_jobs (status, printer_id, id)
      ''');
    }

    await db.execute('''
      CREATE TABLE IF NOT EXISTS pairing_tokens (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        token_hash TEXT NOT NULL UNIQUE,
        suggested_terminal_name TEXT NOT NULL DEFAULT '',
        assigned_register_id INTEGER,
        allow_auto_open_drawer INTEGER NOT NULL DEFAULT 0,
        allow_manual_open_drawer INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        expires_at TEXT NOT NULL,
        consumed_at TEXT,
        consumed_by_terminal_id TEXT
      )
    ''');

    if (await _tableExists(db, 'terminal_sessions')) {
      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_terminal_sessions_token_hash
        ON terminal_sessions (session_token_hash, terminal_id)
      ''');
    }

    if (await _tableExists(db, 'store_settings')) {
      await db.insert(
        'store_settings',
        {'key': 'catalog_sync_version', 'value': '1'},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  /// Increments global monotonic `catalog_sync_version` inside the active transaction
  /// and optionally tags the modified entity row with the new `sync_version`.
  Future<int> bumpSyncVersionTxn(
    DatabaseExecutor db, {
    int? productId,
    int? promoId,
    int? customerId,
  }) async {
    final rows = await db.query(
      'store_settings',
      where: 'key = ?',
      whereArgs: ['catalog_sync_version'],
      limit: 1,
    );
    final current = rows.isNotEmpty
        ? (int.tryParse((rows.first['value'] ?? '1').toString()) ?? 1)
        : 1;
    final next = current + 1;
    await db.insert(
      'store_settings',
      {'key': 'catalog_sync_version', 'value': next.toString()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    final nowIso = DateTime.now().toIso8601String();
    if (productId != null) {
      await db.update(
        'products',
        {'updated_at': nowIso, 'sync_version': next},
        where: 'id = ?',
        whereArgs: [productId],
      );
    }
    if (promoId != null) {
      await db.update(
        'promos',
        {'updated_at': nowIso, 'sync_version': next},
        where: 'id = ?',
        whereArgs: [promoId],
      );
    }
    if (customerId != null) {
      await db.update(
        'customers',
        {'updated_at': nowIso, 'sync_version': next},
        where: 'id = ?',
        whereArgs: [customerId],
      );
    }
    return next;
  }

  /// Hydrates a product + related units, tiered pricing & batches using an existing executor.
  Future<ProductModel> hydrateProductTxn(
    DatabaseExecutor db,
    Map<String, dynamic> map,
  ) =>
      _hydrateProduct(db, map);

  Future<void> _normalizePreV5OpenShifts(Database db) async {
    final openReg1 = await db.query(
      'shifts',
      where: "status = 'open' AND cash_register_id = 1",
      orderBy: 'id DESC',
    );
    if (openReg1.length <= 1) return;

    final nowIso = DateTime.now().toIso8601String();
    // Preserve newest open shift and cleanly close stale duplicate open shifts so unique index creation succeeds
    for (int i = 1; i < openReg1.length; i++) {
      final stale = ShiftModel.fromMap(openReg1[i]);
      if (stale.id == null) continue;
      await db.update(
        'shifts',
        {
          'end_time': nowIso,
          'actual_cash': stale.expectedCash,
          'difference': 0.0,
          'status': 'closed',
          'note': '${stale.note} [Auto-closed stale duplicate open shift during DB v5 migration]'.trim(),
        },
        where: 'id = ?',
        whereArgs: [stale.id],
      );
      await db.insert('audit_logs', {
        'timestamp': nowIso,
        'user_id': 0,
        'user_name': 'Sistem Migrasi v5',
        'user_role': 'owner',
        'action_type': 'tutup_shift',
        'module': 'Kas & Shift',
        'object_id': 'SHIFT-${stale.id}',
        'before_value': 'status=open',
        'after_value': 'status=closed',
        'details': 'Penutupan otomatis shift duplikat lama #${stale.id} (${stale.cashierName}) saat migrasi v5',
      });
    }
  }

  Future<void> _createV5NewTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS cash_registers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        register_code TEXT NOT NULL UNIQUE,
        name TEXT NOT NULL,
        printer_id INTEGER,
        is_shared INTEGER NOT NULL DEFAULT 0,
        is_active INTEGER NOT NULL DEFAULT 1,
        notes TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL
      )
    ''');

    int? defaultPrinterId;
    if (await _tableExists(db, 'printers')) {
      final defaultPrinter = await db.query('printers', where: 'is_default = 1', limit: 1);
      defaultPrinterId = defaultPrinter.isNotEmpty ? defaultPrinter.first['id'] as int? : null;
    }

    await db.insert(
      'cash_registers',
      {
        'id': 1,
        'register_code': 'REG-MAIN',
        'name': 'Laci Kasir Utama (Admin)',
        'printer_id': defaultPrinterId,
        'is_shared': 1,
        'is_active': 1,
        'notes': 'Laci kas default kompatibel data historis v1-v4',
        'created_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS cash_register_assignments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        cash_register_id INTEGER NOT NULL,
        terminal_id TEXT,
        cashier_id INTEGER,
        priority INTEGER NOT NULL DEFAULT 0,
        is_active INTEGER NOT NULL DEFAULT 1,
        assigned_by TEXT NOT NULL DEFAULT 'Admin',
        created_at TEXT NOT NULL,
        FOREIGN KEY (cash_register_id) REFERENCES cash_registers (id) ON DELETE CASCADE,
        FOREIGN KEY (cashier_id) REFERENCES users (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS paired_terminals (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        terminal_id TEXT NOT NULL UNIQUE,
        terminal_name TEXT NOT NULL,
        device_model TEXT NOT NULL DEFAULT '',
        device_secret_hash TEXT NOT NULL,
        device_token_hash TEXT NOT NULL,
        assigned_register_id INTEGER,
        allow_open_cash_drawer INTEGER NOT NULL DEFAULT 0,
        is_revoked INTEGER NOT NULL DEFAULT 0,
        paired_at TEXT NOT NULL,
        last_seen_at TEXT,
        FOREIGN KEY (assigned_register_id) REFERENCES cash_registers (id) ON DELETE SET NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS terminal_sessions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_token_hash TEXT NOT NULL UNIQUE,
        terminal_id TEXT NOT NULL,
        cashier_id INTEGER NOT NULL,
        shift_id INTEGER,
        issued_at TEXT NOT NULL,
        expires_at TEXT NOT NULL,
        revoked_at TEXT,
        FOREIGN KEY (terminal_id) REFERENCES paired_terminals (terminal_id) ON DELETE CASCADE,
        FOREIGN KEY (cashier_id) REFERENCES users (id) ON DELETE CASCADE,
        FOREIGN KEY (shift_id) REFERENCES shifts (id) ON DELETE SET NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS print_jobs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        job_uuid TEXT NOT NULL UNIQUE,
        terminal_id TEXT NOT NULL,
        cashier_id INTEGER,
        transaction_id INTEGER,
        printer_id INTEGER,
        open_drawer_requested INTEGER NOT NULL DEFAULT 0,
        drawer_opened INTEGER NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'queued',
        attempts INTEGER NOT NULL DEFAULT 0,
        error_message TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        completed_at TEXT,
        FOREIGN KEY (transaction_id) REFERENCES transactions (id) ON DELETE SET NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS transaction_voids (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        original_transaction_id INTEGER NOT NULL,
        original_invoice_number TEXT NOT NULL,
        original_shift_id INTEGER,
        original_cash_register_id INTEGER NOT NULL DEFAULT 1,
        void_type TEXT NOT NULL DEFAULT '${VoidTypes.postPaymentReversal}',
        refund_method TEXT NOT NULL DEFAULT 'none',
        refund_amount REAL NOT NULL DEFAULT 0.0,
        credit_restored REAL NOT NULL DEFAULT 0.0,
        voided_at TEXT NOT NULL,
        voided_by INTEGER NOT NULL,
        voided_by_name TEXT NOT NULL DEFAULT 'Admin',
        void_reason TEXT NOT NULL DEFAULT '',
        settlement_shift_id INTEGER,
        settlement_cash_register_id INTEGER,
        settlement_terminal_id TEXT NOT NULL DEFAULT 'ADMIN',
        cash_flow_id INTEGER,
        FOREIGN KEY (original_transaction_id) REFERENCES transactions (id) ON DELETE CASCADE,
        FOREIGN KEY (settlement_shift_id) REFERENCES shifts (id) ON DELETE SET NULL,
        FOREIGN KEY (settlement_cash_register_id) REFERENCES cash_registers (id) ON DELETE SET NULL
      )
    ''');
  }

  Future<void> _ensureV5Indexes(Database db) async {
    await db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_transactions_idempotency
      ON transactions (idempotency_key)
      WHERE idempotency_key IS NOT NULL AND idempotency_key != ''
    ''');

    await db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_shifts_one_open_per_register
      ON shifts (cash_register_id)
      WHERE status = 'open'
    ''');

    await db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_shifts_one_open_per_cashier_indiv
      ON shifts (cashier_id)
      WHERE status = 'open' AND drawer_mode = '${DrawerMode.individualDrawer}'
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_cash_register_assignments_lookup
      ON cash_register_assignments (is_active, terminal_id, cashier_id, priority DESC)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_users_pin_lookup
      ON users (is_active, pin_lookup_hash)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_transaction_voids_orig_trx
      ON transaction_voids (original_transaction_id)
    ''');
  }

  Future<void> _createV4NewTables(Database db) async {
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_return_orders_idempotency
      ON return_orders (idempotency_key)
      WHERE idempotency_key IS NOT NULL AND idempotency_key != ''
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS return_exchange_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        return_order_id INTEGER NOT NULL,
        product_id INTEGER NOT NULL,
        sku TEXT NOT NULL DEFAULT '',
        product_name TEXT NOT NULL,
        unit_name TEXT NOT NULL DEFAULT 'Pcs',
        conversion_factor REAL NOT NULL DEFAULT 1.0,
        qty REAL NOT NULL,
        unit_price REAL NOT NULL,
        cost_price REAL NOT NULL DEFAULT 0.0,
        subtotal REAL NOT NULL,
        FOREIGN KEY (return_order_id) REFERENCES return_orders (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS return_settlements (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        return_order_id INTEGER NOT NULL,
        settlement_type TEXT NOT NULL,
        direction TEXT NOT NULL,
        method TEXT NOT NULL,
        amount REAL NOT NULL,
        account_name TEXT NOT NULL DEFAULT '',
        reference_number TEXT NOT NULL DEFAULT '',
        shift_id INTEGER,
        settlement_shift_id INTEGER,
        settlement_cash_register_id INTEGER,
        customer_id INTEGER,
        cash_flow_id INTEGER,
        note TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        FOREIGN KEY (return_order_id) REFERENCES return_orders (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS inventory_movements (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        product_id INTEGER NOT NULL,
        sku TEXT NOT NULL DEFAULT '',
        product_name TEXT NOT NULL DEFAULT '',
        movement_type TEXT NOT NULL,
        bucket TEXT NOT NULL DEFAULT 'sellable',
        qty_delta REAL NOT NULL,
        stock_before REAL NOT NULL,
        stock_after REAL NOT NULL,
        bucket_before REAL NOT NULL DEFAULT 0.0,
        bucket_after REAL NOT NULL DEFAULT 0.0,
        reference_type TEXT NOT NULL DEFAULT '',
        reference_id INTEGER,
        reference_number TEXT NOT NULL DEFAULT '',
        user_id INTEGER NOT NULL DEFAULT 1,
        user_name TEXT NOT NULL DEFAULT 'Sistem',
        note TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS customer_credit_ledger (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        customer_id INTEGER NOT NULL,
        customer_name TEXT NOT NULL DEFAULT '',
        entry_type TEXT NOT NULL,
        amount REAL NOT NULL,
        balance_before REAL NOT NULL DEFAULT 0.0,
        balance_after REAL NOT NULL DEFAULT 0.0,
        reference_type TEXT NOT NULL DEFAULT '',
        reference_id INTEGER,
        reference_number TEXT NOT NULL DEFAULT '',
        user_id INTEGER NOT NULL DEFAULT 1,
        user_name TEXT NOT NULL DEFAULT 'Sistem',
        note TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL
      )
    ''');
  }

  Future<void> _createV3NewTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS customer_debt_payments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        debt_id INTEGER NOT NULL,
        customer_id INTEGER,
        amount REAL NOT NULL,
        payment_method TEXT NOT NULL DEFAULT 'tunai',
        shift_id INTEGER,
        cashier_name TEXT NOT NULL DEFAULT 'Kasir',
        date TEXT NOT NULL,
        note TEXT NOT NULL DEFAULT '',
        FOREIGN KEY (debt_id) REFERENCES customer_debts (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS supplier_debts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        purchase_id INTEGER NOT NULL,
        purchase_number TEXT NOT NULL,
        supplier_name TEXT NOT NULL,
        supplier_phone TEXT NOT NULL DEFAULT '',
        total_debt REAL NOT NULL,
        paid_debt REAL NOT NULL DEFAULT 0.0,
        purchase_date TEXT NOT NULL,
        due_date TEXT,
        last_payment_date TEXT,
        status TEXT NOT NULL DEFAULT 'belum_lunas',
        note TEXT NOT NULL DEFAULT '',
        FOREIGN KEY (purchase_id) REFERENCES purchases (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS supplier_debt_payments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        supplier_debt_id INTEGER NOT NULL,
        amount REAL NOT NULL,
        payment_source TEXT NOT NULL DEFAULT 'kas_laci',
        account_name TEXT NOT NULL DEFAULT 'Laci Kasir',
        reference_number TEXT NOT NULL DEFAULT '',
        shift_id INTEGER,
        paid_by TEXT NOT NULL DEFAULT 'Admin',
        date TEXT NOT NULL,
        note TEXT NOT NULL DEFAULT '',
        FOREIGN KEY (supplier_debt_id) REFERENCES supplier_debts (id) ON DELETE CASCADE
      )
    ''');
  }

  Future<void> _createV2NewTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS customers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        phone TEXT NOT NULL DEFAULT '',
        address TEXT NOT NULL DEFAULT '',
        email TEXT NOT NULL DEFAULT '',
        notes TEXT NOT NULL DEFAULT '',
        points INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS purchases (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        purchase_number TEXT NOT NULL UNIQUE,
        supplier_name TEXT NOT NULL,
        supplier_phone TEXT NOT NULL DEFAULT '',
        date TEXT NOT NULL,
        total_amount REAL NOT NULL,
        payment_method TEXT NOT NULL DEFAULT 'kas_laci',
        cash_paid REAL NOT NULL DEFAULT 0.0,
        transfer_paid REAL NOT NULL DEFAULT 0.0,
        credit_amount REAL NOT NULL DEFAULT 0.0,
        transfer_account TEXT NOT NULL DEFAULT '',
        transfer_ref TEXT NOT NULL DEFAULT '',
        due_date TEXT,
        status TEXT NOT NULL DEFAULT 'completed',
        shift_id INTEGER,
        note TEXT NOT NULL DEFAULT '',
        created_by TEXT NOT NULL DEFAULT 'Admin'
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS purchase_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        purchase_id INTEGER NOT NULL,
        product_id INTEGER NOT NULL,
        product_name TEXT NOT NULL,
        qty REAL NOT NULL,
        unit_name TEXT NOT NULL DEFAULT 'Pcs',
        conversion_factor REAL NOT NULL DEFAULT 1.0,
        cost_price REAL NOT NULL,
        subtotal REAL NOT NULL,
        FOREIGN KEY (purchase_id) REFERENCES purchases (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS printers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        category TEXT NOT NULL DEFAULT 'thermal',
        connection_type TEXT NOT NULL DEFAULT 'system',
        address TEXT NOT NULL DEFAULT '',
        port INTEGER NOT NULL DEFAULT 9100,
        paper_size TEXT NOT NULL DEFAULT '58mm',
        protocol TEXT NOT NULL DEFAULT 'pdf',
        is_default INTEGER NOT NULL DEFAULT 0,
        auto_cut INTEGER NOT NULL DEFAULT 1,
        open_drawer INTEGER NOT NULL DEFAULT 1
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS service_orders (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        ticket_number TEXT NOT NULL UNIQUE,
        customer_id INTEGER,
        customer_name TEXT NOT NULL,
        customer_phone TEXT NOT NULL DEFAULT '',
        device_type TEXT NOT NULL DEFAULT 'HP',
        brand TEXT NOT NULL DEFAULT '',
        model TEXT NOT NULL DEFAULT '',
        imei_sn TEXT NOT NULL DEFAULT '',
        accessories TEXT NOT NULL DEFAULT '',
        complaint TEXT NOT NULL,
        physical_condition TEXT NOT NULL DEFAULT '',
        photo_paths_json TEXT NOT NULL DEFAULT '[]',
        technician_id INTEGER,
        technician_name TEXT NOT NULL DEFAULT 'Belum Ditentukan',
        estimated_cost REAL NOT NULL DEFAULT 0.0,
        service_fee REAL NOT NULL DEFAULT 0.0,
        parts_total REAL NOT NULL DEFAULT 0.0,
        down_payment REAL NOT NULL DEFAULT 0.0,
        paid_amount REAL NOT NULL DEFAULT 0.0,
        status TEXT NOT NULL DEFAULT 'diterima',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        completed_at TEXT,
        picked_up_at TEXT,
        warranty_days INTEGER NOT NULL DEFAULT 7,
        notes TEXT NOT NULL DEFAULT ''
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS service_parts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        service_order_id INTEGER NOT NULL,
        product_id INTEGER,
        product_name TEXT NOT NULL,
        qty REAL NOT NULL DEFAULT 1.0,
        unit_name TEXT NOT NULL DEFAULT 'Pcs',
        conversion_factor REAL NOT NULL DEFAULT 1.0,
        unit_price REAL NOT NULL,
        cost_price REAL NOT NULL DEFAULT 0.0,
        subtotal REAL NOT NULL,
        FOREIGN KEY (service_order_id) REFERENCES service_orders (id) ON DELETE CASCADE
      )
    ''');

    // Seed default System PDF Printer if printers table is empty
    final existingPrinters = await db.query('printers', limit: 1);
    if (existingPrinters.isEmpty) {
      await db.insert('printers', {
        'name': 'Android Print Service (Default PDF)',
        'category': PrinterCategory.laser,
        'connection_type': PrinterConnectionType.system,
        'address': 'system_pdf',
        'port': 9100,
        'paper_size': '58mm',
        'protocol': PrinterProtocol.pdf,
        'is_default': 1,
        'auto_cut': 0,
        'open_drawer': 0,
      });
    }
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        username TEXT,
        password_hash TEXT NOT NULL DEFAULT '',
        password_salt TEXT NOT NULL DEFAULT '',
        pin TEXT NOT NULL DEFAULT '',
        pin_hash TEXT NOT NULL DEFAULT '',
        pin_salt TEXT NOT NULL DEFAULT '',
        hash_version TEXT NOT NULL DEFAULT '${SecurityHelper.hashVersionV2Pbkdf2}',
        pin_lookup_hash TEXT NOT NULL DEFAULT '',
        failed_pin_count INTEGER NOT NULL DEFAULT 0,
        pin_locked_until TEXT,
        role TEXT NOT NULL,
        phone TEXT NOT NULL DEFAULT '',
        photo_path TEXT,
        permissions_json TEXT NOT NULL DEFAULT '',
        is_active INTEGER NOT NULL DEFAULT 1
      )
    ''');

    await db.execute('''
      CREATE TABLE products (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        code TEXT NOT NULL UNIQUE,
        name TEXT NOT NULL,
        category TEXT NOT NULL,
        barcode TEXT,
        is_service INTEGER NOT NULL DEFAULT 0,
        track_stock INTEGER NOT NULL DEFAULT 1,
        base_unit TEXT NOT NULL,
        cost_price REAL NOT NULL,
        selling_price REAL NOT NULL,
        stock REAL NOT NULL,
        quarantine_stock REAL NOT NULL DEFAULT 0.0,
        damaged_stock REAL NOT NULL DEFAULT 0.0,
        min_stock_alert REAL NOT NULL,
        image_path TEXT,
        is_active INTEGER NOT NULL DEFAULT 1,
        brand TEXT NOT NULL DEFAULT '',
        model TEXT NOT NULL DEFAULT '',
        condition_type TEXT NOT NULL DEFAULT 'baru',
        imei_or_sn TEXT NOT NULL DEFAULT '',
        warranty_info TEXT NOT NULL DEFAULT '',
        description TEXT NOT NULL DEFAULT ''
      )
    ''');

    await db.execute('''
      CREATE TABLE product_units (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        product_id INTEGER NOT NULL,
        unit_name TEXT NOT NULL,
        conversion_factor REAL NOT NULL,
        selling_price REAL NOT NULL,
        barcode TEXT,
        FOREIGN KEY (product_id) REFERENCES products (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE tiered_prices (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        product_id INTEGER NOT NULL,
        min_qty REAL NOT NULL,
        price REAL NOT NULL,
        FOREIGN KEY (product_id) REFERENCES products (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE product_batches (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        product_id INTEGER NOT NULL,
        batch_number TEXT NOT NULL,
        expiry_date TEXT NOT NULL,
        stock_qty REAL NOT NULL,
        FOREIGN KEY (product_id) REFERENCES products (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        invoice_number TEXT NOT NULL UNIQUE,
        date TEXT NOT NULL,
        cashier_id INTEGER NOT NULL,
        cashier_name TEXT NOT NULL,
        terminal_id TEXT NOT NULL DEFAULT 'ADMIN',
        cash_register_id INTEGER NOT NULL DEFAULT 1,
        idempotency_key TEXT,
        customer_id INTEGER,
        shift_id INTEGER,
        customer_name TEXT NOT NULL,
        customer_phone TEXT,
        subtotal REAL NOT NULL,
        discount_total REAL NOT NULL,
        tax_amount REAL NOT NULL DEFAULT 0.0,
        promo_name TEXT NOT NULL DEFAULT '',
        grand_total REAL NOT NULL,
        payment_method TEXT NOT NULL,
        credit_used REAL NOT NULL DEFAULT 0.0,
        amount_paid REAL NOT NULL,
        change_amount REAL NOT NULL,
        status TEXT NOT NULL,
        qr_code_payload TEXT NOT NULL,
        note TEXT,
        printer_snapshot_json TEXT NOT NULL DEFAULT ''
      )
    ''');

    await db.execute('''
      CREATE TABLE transaction_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        transaction_id INTEGER NOT NULL,
        product_id INTEGER NOT NULL,
        product_code TEXT NOT NULL,
        product_name TEXT NOT NULL,
        unit_name TEXT NOT NULL,
        conversion_factor REAL NOT NULL DEFAULT 1.0,
        qty REAL NOT NULL,
        unit_price REAL NOT NULL,
        discount REAL NOT NULL DEFAULT 0.0,
        subtotal REAL NOT NULL,
        cost_price REAL NOT NULL DEFAULT 0.0,
        is_service INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (transaction_id) REFERENCES transactions (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE return_orders (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        return_number TEXT NOT NULL UNIQUE,
        transaction_id INTEGER NOT NULL,
        invoice_number TEXT NOT NULL,
        date TEXT NOT NULL,
        cashier_id INTEGER NOT NULL,
        cashier_name TEXT NOT NULL,
        customer_id INTEGER,
        customer_name TEXT NOT NULL DEFAULT 'Pelanggan Umum',
        total_refund REAL NOT NULL,
        refund_method TEXT NOT NULL,
        reason TEXT NOT NULL DEFAULT '',
        note TEXT,
        status TEXT NOT NULL DEFAULT 'completed',
        exchange_total REAL NOT NULL DEFAULT 0.0,
        difference_amount REAL NOT NULL DEFAULT 0.0,
        difference_payment_method TEXT NOT NULL DEFAULT '',
        idempotency_key TEXT,
        voided_at TEXT,
        voided_by INTEGER,
        voided_by_name TEXT NOT NULL DEFAULT '',
        void_reason TEXT NOT NULL DEFAULT ''
      )
    ''');

    await db.execute('''
      CREATE TABLE return_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        return_order_id INTEGER NOT NULL,
        product_id INTEGER NOT NULL,
        sku TEXT NOT NULL DEFAULT '',
        product_name TEXT NOT NULL,
        unit_name TEXT NOT NULL,
        conversion_factor REAL NOT NULL DEFAULT 1.0,
        purchased_qty REAL NOT NULL DEFAULT 0.0,
        previously_returned_qty REAL NOT NULL DEFAULT 0.0,
        return_qty REAL NOT NULL,
        refund_price REAL NOT NULL,
        cost_price REAL NOT NULL DEFAULT 0.0,
        subtotal REAL NOT NULL,
        condition TEXT NOT NULL,
        stock_treatment TEXT NOT NULL DEFAULT 'restock_sellable',
        FOREIGN KEY (return_order_id) REFERENCES return_orders (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE shifts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        cashier_id INTEGER NOT NULL,
        cashier_name TEXT NOT NULL,
        terminal_id TEXT NOT NULL DEFAULT 'ADMIN',
        cash_register_id INTEGER NOT NULL DEFAULT 1,
        drawer_mode TEXT NOT NULL DEFAULT '${DrawerMode.sharedDrawer}',
        start_time TEXT NOT NULL,
        end_time TEXT,
        starting_cash REAL NOT NULL,
        total_sales_cash REAL NOT NULL DEFAULT 0.0,
        total_sales_qris REAL NOT NULL DEFAULT 0.0,
        total_sales_transfer REAL NOT NULL DEFAULT 0.0,
        total_sales_kasbon REAL NOT NULL DEFAULT 0.0,
        total_sales_credit REAL NOT NULL DEFAULT 0.0,
        total_cash_in REAL NOT NULL DEFAULT 0.0,
        total_cash_out REAL NOT NULL DEFAULT 0.0,
        total_return_cash REAL NOT NULL DEFAULT 0.0,
        actual_cash REAL,
        difference REAL,
        status TEXT NOT NULL DEFAULT 'open',
        note TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE cash_flows (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        shift_id INTEGER,
        terminal_id TEXT NOT NULL DEFAULT 'ADMIN',
        cash_register_id INTEGER NOT NULL DEFAULT 1,
        type TEXT NOT NULL,
        category TEXT NOT NULL,
        amount REAL NOT NULL,
        payment_method TEXT NOT NULL DEFAULT 'tunai',
        account_name TEXT NOT NULL DEFAULT 'Laci Kasir',
        source_type TEXT NOT NULL DEFAULT 'manual',
        source_id TEXT NOT NULL DEFAULT '',
        is_internal_transfer INTEGER NOT NULL DEFAULT 0,
        note TEXT,
        date TEXT NOT NULL,
        cashier_name TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE attendances (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        employee_id INTEGER NOT NULL,
        employee_name TEXT NOT NULL,
        timestamp TEXT NOT NULL,
        type TEXT NOT NULL,
        status TEXT NOT NULL,
        late_minutes INTEGER NOT NULL DEFAULT 0,
        challenge_code TEXT NOT NULL,
        validation_hash TEXT NOT NULL,
        photo_path TEXT NOT NULL,
        is_liveness_passed INTEGER NOT NULL DEFAULT 1,
        device_info TEXT NOT NULL DEFAULT '',
        is_corrected INTEGER NOT NULL DEFAULT 0,
        correction_note TEXT NOT NULL DEFAULT ''
      )
    ''');

    await db.execute('''
      CREATE TABLE audit_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp TEXT NOT NULL,
        user_id INTEGER NOT NULL,
        user_name TEXT NOT NULL,
        user_role TEXT NOT NULL,
        action_type TEXT NOT NULL,
        module TEXT NOT NULL DEFAULT '',
        object_id TEXT NOT NULL DEFAULT '',
        before_value TEXT NOT NULL DEFAULT '',
        after_value TEXT NOT NULL DEFAULT '',
        details TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE customer_debts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        customer_id INTEGER,
        customer_name TEXT NOT NULL,
        customer_phone TEXT,
        invoice_number TEXT NOT NULL,
        total_debt REAL NOT NULL,
        paid_debt REAL NOT NULL DEFAULT 0.0,
        transaction_date TEXT NOT NULL,
        due_date TEXT NOT NULL,
        last_payment_date TEXT,
        note TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE warehouse_docs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        doc_number TEXT NOT NULL UNIQUE,
        doc_type TEXT NOT NULL,
        date TEXT NOT NULL,
        delivery_date TEXT,
        recipient_name TEXT NOT NULL,
        recipient_address TEXT,
        recipient_phone TEXT,
        driver_or_picker_name TEXT,
        vehicle_number TEXT,
        note TEXT,
        status TEXT NOT NULL,
        items_json TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE stock_opnames (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL,
        product_id INTEGER NOT NULL,
        product_code TEXT NOT NULL,
        product_name TEXT NOT NULL,
        system_stock REAL NOT NULL,
        physical_stock REAL NOT NULL,
        difference REAL NOT NULL,
        note TEXT,
        audited_by TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE promos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        promo_type TEXT NOT NULL,
        min_purchase REAL NOT NULL DEFAULT 0.0,
        discount_value REAL NOT NULL DEFAULT 0.0,
        buy_qty INTEGER,
        get_qty INTEGER,
        target_product_id INTEGER,
        target_product_name TEXT,
        start_date TEXT NOT NULL,
        end_date TEXT NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1
      )
    ''');

    await db.execute('''
      CREATE TABLE store_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    await _createV2NewTables(db);
    await _createV3NewTables(db);
    await _createV4NewTables(db);
    await _createV5NewTables(db);
    await _ensureV5Indexes(db);
    await _applyV6Upgrade(db);
    await _seedInitialData(db);
  }

  Future<void> _seedInitialData(Database db) async {
    final defaultSettings = {
      'store_name': 'TOKO BERKAH JAYA',
      'store_address': 'Jl. Ahmad Yani No. 88, Kota',
      'store_phone': '081234567890',
      'store_email': 'admin@tokoberkahjaya.id',
      'owner_name': 'Pemilik Toko',
      'owner_phone': '081234567890',
      'business_type': 'general',
      'business_identity': 'Universal Retail & Service POS',
      'branch_name': 'Cabang Utama',
      'logo_path': '',
      'currency_symbol': 'Rp ',
      'invoice_prefix': 'INV',
      'invoice_format': '{PREFIX}-{YYYYMMDD}-{RAND}',
      'tax_enabled': '0',
      'tax_rate': '11',
      'receipt_footer': 'Terima kasih atas kunjungan Anda!\nBarang yang sudah dibeli dapat ditukar maksimal 2 hari.',
      'printer_paper_size': '58mm',
      'shift_start_hour': '08:00',
      'drawer_mode': DrawerMode.sharedDrawer,
    };

    for (final entry in defaultSettings.entries) {
      await db.insert('store_settings', {'key': entry.key, 'value': entry.value});
    }

    // Seed hashed default accounts using v2 PBKDF2-HMAC-SHA256 with separated salts
    final defaultUsers = [
      {'name': 'Pemilik Toko', 'username': 'owner', 'pin': '123456', 'role': AppRoles.owner},
      {'name': 'Supervisor Toko', 'username': 'supervisor', 'pin': '3333', 'role': AppRoles.supervisor},
      {'name': 'Kasir 1', 'username': 'kasir', 'pin': '1111', 'role': AppRoles.cashier},
      {'name': 'Petugas Gudang', 'username': 'gudang', 'pin': '2222', 'role': AppRoles.warehouse},
      {'name': 'Teknisi Servis', 'username': 'teknisi', 'pin': '4444', 'role': AppRoles.technician},
    ];

    final isTestMode = _testDbPath != null;
    final sigDigest = await SecurityHelper.computePinLookupDigest('seed_sig');
    final seedSignature = '${SecurityHelper.activeIterations}:$sigDigest';

    if (isTestMode && _cachedSeedSignature == seedSignature && _cachedTestSeedUsers != null) {
      for (final userMap in _cachedTestSeedUsers!) {
        await db.insert('users', Map<String, dynamic>.from(userMap));
      }
    } else {
      final seededMaps = await Future.wait(
        defaultUsers.map((u) async {
          final pin = u['pin']!;
          final pwPair = await SecurityHelper.hashSecretV2(
            pin,
            domain: SecurityHelper.domainPassword,
          );
          final pinPair = await SecurityHelper.hashSecretV2(
            pin,
            domain: SecurityHelper.domainPin,
          );
          final lookup = await SecurityHelper.computePinLookupDigest(pin);
          final user = UserModel(
            name: u['name']!,
            username: u['username']!,
            passwordHash: pwPair.hash,
            passwordSalt: pwPair.salt,
            pin: '',
            pinHash: pinPair.hash,
            pinSalt: pinPair.salt,
            hashVersion: SecurityHelper.hashVersionV2Pbkdf2,
            pinLookupHash: lookup,
            role: u['role']!,
            isActive: true,
          );
          return user.toMap();
        }),
      );

      for (final userMap in seededMaps) {
        await db.insert('users', userMap);
      }
      if (isTestMode) {
        _cachedSeedSignature = seedSignature;
        _cachedTestSeedUsers = seededMaps.map((m) => Map<String, dynamic>.from(m)).toList();
      }
    }

    final now = DateTime.now();

    final p1Id = await db.insert('products', {
      'code': 'PRD-001',
      'name': 'Minyak Goreng Sania 2L',
      'category': 'Sembako',
      'barcode': '8992345001',
      'is_service': 0,
      'base_unit': 'Pcs',
      'cost_price': 31000.0,
      'selling_price': 34500.0,
      'stock': 48.0,
      'min_stock_alert': 10.0,
      'is_active': 1,
    });
    await db.insert('product_units', {
      'product_id': p1Id,
      'unit_name': 'Dus',
      'conversion_factor': 6.0,
      'selling_price': 200000.0,
      'barcode': '8992345001-DUS',
    });
    await db.insert('tiered_prices', {
      'product_id': p1Id,
      'min_qty': 3.0,
      'price': 33500.0,
    });
    await db.insert('product_batches', {
      'product_id': p1Id,
      'batch_number': 'BATCH-MG26',
      'expiry_date': now.add(const Duration(days: 180)).toIso8601String(),
      'stock_qty': 48.0,
    });

    final p2Id = await db.insert('products', {
      'code': 'PRD-002',
      'name': 'Beras Ramos Super 5Kg',
      'category': 'Sembako',
      'barcode': '8992345002',
      'is_service': 0,
      'base_unit': 'Karung',
      'cost_price': 65000.0,
      'selling_price': 72000.0,
      'stock': 25.0,
      'min_stock_alert': 5.0,
      'is_active': 1,
    });
    await db.insert('tiered_prices', {
      'product_id': p2Id,
      'min_qty': 5.0,
      'price': 70000.0,
    });

    final p3Id = await db.insert('products', {
      'code': 'PRD-003',
      'name': 'Susu UHT Ultramilk 1L',
      'category': 'Minuman',
      'barcode': '8992345003',
      'is_service': 0,
      'base_unit': 'Pcs',
      'cost_price': 16000.0,
      'selling_price': 19000.0,
      'stock': 30.0,
      'min_stock_alert': 8.0,
      'is_active': 1,
    });
    await db.insert('product_batches', {
      'product_id': p3Id,
      'batch_number': 'UHT-NOV26',
      'expiry_date': now.add(const Duration(days: 15)).toIso8601String(),
      'stock_qty': 30.0,
    });

    await db.insert('products', {
      'code': 'SRV-001',
      'name': 'Jasa Antar Barang / Pasang',
      'category': 'Jasa',
      'barcode': 'SRV001',
      'is_service': 1,
      'base_unit': 'Trip',
      'cost_price': 5000.0,
      'selling_price': 15000.0,
      'stock': 999.0,
      'min_stock_alert': 0.0,
      'is_active': 1,
    });

    await db.insert('products', {
      'code': 'SPR-001',
      'name': 'LCD Samsung A52 Original',
      'category': 'Sparepart',
      'barcode': '8992345901',
      'is_service': 0,
      'base_unit': 'Pcs',
      'cost_price': 350000.0,
      'selling_price': 500000.0,
      'stock': 5.0,
      'min_stock_alert': 2.0,
      'brand': 'Samsung',
      'model': 'A52',
      'condition_type': 'baru',
      'warranty_info': 'Garansi 7 Hari',
      'is_active': 1,
    });

    await db.insert('customers', {
      'name': 'Pelanggan Umum',
      'phone': '',
      'address': '-',
      'notes': 'Pelanggan walk-in default',
      'points': 0,
      'created_at': now.toIso8601String(),
    });
  }

  // ================= USERS & AUTH CRUD =================
  static const int _lockThresholdMedium = 5;
  static const int _lockThresholdHigh = 8;
  static const int _lockThresholdSevere = 10;

  int _lockDurationSecondsForFailures(int failCount) {
    if (failCount >= _lockThresholdSevere) return 900; // 15 minutes
    if (failCount >= _lockThresholdHigh) return 300; // 5 minutes
    if (failCount >= _lockThresholdMedium) return 60; // 1 minute
    return 0;
  }

  AuthAttemptResult? _checkTerminalRateLimit(String key, DateTime now) {
    final state = _terminalRateLimits[key];
    if (state?.lockedUntil != null && now.isBefore(state!.lockedUntil!)) {
      final rem = state.lockedUntil!.difference(now).inSeconds.clamp(1, 3600);
      return AuthAttemptResult(
        status: AuthAttemptStatus.lockedOut,
        retryAfterSeconds: rem,
        message: 'Terlalu banyak percobaan gagal pada terminal ini. Coba lagi dalam $rem detik.',
      );
    }
    return null;
  }

  Future<void> _recordSecurityAudit(
    DatabaseExecutor db, {
    required int userId,
    required String userName,
    required String userRole,
    required String actionType,
    required String objectId,
    String beforeValue = '',
    String afterValue = '',
    required String details,
  }) async {
    await db.insert('audit_logs', {
      'timestamp': DateTime.now().toIso8601String(),
      'user_id': userId,
      'user_name': userName,
      'user_role': userRole,
      'action_type': actionType,
      'module': 'Keamanan & Autentikasi',
      'object_id': objectId,
      'before_value': beforeValue,
      'after_value': afterValue,
      'details': details,
    });
  }

  Future<AuthAttemptResult> _recordFailedAuthAttempt(
    Database db, {
    required String terminalRateKey,
    required String terminalId,
    UserModel? user,
    required String methodLabel,
    String? attemptedUsername,
  }) async {
    final now = DateTime.now();
    final state = _terminalRateLimits.putIfAbsent(terminalRateKey, () => _TerminalRateState());
    state.failedCount += 1;

    final int nextUserFail = (user?.failedPinCount ?? 0) + 1;
    final int lockSecs = [
      _lockDurationSecondsForFailures(state.failedCount),
      _lockDurationSecondsForFailures(nextUserFail),
    ].reduce((a, b) => a > b ? a : b);

    final DateTime? lockUntil = lockSecs > 0 ? now.add(Duration(seconds: lockSecs)) : null;
    if (lockUntil != null) {
      state.lockedUntil = lockUntil;
    }

    if (user?.id != null) {
      await db.update(
        'users',
        {
          'failed_pin_count': nextUserFail,
          if (lockUntil != null) 'pin_locked_until': lockUntil.toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [user!.id],
      );
    }

    final actorName = user?.name ?? (attemptedUsername?.isNotEmpty == true ? attemptedUsername! : 'Tidak Dikenal');
    final objectId = user?.id != null ? 'USER-${user!.id}' : 'TERMINAL-$terminalId';
    await _recordSecurityAudit(
      db,
      userId: user?.id ?? 0,
      userName: actorName,
      userRole: user?.role ?? 'unknown',
      actionType: lockUntil != null ? 'pin_lockout' : 'login_gagal',
      objectId: objectId,
      beforeValue: 'fail_count=${user?.failedPinCount ?? state.failedCount - 1}',
      afterValue: 'fail_count=${user != null ? nextUserFail : state.failedCount}',
      details: lockUntil != null
          ? 'Akun/terminal dikunci $lockSecs detik setelah $methodLabel gagal di terminal $terminalId ($actorName).'
          : 'Percobaan $methodLabel gagal di terminal $terminalId ($actorName).',
    );

    if (lockUntil != null) {
      return AuthAttemptResult(
        status: AuthAttemptStatus.lockedOut,
        retryAfterSeconds: lockSecs,
        message: 'Terlalu banyak percobaan gagal. Akun/terminal dikunci selama $lockSecs detik.',
      );
    }

    return const AuthAttemptResult(
      status: AuthAttemptStatus.invalidCredentials,
      message: 'PIN atau username/password salah!',
    );
  }

  Future<UserModel> _migrateUserToV2IfNeeded(
    Database db,
    UserModel user, {
    String? verifiedPin,
    String? verifiedPassword,
  }) async {
    if (user.id == null) return user;

    String nextPinHash = user.pinHash;
    String nextPinSalt = user.pinSalt;
    String nextLookupHash = user.pinLookupHash;
    String nextPwHash = user.passwordHash;
    String nextPwSalt = user.passwordSalt;
    bool changed = false;

    if (verifiedPin != null) {
      final pinIsV2 = SecurityHelper.isV2PhcHash(user.pinHash) &&
          user.pinSalt.isNotEmpty &&
          (SecurityHelper.parseV2Hash(user.pinHash)?.iterations ?? 0) >= SecurityHelper.activeIterations;
      if (!pinIsV2 || user.pin.isNotEmpty || user.pinLookupHash.isEmpty) {
        final pair = await SecurityHelper.hashSecretV2(
          verifiedPin,
          domain: SecurityHelper.domainPin,
        );
        nextPinHash = pair.hash;
        nextPinSalt = pair.salt;
        nextLookupHash = await SecurityHelper.computePinLookupDigest(verifiedPin);
        changed = true;
      }
    }

    if (verifiedPassword != null) {
      final pwIsV2 = SecurityHelper.isV2PhcHash(user.passwordHash) &&
          user.passwordSalt.isNotEmpty &&
          (SecurityHelper.parseV2Hash(user.passwordHash)?.iterations ?? 0) >= SecurityHelper.activeIterations;
      if (!pwIsV2) {
        final pair = await SecurityHelper.hashSecretV2(
          verifiedPassword,
          domain: SecurityHelper.domainPassword,
        );
        nextPwHash = pair.hash;
        nextPwSalt = pair.salt;
        changed = true;
      }
    }

    final bothV2 = SecurityHelper.isV2PhcHash(nextPinHash) && SecurityHelper.isV2PhcHash(nextPwHash);
    final nextVersion = bothV2
        ? SecurityHelper.hashVersionV2Pbkdf2
        : (user.hashVersion.isNotEmpty ? user.hashVersion : SecurityHelper.hashVersionLegacyV1);

    final updates = <String, dynamic>{
      'failed_pin_count': 0,
      'pin_locked_until': null,
    };

    if (changed) {
      updates['pin'] = '';
      updates['pin_hash'] = nextPinHash;
      updates['pin_salt'] = nextPinSalt;
      updates['pin_lookup_hash'] = nextLookupHash;
      updates['password_hash'] = nextPwHash;
      updates['password_salt'] = nextPwSalt;
      updates['hash_version'] = nextVersion;
    }

    await db.update('users', updates, where: 'id = ?', whereArgs: [user.id]);

    if (changed) {
      await _recordSecurityAudit(
        db,
        userId: user.id!,
        userName: user.name,
        userRole: user.role,
        actionType: 'migrasi_kdf_akun',
        objectId: 'USER-${user.id}',
        beforeValue: 'hash_version=${user.hashVersion}',
        afterValue: 'hash_version=$nextVersion, has_pin_salt=${nextPinSalt.isNotEmpty}',
        details: 'Migrasi transparan kredensial ${user.name} ke PBKDF2-HMAC-SHA256 v2 (salt terpisah & Keystore pepper).',
      );
    }

    final refreshed = await db.query('users', where: 'id = ?', whereArgs: [user.id], limit: 1);
    return refreshed.isNotEmpty ? UserModel.fromMap(refreshed.first) : user;
  }

  Future<List<UserModel>> getUsers({bool includeInactive = false}) async {
    final db = await database;
    final res = includeInactive
        ? await db.query('users', orderBy: 'id ASC')
        : await db.query('users', where: 'is_active = ?', whereArgs: [1], orderBy: 'id ASC');
    return res.map((e) => UserModel.fromMap(e)).toList();
  }

  Future<bool> isPinAlreadyInUse(String pin, {int? excludeUserId}) async {
    final clean = pin.trim();
    if (clean.isEmpty) return false;
    final db = await database;
    final lookup = await SecurityHelper.computePinLookupDigest(clean);
    final indexed = await db.query(
      'users',
      where: excludeUserId != null
          ? 'is_active = 1 AND pin_lookup_hash = ? AND id != ?'
          : 'is_active = 1 AND pin_lookup_hash = ?',
      whereArgs: excludeUserId != null ? [lookup, excludeUserId] : [lookup],
    );
    for (final row in indexed) {
      final u = UserModel.fromMap(row);
      final salt = u.pinSalt.isNotEmpty ? u.pinSalt : u.passwordSalt;
      final res = await SecurityHelper.verifyCredential(
        secret: clean,
        storedHash: u.pinHash,
        legacyOrV2Salt: salt,
        expectedDomain: SecurityHelper.domainPin,
      );
      if (res.valid) return true;
    }

    final legacyRows = await db.query(
      'users',
      where: excludeUserId != null
          ? "(is_active = 1 AND (pin_lookup_hash = '' OR pin_lookup_hash IS NULL) AND id != ?)"
          : "(is_active = 1 AND (pin_lookup_hash = '' OR pin_lookup_hash IS NULL))",
      whereArgs: excludeUserId != null ? [excludeUserId] : null,
    );
    for (final row in legacyRows) {
      final u = UserModel.fromMap(row);
      if (u.pinHash.isNotEmpty) {
        final salt = u.pinSalt.isNotEmpty ? u.pinSalt : u.passwordSalt;
        final res = await SecurityHelper.verifyCredential(
          secret: clean,
          storedHash: u.pinHash,
          legacyOrV2Salt: salt,
          expectedDomain: SecurityHelper.domainPin,
        );
        if (res.valid) return true;
      } else if (u.pin.isNotEmpty && SecurityHelper.constantTimeEquals(u.pin, clean)) {
        return true;
      }
    }
    return false;
  }

  Future<AuthAttemptResult> authenticateWithPin(
    String pin, {
    int? userId,
    String terminalId = 'ADMIN',
  }) async {
    final db = await database;
    final now = DateTime.now();
    final cleanPin = pin.trim();
    final cleanTerm = terminalId.trim().isNotEmpty ? terminalId.trim() : 'ADMIN';
    final termRateKey = userId != null ? 'pin:$cleanTerm:uid:$userId' : 'pin:$cleanTerm';

    final termLock = _checkTerminalRateLimit(termRateKey, now);
    if (termLock != null) return termLock;

    if (cleanPin.isEmpty) {
      return await _recordFailedAuthAttempt(
        db,
        terminalRateKey: termRateKey,
        terminalId: cleanTerm,
        methodLabel: 'login PIN (kosong)',
      );
    }

    UserModel? targetedUser;
    final List<Map<String, dynamic>> candidates = [];
    if (userId != null) {
      final rows = await db.query('users', where: 'id = ? AND is_active = 1', whereArgs: [userId], limit: 1);
      if (rows.isEmpty) {
        return const AuthAttemptResult(
          status: AuthAttemptStatus.inactive,
          message: 'Akun kasir tidak ditemukan atau tidak aktif.',
        );
      }
      targetedUser = UserModel.fromMap(rows.first);
      if (targetedUser.isPinLocked(now)) {
        final rem = targetedUser.pinLockedUntil!.difference(now).inSeconds.clamp(1, 3600);
        return AuthAttemptResult(
          status: AuthAttemptStatus.lockedOut,
          retryAfterSeconds: rem,
          message: 'Akun "${targetedUser.name}" sedang terkunci. Coba lagi dalam $rem detik.',
        );
      }
      candidates.add(rows.first);
    } else {
      final lookup = await SecurityHelper.computePinLookupDigest(cleanPin);
      final fastRows = await db.query(
        'users',
        where: 'is_active = 1 AND pin_lookup_hash = ?',
        whereArgs: [lookup],
      );
      candidates.addAll(fastRows);
      // Fallback scan ONLY for non-v2 or unindexed legacy rows (never penalizes v2 miss with O(N)*600k cost)
      final legacyRows = await db.query(
        'users',
        where:
            "is_active = 1 AND (pin_lookup_hash = '' OR pin_lookup_hash IS NULL OR hash_version != ?)",
        whereArgs: [SecurityHelper.hashVersionV2Pbkdf2],
      );
      for (final r in legacyRows) {
        if (!candidates.any((c) => c['id'] == r['id'])) {
          candidates.add(r);
        }
      }
    }

    for (final map in candidates) {
      final user = UserModel.fromMap(map);
      if (user.isPinLocked(now)) continue;

      bool matched = false;
      if (user.pinHash.isNotEmpty) {
        final effectiveSalt = user.pinSalt.isNotEmpty ? user.pinSalt : user.passwordSalt;
        if (effectiveSalt.isNotEmpty || SecurityHelper.isV2PhcHash(user.pinHash)) {
          final res = await SecurityHelper.verifyCredential(
            secret: cleanPin,
            storedHash: user.pinHash,
            legacyOrV2Salt: effectiveSalt,
            expectedDomain: SecurityHelper.domainPin,
          );
          matched = res.valid;
        }
      } else if (user.pin.isNotEmpty && SecurityHelper.constantTimeEquals(user.pin, cleanPin)) {
        matched = true;
      }

      if (matched) {
        _terminalRateLimits.remove(termRateKey);
        final upgraded = await _migrateUserToV2IfNeeded(db, user, verifiedPin: cleanPin);
        return AuthAttemptResult(
          status: AuthAttemptStatus.success,
          user: upgraded,
        );
      }
    }

    return await _recordFailedAuthAttempt(
      db,
      terminalRateKey: termRateKey,
      terminalId: cleanTerm,
      user: targetedUser,
      methodLabel: 'login PIN',
    );
  }

  Future<AuthAttemptResult> authenticateWithPassword(
    String username,
    String password, {
    String terminalId = 'ADMIN',
  }) async {
    final db = await database;
    final now = DateTime.now();
    final cleanUser = username.trim().toLowerCase();
    final cleanTerm = terminalId.trim().isNotEmpty ? terminalId.trim() : 'ADMIN';
    final termRateKey = 'pw:$cleanTerm:$cleanUser';

    final termLock = _checkTerminalRateLimit(termRateKey, now);
    if (termLock != null) return termLock;

    final rows = await db.query(
      'users',
      where: 'LOWER(username) = ?',
      whereArgs: [cleanUser],
      limit: 1,
    );
    if (rows.isEmpty) {
      return await _recordFailedAuthAttempt(
        db,
        terminalRateKey: termRateKey,
        terminalId: cleanTerm,
        methodLabel: 'login password',
        attemptedUsername: cleanUser,
      );
    }

    final user = UserModel.fromMap(rows.first);
    if (!user.isActive) {
      return const AuthAttemptResult(
        status: AuthAttemptStatus.inactive,
        message: 'Akun ini telah dinonaktifkan oleh Owner.',
      );
    }
    if (user.isPinLocked(now)) {
      final rem = user.pinLockedUntil!.difference(now).inSeconds.clamp(1, 3600);
      return AuthAttemptResult(
        status: AuthAttemptStatus.lockedOut,
        retryAfterSeconds: rem,
        message: 'Akun "${user.name}" sedang terkunci. Coba lagi dalam $rem detik.',
      );
    }

    if (user.passwordHash.isNotEmpty &&
        (user.passwordSalt.isNotEmpty || SecurityHelper.isV2PhcHash(user.passwordHash))) {
      final res = await SecurityHelper.verifyCredential(
        secret: password,
        storedHash: user.passwordHash,
        legacyOrV2Salt: user.passwordSalt,
        expectedDomain: SecurityHelper.domainPassword,
      );
      if (res.valid) {
        _terminalRateLimits.remove(termRateKey);
        final upgraded = await _migrateUserToV2IfNeeded(db, user, verifiedPassword: password);
        return AuthAttemptResult(
          status: AuthAttemptStatus.success,
          user: upgraded,
        );
      }
    }

    return await _recordFailedAuthAttempt(
      db,
      terminalRateKey: termRateKey,
      terminalId: cleanTerm,
      user: user,
      methodLabel: 'login password',
      attemptedUsername: cleanUser,
    );
  }

  Future<UserModel?> loginWithPin(String pin, {int? userId, String terminalId = 'ADMIN'}) async {
    final res = await authenticateWithPin(pin, userId: userId, terminalId: terminalId);
    return res.user;
  }

  Future<UserModel?> loginWithPassword(
    String username,
    String password, {
    String terminalId = 'ADMIN',
  }) async {
    final res = await authenticateWithPassword(username, password, terminalId: terminalId);
    return res.user;
  }

  Future<UserModel?> login(String pin) => loginWithPin(pin);

  Future<int> insertUser(UserModel user) async {
    final db = await database;
    return await db.insert('users', user.toMap());
  }

  Future<int> updateUser(UserModel user) async {
    final db = await database;
    final rows = await db.update(
      'users',
      user.toMap(),
      where: 'id = ?',
      whereArgs: [user.id],
    );
    if (user.id != null) {
      // Force re-login on connected terminals when permissions, role, or PIN/status change.
      await db.update(
        'terminal_sessions',
        {'revoked_at': DateTime.now().toIso8601String()},
        where: 'cashier_id = ? AND (revoked_at IS NULL OR revoked_at = \'\')',
        whereArgs: [user.id],
      );
      onMultiDeviceEvent?.call('session_revoked', {
        'cashier_id': user.id,
        'reason': user.isActive ? 'Hak akses / akun diperbarui' : 'Akun dinonaktifkan',
      });
    }
    return rows;
  }

  Future<void> setUserActive(int userId, bool isActive) async {
    final db = await database;
    await db.update(
      'users',
      {'is_active': isActive ? 1 : 0},
      where: 'id = ?',
      whereArgs: [userId],
    );
    if (!isActive) {
      await db.update(
        'terminal_sessions',
        {'revoked_at': DateTime.now().toIso8601String()},
        where: 'cashier_id = ? AND (revoked_at IS NULL OR revoked_at = \'\')',
        whereArgs: [userId],
      );
      onMultiDeviceEvent?.call('session_revoked', {
        'cashier_id': userId,
        'reason': 'Akun dinonaktifkan oleh Admin',
      });
    }
  }

  // ================= CASH REGISTERS & ASSIGNMENTS =================
  Future<String> _getDrawerModeTxn(DatabaseExecutor db) async {
    final res = await db.query(
      'store_settings',
      where: 'key = ?',
      whereArgs: ['drawer_mode'],
      limit: 1,
    );
    if (res.isEmpty) return DrawerMode.sharedDrawer;
    return DrawerMode.normalize(res.first['value']?.toString());
  }

  Future<String> getDrawerMode() async {
    final db = await database;
    return await _getDrawerModeTxn(db);
  }

  Future<void> setDrawerMode(String mode, {UserModel? actor}) async {
    final normalized = DrawerMode.normalize(mode);
    final db = await database;
    await db.transaction((txn) async {
      final prevMode = await _getDrawerModeTxn(txn);
      if (prevMode != normalized && normalized == DrawerMode.sharedDrawer) {
        final openShifts = await txn.query('shifts', where: "status = 'open'");
        final distinctRegIds = openShifts.map((s) => (s['cash_register_id'] as num?)?.toInt() ?? 1).toSet();
        if (openShifts.length > 1 || distinctRegIds.any((id) => id != 1)) {
          throw StateError(
            'Tidak dapat beralih ke SHARED_DRAWER selama masih ada ${openShifts.length} shift individu terbuka. Tutup seluruh shift aktif terlebih dahulu.',
          );
        }
      }

      await txn.insert(
        'store_settings',
        {'key': 'drawer_mode', 'value': normalized},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      if (actor != null && prevMode != normalized) {
        await txn.insert('audit_logs', {
          'timestamp': DateTime.now().toIso8601String(),
          'user_id': actor.id ?? 0,
          'user_name': actor.name,
          'user_role': actor.role,
          'action_type': 'ubah_drawer_mode',
          'module': 'Pengaturan Toko',
          'object_id': 'SETTING-DRAWER-MODE',
          'before_value': prevMode,
          'after_value': normalized,
          'details': 'Mode laci kas diubah dari $prevMode menjadi $normalized',
        });
      }
    });
  }

  Future<List<CashRegisterModel>> getCashRegisters({bool includeInactive = false}) async {
    final db = await database;
    final rows = includeInactive
        ? await db.query('cash_registers', orderBy: 'id ASC')
        : await db.query('cash_registers', where: 'is_active = 1', orderBy: 'id ASC');
    return rows.map((e) => CashRegisterModel.fromMap(e)).toList();
  }

  Future<CashRegisterModel?> getCashRegisterById(int id) async {
    final db = await database;
    final rows = await db.query('cash_registers', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return CashRegisterModel.fromMap(rows.first);
  }

  Future<int> insertCashRegister(CashRegisterModel register) async {
    final db = await database;
    return await db.insert('cash_registers', register.toMap());
  }

  Future<void> updateCashRegister(CashRegisterModel register) async {
    if (register.id == null) throw ArgumentError('ID laci kas wajib diisi untuk pembaruan.');
    final db = await database;
    await db.update(
      'cash_registers',
      register.toMap(),
      where: 'id = ?',
      whereArgs: [register.id],
    );
  }

  Future<List<CashRegisterAssignmentModel>> getCashRegisterAssignments({
    bool includeInactive = true,
  }) async {
    final db = await database;
    final rows = includeInactive
        ? await db.query('cash_register_assignments', orderBy: 'priority DESC, id ASC')
        : await db.query(
            'cash_register_assignments',
            where: 'is_active = 1',
            orderBy: 'priority DESC, id ASC',
          );
    return rows.map((e) => CashRegisterAssignmentModel.fromMap(e)).toList();
  }

  Future<int> saveCashRegisterAssignment(
    CashRegisterAssignmentModel assignment, {
    UserModel? actor,
  }) async {
    if (assignment.specificityRank <= 0) {
      throw StateError('Assignment laci kas wajib menentukan minimal terminal_id atau cashier_id.');
    }
    final db = await database;
    return await db.transaction((txn) async {
      final regRows = await txn.query(
        'cash_registers',
        where: 'id = ?',
        whereArgs: [assignment.cashRegisterId],
        limit: 1,
      );
      if (regRows.isEmpty) {
        throw StateError('Laci kas ID ${assignment.cashRegisterId} tidak ditemukan.');
      }
      final reg = CashRegisterModel.fromMap(regRows.first);
      if (!reg.isActive && assignment.isActive) {
        throw StateError('Tidak dapat mengaktifkan assignment ke laci kas "${reg.name}" yang nonaktif.');
      }

      late final int id;
      if (assignment.id != null) {
        id = assignment.id!;
        await txn.update(
          'cash_register_assignments',
          assignment.toMap(),
          where: 'id = ?',
          whereArgs: [id],
        );
      } else {
        id = await txn.insert('cash_register_assignments', assignment.toMap());
      }

      if (actor != null) {
        await txn.insert('audit_logs', {
          'timestamp': DateTime.now().toIso8601String(),
          'user_id': actor.id ?? 0,
          'user_name': actor.name,
          'user_role': actor.role,
          'action_type': 'assign_laci_kas',
          'module': 'Pengaturan Toko',
          'object_id': 'REG-${reg.id}',
          'before_value': '',
          'after_value':
              'reg=${reg.registerCode}, terminal=${assignment.terminalId ?? "*"}, cashier=${assignment.cashierId ?? "*"}, priority=${assignment.priority}, active=${assignment.isActive}',
          'details': 'Penugasan laci kas ${reg.registerCode} (${reg.name}) diperbarui.',
        });
      }
      return id;
    });
  }

  Future<void> deleteCashRegisterAssignment(int assignmentId) async {
    final db = await database;
    await db.delete('cash_register_assignments', where: 'id = ?', whereArgs: [assignmentId]);
  }

  /// Deterministically resolves the authorized CashRegister for a cashier + terminal:
  /// 1. Exact (terminal_id + cashier_id) [rank 3]
  /// 2. Cashier-level (cashier_id) [rank 2]
  /// 3. Terminal-level (terminal_id) [rank 1]
  /// Ties within highest specificity are resolved by highest [priority]; conflicting equal-priority
  /// assignments targeting distinct registers are rejected deterministically rather than guessing.
  Future<CashRegisterModel> resolveAuthorizedCashRegisterTxn(
    DatabaseExecutor db, {
    required int cashierId,
    required String terminalId,
    int? requestedRegisterId,
  }) async {
    final cleanTerm = terminalId.trim().isNotEmpty ? terminalId.trim() : 'ADMIN';
    final drawerMode = await _getDrawerModeTxn(db);

    final assignmentRows = await db.query(
      'cash_register_assignments',
      where: 'is_active = 1 AND (terminal_id = ? OR terminal_id IS NULL) AND (cashier_id = ? OR cashier_id IS NULL)',
      whereArgs: [cleanTerm, cashierId],
    );

    final matching = assignmentRows
        .map((r) => CashRegisterAssignmentModel.fromMap(r))
        .where((a) => a.specificityRank > 0)
        .toList();

    if (matching.isNotEmpty) {
      matching.sort((a, b) {
        final rankCmp = b.specificityRank.compareTo(a.specificityRank);
        if (rankCmp != 0) return rankCmp;
        final prioCmp = b.priority.compareTo(a.priority);
        if (prioCmp != 0) return prioCmp;
        return (a.id ?? 0).compareTo(b.id ?? 0);
      });

      final topRank = matching.first.specificityRank;
      final topPriority = matching.first.priority;
      final topTied = matching
          .where((a) => a.specificityRank == topRank && a.priority == topPriority)
          .toList();
      final distinctTopRegisterIds = topTied.map((a) => a.cashRegisterId).toSet();

      if (distinctTopRegisterIds.length > 1) {
        throw StateError(
          'Konflik assignment laci kas terdeteksi (prioritas sama pada rank $topRank untuk terminal=$cleanTerm, kasir=$cashierId: register $distinctTopRegisterIds). Harap tetapkan prioritas unik di Pengaturan.',
        );
      }

      final targetRegId = distinctTopRegisterIds.first;
      if (requestedRegisterId != null && requestedRegisterId != targetRegId) {
        throw StateError(
          'Assignment tidak sah: terminal $cleanTerm / kasir #$cashierId hanya diizinkan menggunakan laci kas #$targetRegId (bukan #$requestedRegisterId).',
        );
      }

      final regRows = await db.query('cash_registers', where: 'id = ?', whereArgs: [targetRegId], limit: 1);
      if (regRows.isEmpty) {
        throw StateError('Laci kas tujuan (#$targetRegId) tidak ditemukan.');
      }
      final reg = CashRegisterModel.fromMap(regRows.first);
      if (!reg.isActive) {
        throw StateError('Laci kas "${reg.name}" (${reg.registerCode}) berstatus nonaktif dan tidak sah digunakan.');
      }
      return reg;
    }

    // No explicit rule matched:
    if (drawerMode == DrawerMode.individualDrawer) {
      throw StateError(
        'Mode INDIVIDUAL_DRAWER aktif: terminal $cleanTerm / kasir #$cashierId belum memiliki assignment laci kas yang sah.',
      );
    }

    // SHARED_DRAWER default fallback -> shared REG-MAIN (#1)
    if (requestedRegisterId != null && requestedRegisterId != 1) {
      throw StateError(
        'Laci kas #$requestedRegisterId belum memiliki assignment sah untuk terminal $cleanTerm / kasir #$cashierId.',
      );
    }
    final mainRows = await db.query('cash_registers', where: 'id = 1', limit: 1);
    if (mainRows.isEmpty) {
      throw StateError('Laci kas utama (REG-MAIN) tidak ditemukan di database.');
    }
    final mainReg = CashRegisterModel.fromMap(mainRows.first);
    if (!mainReg.isActive) {
      throw StateError('Laci kas utama (${mainReg.registerCode}) sedang dinonaktifkan.');
    }
    return mainReg;
  }

  Future<CashRegisterModel> resolveAuthorizedCashRegister({
    required int cashierId,
    required String terminalId,
    int? requestedRegisterId,
  }) async {
    final db = await database;
    return await resolveAuthorizedCashRegisterTxn(
      db,
      cashierId: cashierId,
      terminalId: terminalId,
      requestedRegisterId: requestedRegisterId,
    );
  }

  // ================= PRODUCTS CRUD =================
  Future<ProductModel> _hydrateProduct(DatabaseExecutor db, Map<String, dynamic> map) async {
    final p = ProductModel.fromMap(map);
    final unitsRes = await db.query('product_units', where: 'product_id = ?', whereArgs: [p.id]);
    final tiersRes = await db.query('tiered_prices', where: 'product_id = ?', whereArgs: [p.id]);
    final batchRes = await db.query('product_batches', where: 'product_id = ?', whereArgs: [p.id]);
    p.units = unitsRes.map((e) => ProductUnitModel.fromMap(e)).toList();
    p.tieredPrices = tiersRes.map((e) => TieredPriceModel.fromMap(e)).toList();
    p.batches = batchRes.map((e) => ProductBatchModel.fromMap(e)).toList();
    return p;
  }

  Future<List<ProductModel>> getProducts({String? query, String? category}) async {
    final db = await database;
    String whereClause = 'is_active = 1';
    final List<dynamic> whereArgs = [];

    if (category != null && category.isNotEmpty && category != 'Semua') {
      whereClause += ' AND category = ?';
      whereArgs.add(category);
    }

    if (query != null && query.isNotEmpty) {
      whereClause += ' AND (name LIKE ? OR code LIKE ? OR barcode LIKE ? OR imei_or_sn LIKE ? OR brand LIKE ?)';
      whereArgs.addAll(['%$query%', '%$query%', '%$query%', '%$query%', '%$query%']);
    }

    final res = await db.query('products', where: whereClause, whereArgs: whereArgs, orderBy: 'name ASC');
    final List<ProductModel> products = [];
    for (final map in res) {
      products.add(await _hydrateProduct(db, map));
    }
    return products;
  }

  Future<ProductScanMatch?> findProductAndUnitByBarcode(String barcode) async {
    final clean = barcode.trim();
    if (clean.isEmpty) return null;
    final db = await database;

    final res = await db.query(
      'products',
      where: '(barcode = ? OR code = ? OR imei_or_sn = ?) AND is_active = 1',
      whereArgs: [clean, clean, clean],
      limit: 1,
    );
    if (res.isNotEmpty) {
      final prod = await _hydrateProduct(db, res.first);
      return ProductScanMatch(product: prod);
    }

    final unitRes = await db.query(
      'product_units',
      where: 'barcode = ?',
      whereArgs: [clean],
      limit: 1,
    );
    if (unitRes.isNotEmpty) {
      final unit = ProductUnitModel.fromMap(unitRes.first);
      final prodRes = await db.query(
        'products',
        where: 'id = ? AND is_active = 1',
        whereArgs: [unit.productId],
        limit: 1,
      );
      if (prodRes.isNotEmpty) {
        final prod = await _hydrateProduct(db, prodRes.first);
        return ProductScanMatch(product: prod, matchedUnit: unit);
      }
    }
    return null;
  }

  Future<ProductModel?> getProductByBarcode(String barcode) async {
    final match = await findProductAndUnitByBarcode(barcode);
    return match?.product;
  }

  /// Checks whether [barcode] is already owned by another active product or unit.
  Future<BarcodeConflictResult?> findBarcodeConflict(
    String barcode, {
    int? excludeProductId,
  }) async {
    final clean = barcode.trim();
    if (clean.isEmpty) return null;
    final db = await database;

    final prodRows = await db.query(
      'products',
      where: 'barcode = ? AND is_active = 1',
      whereArgs: [clean],
    );
    for (final row in prodRows) {
      final id = row['id'] as int;
      if (excludeProductId != null && id == excludeProductId) continue;
      return BarcodeConflictResult(
        conflictingProduct: await _hydrateProduct(db, row),
        matchedOn: 'product_barcode',
      );
    }

    final codeRows = await db.query(
      'products',
      where: 'code = ? AND is_active = 1',
      whereArgs: [clean],
    );
    for (final row in codeRows) {
      final id = row['id'] as int;
      if (excludeProductId != null && id == excludeProductId) continue;
      return BarcodeConflictResult(
        conflictingProduct: await _hydrateProduct(db, row),
        matchedOn: 'product_code',
      );
    }

    final unitRows = await db.query(
      'product_units',
      where: 'barcode = ?',
      whereArgs: [clean],
    );
    for (final uRow in unitRows) {
      final pid = uRow['product_id'] as int;
      if (excludeProductId != null && pid == excludeProductId) continue;
      final pRows = await db.query(
        'products',
        where: 'id = ? AND is_active = 1',
        whereArgs: [pid],
        limit: 1,
      );
      if (pRows.isNotEmpty) {
        return BarcodeConflictResult(
          conflictingProduct: await _hydrateProduct(db, pRows.first),
          matchedOn: 'unit_barcode',
        );
      }
    }
    return null;
  }

  Future<int> insertProduct(ProductModel product) async {
    final db = await database;
    int nextVer = 1;
    final id = await db.transaction((txn) async {
      final newId = await txn.insert('products', product.toMap());
      await _saveProductRelations(txn, newId, product);
      nextVer = await bumpSyncVersionTxn(txn, productId: newId);
      return newId;
    });
    onMultiDeviceEvent?.call('catalog_changed', {'sync_version': nextVer, 'product_id': id});
    return id;
  }

  Future<void> updateProduct(ProductModel product) async {
    final db = await database;
    int nextVer = 1;
    await db.transaction((txn) async {
      await txn.update(
        'products',
        product.toMap(),
        where: 'id = ?',
        whereArgs: [product.id],
      );
      await txn.delete('product_units', where: 'product_id = ?', whereArgs: [product.id]);
      await txn.delete('tiered_prices', where: 'product_id = ?', whereArgs: [product.id]);
      await txn.delete('product_batches', where: 'product_id = ?', whereArgs: [product.id]);
      await _saveProductRelations(txn, product.id!, product);
      nextVer = await bumpSyncVersionTxn(txn, productId: product.id);
    });
    onMultiDeviceEvent?.call('catalog_changed', {'sync_version': nextVer, 'product_id': product.id});
  }

  Future<void> _saveProductRelations(DatabaseExecutor txn, int productId, ProductModel product) async {
    for (final unit in product.units) {
      await txn.insert('product_units', {
        'product_id': productId,
        'unit_name': unit.unitName,
        'conversion_factor': unit.conversionFactor,
        'selling_price': unit.sellingPrice,
        'barcode': unit.barcode,
      });
    }
    for (final tp in product.tieredPrices) {
      await txn.insert('tiered_prices', {
        'product_id': productId,
        'min_qty': tp.minQty,
        'price': tp.price,
      });
    }
    for (final batch in product.batches) {
      await txn.insert('product_batches', {
        'product_id': productId,
        'batch_number': batch.batchNumber,
        'expiry_date': batch.expiryDate.toIso8601String(),
        'stock_qty': batch.stockQty,
      });
    }
  }

  Future<void> deleteProduct(int id) async {
    final db = await database;
    final nextVer = await db.transaction((txn) async {
      await txn.update('products', {'is_active': 0}, where: 'id = ?', whereArgs: [id]);
      return bumpSyncVersionTxn(txn, productId: id);
    });
    onMultiDeviceEvent?.call('catalog_changed', {'sync_version': nextVer, 'product_id': id, 'deleted': true});
  }

  Future<List<ProductUnitModel>> getProductUnits(int productId) async {
    final db = await database;
    final res = await db.query('product_units', where: 'product_id = ?', whereArgs: [productId]);
    return res.map((e) => ProductUnitModel.fromMap(e)).toList();
  }

  Future<List<TieredPriceModel>> getTieredPrices(int productId) async {
    final db = await database;
    final res = await db.query('tiered_prices', where: 'product_id = ?', whereArgs: [productId]);
    return res.map((e) => TieredPriceModel.fromMap(e)).toList();
  }

  Future<List<ProductBatchModel>> getProductBatches(int productId) async {
    final db = await database;
    final res = await db.query('product_batches', where: 'product_id = ?', whereArgs: [productId]);
    return res.map((e) => ProductBatchModel.fromMap(e)).toList();
  }

  Future<List<Map<String, dynamic>>> getExpiringBatches() async {
    final db = await database;
    return await db.rawQuery('''
      SELECT b.*, p.name as product_name, p.code as product_code, p.base_unit
      FROM product_batches b
      JOIN products p ON b.product_id = p.id
      WHERE p.is_active = 1 AND b.stock_qty > 0
      ORDER BY b.expiry_date ASC
    ''');
  }

  // ================= INVENTORY LEDGER & CREDIT HELPERS =================
  Future<void> _recordStockMovement(
    Transaction txn, {
    required int productId,
    required String movementType,
    String bucket = 'sellable',
    required double qtyDelta,
    String referenceType = '',
    int? referenceId,
    String referenceNumber = '',
    int userId = 1,
    String userName = 'Sistem',
    String note = '',
    bool enforceNonNegative = true,
    bool recordWhenUntracked = false,
  }) async {
    final prodRows = await txn.query('products', where: 'id = ?', whereArgs: [productId], limit: 1);
    if (prodRows.isEmpty) {
      throw StateError('Produk ID $productId tidak ditemukan di database.');
    }
    final p = prodRows.first;
    final sku = (p['code'] ?? '').toString();
    final prodName = (p['name'] ?? '').toString();
    final tracksStock = (p['track_stock'] ?? 1) == 1 && (p['is_service'] ?? 0) != 1;
    final currentSellable = (p['stock'] as num?)?.toDouble() ?? 0.0;
    final currentQuarantine = (p['quarantine_stock'] as num?)?.toDouble() ?? 0.0;
    final currentDamaged = (p['damaged_stock'] as num?)?.toDouble() ?? 0.0;

    if (!tracksStock || bucket == 'none') {
      if (recordWhenUntracked || bucket == 'none') {
        await txn.insert('inventory_movements', {
          'product_id': productId,
          'sku': sku,
          'product_name': prodName,
          'movement_type': !tracksStock ? MovementTypes.noStockChange : movementType,
          'bucket': 'none',
          'qty_delta': 0.0,
          'stock_before': currentSellable,
          'stock_after': currentSellable,
          'bucket_before': 0.0,
          'bucket_after': 0.0,
          'reference_type': referenceType,
          'reference_id': referenceId,
          'reference_number': referenceNumber,
          'user_id': userId,
          'user_name': userName,
          'note': note,
          'created_at': DateTime.now().toIso8601String(),
        });
      }
      return;
    }

    late final String col;
    late final double bucketBefore;
    switch (bucket) {
      case 'quarantine':
        col = 'quarantine_stock';
        bucketBefore = currentQuarantine;
        break;
      case 'damaged':
        col = 'damaged_stock';
        bucketBefore = currentDamaged;
        break;
      case 'sellable':
      default:
        col = 'stock';
        bucketBefore = currentSellable;
        break;
    }

    final rawNext = bucketBefore + qtyDelta;
    if (enforceNonNegative && rawNext < -0.0001) {
      final bucketLabel = bucket == 'sellable'
          ? 'stok jual'
          : (bucket == 'quarantine' ? 'stok karantina' : 'stok rusak');
      throw StateError(
        'Mutasi $bucketLabel "$prodName" gagal: tersedia ${bucketBefore.toStringAsFixed(1)}, perubahan ${qtyDelta.toStringAsFixed(1)}.',
      );
    }
    final bucketAfter = rawNext < 0 ? 0.0 : rawNext;
    await txn.update(
      'products',
      {col: bucketAfter},
      where: 'id = ?',
      whereArgs: [productId],
    );
    await bumpSyncVersionTxn(txn, productId: productId);

    final stockAfter = bucket == 'sellable' ? bucketAfter : currentSellable;
    await txn.insert('inventory_movements', {
      'product_id': productId,
      'sku': sku,
      'product_name': prodName,
      'movement_type': movementType,
      'bucket': bucket,
      'qty_delta': qtyDelta,
      'stock_before': currentSellable,
      'stock_after': stockAfter,
      'bucket_before': bucketBefore,
      'bucket_after': bucketAfter,
      'reference_type': referenceType,
      'reference_id': referenceId,
      'reference_number': referenceNumber,
      'user_id': userId,
      'user_name': userName,
      'note': note,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<double> _getCustomerCreditBalanceTxn(DatabaseExecutor db, int customerId) async {
    final rows = await db.rawQuery('''
      SELECT COALESCE(SUM(
        CASE
          WHEN entry_type IN ('credit_issued', 'manual_adjustment') THEN amount
          WHEN entry_type IN ('credit_redeemed', 'credit_reversed') THEN -amount
          ELSE 0
        END
      ), 0.0) as bal
      FROM customer_credit_ledger
      WHERE customer_id = ?
    ''', [customerId]);
    final bal = (rows.first['bal'] as num?)?.toDouble() ?? 0.0;
    return bal < 0 ? 0.0 : bal;
  }

  Future<double> _appendCustomerCreditLedgerTxn(
    Transaction txn, {
    required int customerId,
    required String customerName,
    required String entryType,
    required double amount,
    String referenceType = '',
    int? referenceId,
    String referenceNumber = '',
    int userId = 1,
    String userName = 'Sistem',
    String note = '',
  }) async {
    if (amount <= 0) {
      throw StateError('Nominal mutasi saldo kredit harus lebih dari Rp 0.');
    }
    final before = await _getCustomerCreditBalanceTxn(txn, customerId);
    final isDeduction = entryType == CustomerCreditTypes.creditRedeemed ||
        entryType == CustomerCreditTypes.creditReversed;
    if (isDeduction && before + 0.001 < amount) {
      throw StateError(
        'Saldo kredit pelanggan "$customerName" tidak mencukupi (Tersedia: Rp ${before.toInt()}, Dibutuhkan: Rp ${amount.toInt()}).',
      );
    }
    final after = isDeduction ? (before - amount).clamp(0.0, double.infinity) : (before + amount);
    await txn.insert('customer_credit_ledger', {
      'customer_id': customerId,
      'customer_name': customerName,
      'entry_type': entryType,
      'amount': amount,
      'balance_before': before,
      'balance_after': after,
      'reference_type': referenceType,
      'reference_id': referenceId,
      'reference_number': referenceNumber,
      'user_id': userId,
      'user_name': userName,
      'note': note,
      'created_at': DateTime.now().toIso8601String(),
    });
    return after;
  }

  // ================= TRANSACTIONS & SHIFT SYNC =================
  Future<void> _ensureSufficientShiftCash(Transaction txn, int? shiftId, double amount) async {
    if (amount <= 0) return;
    if (shiftId == null) {
      throw StateError('Shift kasir harus dibuka sebelum mengeluarkan uang tunai dari laci.');
    }
    final shiftRows = await txn.query('shifts', where: 'id = ?', whereArgs: [shiftId], limit: 1);
    if (shiftRows.isEmpty) {
      throw StateError('Data shift aktif tidak ditemukan.');
    }
    final shift = ShiftModel.fromMap(shiftRows.first);
    if (!shift.isOpen) {
      throw StateError('Shift kasir sudah ditutup dan tidak dapat digunakan untuk transaksi kas.');
    }
    if (shift.expectedCash + 0.001 < amount) {
      throw StateError(
        'Saldo kas laci tidak mencukupi (Tersedia: Rp ${shift.expectedCash.toInt()}, Dibutuhkan: Rp ${amount.toInt()}).',
      );
    }
  }

  Future<int> insertTransaction(
    TransactionModel trx, {
    int? shiftId,
    String? terminalId,
    int? cashRegisterId,
  }) async {
    final db = await database;
    final targetShiftId = shiftId ?? trx.shiftId;
    return await db.transaction((txn) async {
      // 0. Idempotency check (must never duplicate sales, stock deduction, or cash totals)
      final cleanIdemKey = trx.idempotencyKey?.trim();
      if (cleanIdemKey != null && cleanIdemKey.isNotEmpty) {
        final dupRows = await txn.query(
          'transactions',
          columns: ['id'],
          where: 'idempotency_key = ?',
          whereArgs: [cleanIdemKey],
          limit: 1,
        );
        if (dupRows.isNotEmpty) {
          return (dupRows.first['id'] as num).toInt();
        }
      }

      // 1. Strict Shift Enforcement
      if (targetShiftId == null) {
        throw StateError('Kasir wajib membuka shift terlebih dahulu sebelum melakukan transaksi.');
      }
      final shiftRows = await txn.query('shifts', where: 'id = ?', whereArgs: [targetShiftId], limit: 1);
      if (shiftRows.isEmpty || ShiftModel.fromMap(shiftRows.first).status != 'open') {
        throw StateError('Shift tidak valid atau sudah ditutup. Silakan buka shift aktif terlebih dahulu.');
      }
      final activeShift = ShiftModel.fromMap(shiftRows.first);

      // 1b. Deterministic Cash Register & Assignment Enforcement
      final effectiveTerminal = (terminalId != null && terminalId.trim().isNotEmpty)
          ? terminalId.trim()
          : (trx.terminalId.trim().isNotEmpty ? trx.terminalId.trim() : activeShift.terminalId);
      final requestedRegId = cashRegisterId ?? trx.cashRegisterId;
      final authorizedReg = await resolveAuthorizedCashRegisterTxn(
        txn,
        cashierId: trx.cashierId,
        terminalId: effectiveTerminal,
        requestedRegisterId: requestedRegId,
      );
      if (activeShift.cashRegisterId != authorizedReg.id) {
        throw StateError(
          'Shift aktif #${activeShift.id} terikat pada laci kas #${activeShift.cashRegisterId}, bukan laci #${authorizedReg.id} (${authorizedReg.registerCode}).',
        );
      }
      if (activeShift.drawerMode == DrawerMode.individualDrawer &&
          activeShift.cashierId != trx.cashierId) {
        throw StateError(
          'Mode INDIVIDUAL_DRAWER: kasir #${trx.cashierId} (${trx.cashierName}) tidak diizinkan bertransaksi pada shift milik kasir #${activeShift.cashierId} (${activeShift.cashierName}).',
        );
      }

      // 2. Strict Registered Customer Rule for Kasbon or Saldo Kredit
      final needsRegisteredCust = trx.paymentMethod == 'kasbon' ||
          trx.paymentMethod == 'saldo_kredit' ||
          trx.creditUsed > 0;
      String resolvedCustomerName = trx.customerName;
      if (needsRegisteredCust) {
        if (trx.customerId == null) {
          throw StateError(
            trx.paymentMethod == 'kasbon'
                ? 'Kasbon hanya diperbolehkan untuk pelanggan yang sudah terdaftar.'
                : 'Penggunaan Saldo Kredit hanya diperbolehkan untuk pelanggan yang sudah terdaftar.',
          );
        }
        final custRows = await txn.query('customers', where: 'id = ?', whereArgs: [trx.customerId], limit: 1);
        if (custRows.isEmpty) {
          throw StateError('Pelanggan tidak ditemukan dalam database pelanggan terdaftar.');
        }
        final regName = (custRows.first['name'] ?? '').toString().trim();
        if (regName.isEmpty || regName.toLowerCase() == 'pelanggan umum') {
          throw StateError('Pelanggan Umum tidak diperbolehkan memakai Kasbon atau Saldo Kredit. Pilih pelanggan terdaftar.');
        }
        resolvedCustomerName = regName;
      }

      final double normalizedCreditUsed = trx.paymentMethod == 'saldo_kredit'
          ? (trx.creditUsed > 0 ? trx.creditUsed : trx.grandTotal)
          : trx.creditUsed;
      if (normalizedCreditUsed < 0 || normalizedCreditUsed > trx.grandTotal + 0.01) {
        throw StateError('Nominal saldo kredit yang digunakan tidak valid terhadap total transaksi.');
      }
      if (normalizedCreditUsed > 0 && trx.customerId != null) {
        final curBal = await _getCustomerCreditBalanceTxn(txn, trx.customerId!);
        if (curBal + 0.001 < normalizedCreditUsed) {
          throw StateError(
            'Saldo kredit pelanggan "$resolvedCustomerName" tidak mencukupi (Tersedia: Rp ${curBal.toInt()}, Dibutuhkan: Rp ${normalizedCreditUsed.toInt()}).',
          );
        }
      }

      // 3. Validate stock inside transaction before inserting
      for (final item in trx.items) {
        if (!item.isService) {
          final prodRows = await txn.query('products', where: 'id = ?', whereArgs: [item.productId], limit: 1);
          if (prodRows.isEmpty) {
            throw StateError('Produk "${item.productName}" tidak ditemukan di database.');
          }
          final p = prodRows.first;
          final tracksStock = (p['track_stock'] ?? 1) == 1;
          if (tracksStock) {
            final currentStock = (p['stock'] as num?)?.toDouble() ?? 0.0;
            if (currentStock + 0.0001 < item.baseStockQty) {
              throw StateError(
                'Stok "${item.productName}" tidak mencukupi (tersedia ${currentStock.toStringAsFixed(1)}, diminta ${item.baseStockQty.toStringAsFixed(1)}).',
              );
            }
          }
        }
      }

      final trxMap = trx.toMap();
      trxMap['shift_id'] = targetShiftId;
      trxMap['terminal_id'] = effectiveTerminal;
      trxMap['cash_register_id'] = authorizedReg.id;
      if (cleanIdemKey != null && cleanIdemKey.isNotEmpty) {
        trxMap['idempotency_key'] = cleanIdemKey;
      }
      trxMap['credit_used'] = normalizedCreditUsed;
      if (trx.customerId != null) trxMap['customer_id'] = trx.customerId;
      final trxId = await txn.insert('transactions', trxMap);

      for (final item in trx.items) {
        await txn.insert('transaction_items', {
          'transaction_id': trxId,
          'product_id': item.productId,
          'product_code': item.productCode,
          'product_name': item.productName,
          'unit_name': item.unitName,
          'conversion_factor': item.conversionFactor,
          'qty': item.qty,
          'unit_price': item.unitPrice,
          'discount': item.discount,
          'subtotal': item.subtotal,
          'cost_price': item.costPrice,
          'is_service': item.isService ? 1 : 0,
        });

        if (!item.isService) {
          await _recordStockMovement(
            txn,
            productId: item.productId,
            movementType: MovementTypes.saleOut,
            bucket: 'sellable',
            qtyDelta: -item.baseStockQty,
            referenceType: 'transaction',
            referenceId: trxId,
            referenceNumber: trx.invoiceNumber,
            userId: trx.cashierId,
            userName: trx.cashierName,
            note: 'Penjualan Nota #${trx.invoiceNumber} (${item.qty} ${item.unitName})',
          );
        }
      }

      // 4. Deduct customer credit ledger if used
      if (normalizedCreditUsed > 0 && trx.customerId != null) {
        await _appendCustomerCreditLedgerTxn(
          txn,
          customerId: trx.customerId!,
          customerName: resolvedCustomerName,
          entryType: CustomerCreditTypes.creditRedeemed,
          amount: normalizedCreditUsed,
          referenceType: 'transaction',
          referenceId: trxId,
          referenceNumber: trx.invoiceNumber,
          userId: trx.cashierId,
          userName: trx.cashierName,
          note: 'Dipakai belanja Nota #${trx.invoiceNumber}',
        );
        await txn.rawUpdate(
          'UPDATE shifts SET total_sales_credit = total_sales_credit + ? WHERE id = ?',
          [normalizedCreditUsed, targetShiftId],
        );
      }

      // 5. Sync active shift sales totals for remaining net due after credit
      final remainingDue = (trx.grandTotal - normalizedCreditUsed).clamp(0.0, double.infinity);
      if (trx.paymentMethod == 'tunai' && remainingDue > 0) {
        await txn.rawUpdate(
          'UPDATE shifts SET total_sales_cash = total_sales_cash + ? WHERE id = ?',
          [remainingDue, targetShiftId],
        );
      } else if (trx.paymentMethod == 'qris' && remainingDue > 0) {
        await txn.rawUpdate(
          'UPDATE shifts SET total_sales_qris = total_sales_qris + ? WHERE id = ?',
          [remainingDue, targetShiftId],
        );
      } else if (trx.paymentMethod == 'transfer' && remainingDue > 0) {
        await txn.rawUpdate(
          'UPDATE shifts SET total_sales_transfer = total_sales_transfer + ? WHERE id = ?',
          [remainingDue, targetShiftId],
        );
      } else if (trx.paymentMethod == 'kasbon' && remainingDue > 0) {
        await txn.rawUpdate(
          'UPDATE shifts SET total_sales_kasbon = total_sales_kasbon + ? WHERE id = ?',
          [remainingDue, targetShiftId],
        );
        if (trx.amountPaid > 0) {
          await txn.rawUpdate(
            'UPDATE shifts SET total_cash_in = total_cash_in + ? WHERE id = ?',
            [trx.amountPaid, targetShiftId],
          );
        }
      }

      // 6. Record Kasbon ledger & initial DP payment history
      if (trx.paymentMethod == 'kasbon' && remainingDue > 0) {
        final dueDate = DateTime.now().add(const Duration(days: 30));
        final debtId = await txn.insert('customer_debts', {
          'customer_id': trx.customerId,
          'customer_name': trx.customerName,
          'customer_phone': trx.customerPhone,
          'invoice_number': trx.invoiceNumber,
          'total_debt': remainingDue,
          'paid_debt': trx.amountPaid,
          'transaction_date': trx.date.toIso8601String(),
          'due_date': dueDate.toIso8601String(),
          'last_payment_date': trx.amountPaid > 0 ? trx.date.toIso8601String() : null,
          'note': trx.note,
        });

        if (trx.amountPaid > 0) {
          await txn.insert('customer_debt_payments', {
            'debt_id': debtId,
            'customer_id': trx.customerId,
            'amount': trx.amountPaid,
            'payment_method': 'tunai',
            'shift_id': targetShiftId,
            'cashier_name': trx.cashierName,
            'date': trx.date.toIso8601String(),
            'note': 'DP / Uang Muka Kasbon #${trx.invoiceNumber}',
          });
          await txn.insert('cash_flows', {
            'shift_id': targetShiftId,
            'terminal_id': effectiveTerminal,
            'cash_register_id': authorizedReg.id,
            'type': 'in',
            'category': 'DP Kasbon',
            'amount': trx.amountPaid,
            'payment_method': 'tunai',
            'account_name': 'Laci Kasir',
            'source_type': 'kasbon_bayar',
            'source_id': trx.invoiceNumber,
            'is_internal_transfer': 0,
            'note': 'DP Kasbon ${trx.customerName} (#${trx.invoiceNumber})',
            'date': trx.date.toIso8601String(),
            'cashier_name': trx.cashierName,
          });
        }
      }

      return trxId;
    });
  }

  Future<int> insertTransactionWithBroadcast(
    TransactionModel trx, {
    int? shiftId,
    String? terminalId,
    int? cashRegisterId,
  }) async {
    final trxId = await insertTransaction(
      trx,
      shiftId: shiftId,
      terminalId: terminalId,
      cashRegisterId: cashRegisterId,
    );
    final ids = trx.items.where((i) => !i.isService).map((i) => i.productId).toSet().toList();
    onMultiDeviceEvent?.call('stock_updated', {
      'transaction_id': trxId,
      'invoice_number': trx.invoiceNumber,
      'product_ids': ids,
    });
    return trxId;
  }

  /// Voids or reverses a transaction safely without mutating closed shifts retroactively.
  ///
  /// - Distinguishes [VoidTypes.prePaymentVoid] (payment never settled) vs
  ///   [VoidTypes.postPaymentReversal] (reversal/refund after completed payment).
  /// - If the original shift is already CLOSED (or void happens under another shift),
  ///   the original shift row is NEVER modified and `transactions.shift_id` stays intact.
  ///   Cash refunds are settled onto the active OPEN [shiftId] (or open shift) via `transaction_voids`
  ///   and `cash_flows`; if no valid open shift exists, cash refund / void is held with a clear StateError.
  Future<int> voidTransaction(
    int trxId, {
    int? shiftId,
    int? voidedBy,
    String? voidedByName,
    String reason = '',
    String? voidType,
    String? settlementTerminalId,
  }) async {
    final db = await database;
    return await db.transaction((txn) async {
      final res = await txn.query('transactions', where: 'id = ?', whereArgs: [trxId], limit: 1);
      if (res.isEmpty) return 0;
      final trx = TransactionModel.fromMap(res.first);
      if (trx.status == 'voided') {
        final existingVoids = await txn.query(
          'transaction_voids',
          columns: ['id'],
          where: 'original_transaction_id = ?',
          whereArgs: [trxId],
          limit: 1,
        );
        return existingVoids.isNotEmpty ? (existingVoids.first['id'] as num).toInt() : 0;
      }

      final effectiveVoidType = (voidType == VoidTypes.prePaymentVoid || voidType == VoidTypes.postPaymentReversal)
          ? voidType!
          : VoidTypes.postPaymentReversal;

      ShiftModel? origShift;
      if (trx.shiftId != null) {
        final sRows = await txn.query('shifts', where: 'id = ?', whereArgs: [trx.shiftId], limit: 1);
        if (sRows.isNotEmpty) origShift = ShiftModel.fromMap(sRows.first);
      }

      // Compute already-refunded cash from active returns on this invoice so net refundable cash is exact
      final returnedCashRows = await txn.rawQuery('''
        SELECT COALESCE(SUM(rs.amount), 0) as ret_cash
        FROM return_settlements rs
        JOIN return_orders ro ON rs.return_order_id = ro.id
        WHERE ro.transaction_id = ?
          AND COALESCE(ro.status, 'completed') != 'voided'
          AND rs.direction = 'out_to_customer'
          AND rs.method = 'tunai'
      ''', [trxId]);
      final alreadyReturnedCash = (returnedCashRows.first['ret_cash'] as num?)?.toDouble() ?? 0.0;
      final netDue = (trx.grandTotal - trx.creditUsed).clamp(0.0, double.infinity);
      final refundableCash = (effectiveVoidType == VoidTypes.postPaymentReversal && trx.paymentMethod == 'tunai')
          ? (netDue - alreadyReturnedCash).clamp(0.0, netDue)
          : 0.0;

      // Determine settlement shift strictly
      ShiftModel? settlementShift;
      if (shiftId != null) {
        final sRows = await txn.query('shifts', where: 'id = ?', whereArgs: [shiftId], limit: 1);
        if (sRows.isNotEmpty) {
          final cand = ShiftModel.fromMap(sRows.first);
          if (cand.isOpen) settlementShift = cand;
        }
        if (settlementShift == null && refundableCash > 0.001) {
          throw StateError(
            'Shift settlement #$shiftId sudah ditutup atau tidak valid. Refund tunai ditahan — buka shift aktif terlebih dahulu.',
          );
        }
      } else if (origShift != null && origShift.isOpen) {
        settlementShift = origShift;
      } else if (refundableCash > 0.001) {
        // Closed original shift and no explicit shiftId passed: check for open shift on requested register/terminal
        final openRows = await txn.query(
          'shifts',
          where: "status = 'open'",
          orderBy: 'id DESC',
          limit: 1,
        );
        if (openRows.isNotEmpty) {
          settlementShift = ShiftModel.fromMap(openRows.first);
        }
      }

      final bool isSameOpenOrigShift =
          origShift != null && origShift.isOpen && settlementShift != null && settlementShift.id == origShift.id;

      // CRITICAL: Closed-shift cash reversal MUST be held/blocked if no valid open settlement shift exists!
      if (!isSameOpenOrigShift &&
          effectiveVoidType == VoidTypes.postPaymentReversal &&
          trx.paymentMethod == 'tunai' &&
          refundableCash > 0.001) {
        if (settlementShift == null || !settlementShift.isOpen) {
          throw StateError(
            'Tidak ada shift aktif yang sah untuk refund tunai Nota #${trx.invoiceNumber}. Refund tunai ditahan hingga ada shift kasir terbuka.',
          );
        }
        await _ensureSufficientShiftCash(txn, settlementShift.id, refundableCash);
      }

      // 1. Restore unreturned inventory safely
      final alreadyReturnedRows = await txn.rawQuery('''
        SELECT ri.product_id, ri.unit_name, SUM(ri.return_qty) as total_ret
        FROM return_items ri
        JOIN return_orders ro ON ri.return_order_id = ro.id
        WHERE ro.transaction_id = ? AND COALESCE(ro.status, 'completed') != 'voided'
        GROUP BY ri.product_id, ri.unit_name
      ''', [trxId]);
      final returnedMap = <String, double>{
        for (final r in alreadyReturnedRows)
          '${r['product_id']}_${r['unit_name']}': (r['total_ret'] as num?)?.toDouble() ?? 0.0,
      };

      final itemsRes = await txn.query('transaction_items', where: 'transaction_id = ?', whereArgs: [trxId]);
      for (final m in itemsRes) {
        final item = TransactionItemModel.fromMap(m);
        if (!item.isService) {
          final key = '${item.productId}_${item.unitName}';
          final retQty = returnedMap[key] ?? 0.0;
          final unreturnedQty = (item.qty - retQty).clamp(0.0, item.qty);
          final restoreBase = unreturnedQty * item.conversionFactor;
          if (restoreBase > 0) {
            await _recordStockMovement(
              txn,
              productId: item.productId,
              movementType: MovementTypes.voidRestore,
              bucket: 'sellable',
              qtyDelta: restoreBase,
              referenceType: 'void_transaction',
              referenceId: trxId,
              referenceNumber: trx.invoiceNumber,
              userId: voidedBy ?? trx.cashierId,
              userName: (voidedByName != null && voidedByName.trim().isNotEmpty)
                  ? voidedByName.trim()
                  : trx.cashierName,
              note: 'Pembalikan stok void nota #${trx.invoiceNumber} (sisa belum retur: $unreturnedQty ${item.unitName})',
            );
          }
        }
      }

      // 2. Restore customer credit if used
      if (trx.creditUsed > 0 && trx.customerId != null) {
        await _appendCustomerCreditLedgerTxn(
          txn,
          customerId: trx.customerId!,
          customerName: trx.customerName,
          entryType: CustomerCreditTypes.creditIssued,
          amount: trx.creditUsed,
          referenceType: 'void_transaction',
          referenceId: trxId,
          referenceNumber: trx.invoiceNumber,
          userId: voidedBy ?? trx.cashierId,
          userName: (voidedByName != null && voidedByName.trim().isNotEmpty)
              ? voidedByName.trim()
              : trx.cashierName,
          note: 'Pengembalian saldo kredit dari pembatalan Nota #${trx.invoiceNumber}',
        );
      }

      // 3. Mark transaction status = 'voided' while keeping original shift_id & cash_register_id untouched!
      await txn.update('transactions', {'status': 'voided'}, where: 'id = ?', whereArgs: [trxId]);

      final nowIso = DateTime.now().toIso8601String();
      final effectiveVoidedBy = voidedBy ?? trx.cashierId;
      final effectiveVoidedByName =
          (voidedByName != null && voidedByName.trim().isNotEmpty) ? voidedByName.trim() : trx.cashierName;
      final effectiveTerm = settlementTerminalId ?? settlementShift?.terminalId ?? 'ADMIN';
      int? cashFlowId;

      if (isSameOpenOrigShift) {
        // Void inside the SAME open shift: adjust live open shift totals consistently
        final targetShiftId = origShift.id!;
        if (trx.creditUsed > 0) {
          await txn.rawUpdate(
            'UPDATE shifts SET total_sales_credit = MAX(0, total_sales_credit - ?) WHERE id = ?',
            [trx.creditUsed, targetShiftId],
          );
        }
        if (trx.paymentMethod == 'tunai' && netDue > 0) {
          await txn.rawUpdate(
            'UPDATE shifts SET total_sales_cash = MAX(0, total_sales_cash - ?) WHERE id = ?',
            [netDue, targetShiftId],
          );
        } else if (trx.paymentMethod == 'qris' && netDue > 0) {
          await txn.rawUpdate(
            'UPDATE shifts SET total_sales_qris = MAX(0, total_sales_qris - ?) WHERE id = ?',
            [netDue, targetShiftId],
          );
        } else if (trx.paymentMethod == 'transfer' && netDue > 0) {
          await txn.rawUpdate(
            'UPDATE shifts SET total_sales_transfer = MAX(0, total_sales_transfer - ?) WHERE id = ?',
            [netDue, targetShiftId],
          );
        } else if (trx.paymentMethod == 'kasbon' && netDue > 0) {
          await txn.rawUpdate(
            'UPDATE shifts SET total_sales_kasbon = MAX(0, total_sales_kasbon - ?) WHERE id = ?',
            [netDue, targetShiftId],
          );
        }
      } else if (effectiveVoidType == VoidTypes.postPaymentReversal) {
        // CLOSED original shift (or cross-shift void): NEVER touch closed original shift!
        if (trx.paymentMethod == 'tunai' && refundableCash > 0.001 && settlementShift?.id != null) {
          cashFlowId = await _insertCashFlowInTxn(
            txn,
            shiftId: settlementShift!.id,
            terminalId: settlementShift.terminalId,
            cashRegisterId: settlementShift.cashRegisterId,
            type: 'out',
            category: 'Refund Void Nota Shift Tertutup',
            amount: refundableCash,
            paymentMethod: 'tunai',
            accountName: 'Laci Kasir',
            sourceType: 'void_reversal',
            sourceId: trx.invoiceNumber,
            note: 'Refund tunai void Nota #${trx.invoiceNumber} (shift asal #${trx.shiftId ?? "-"}): ${reason.trim()}',
            cashierName: effectiveVoidedByName,
          );
          await txn.rawUpdate(
            'UPDATE shifts SET total_return_cash = total_return_cash + ? WHERE id = ?',
            [refundableCash, settlementShift.id],
          );
        } else if ((trx.paymentMethod == 'qris' || trx.paymentMethod == 'transfer') && netDue > 0.001) {
          cashFlowId = await _insertCashFlowInTxn(
            txn,
            shiftId: null,
            terminalId: effectiveTerm,
            cashRegisterId: settlementShift?.cashRegisterId ?? trx.cashRegisterId,
            type: 'out',
            category: 'Reversal Void Non-Tunai',
            amount: netDue,
            paymentMethod: trx.paymentMethod,
            accountName: trx.paymentMethod == 'transfer' ? 'Rekening Bank' : 'QRIS / E-Wallet',
            sourceType: 'void_reversal',
            sourceId: trx.invoiceNumber,
            note: 'Reversal non-tunai void Nota #${trx.invoiceNumber}: ${reason.trim()}',
            cashierName: effectiveVoidedByName,
          );
        }
      }

      // 4. Preserve debt payment history cleanly if a kasbon transaction is voided
      if (trx.paymentMethod == 'kasbon') {
        final debtRows = await txn.query(
          'customer_debts',
          where: 'invoice_number = ?',
          whereArgs: [trx.invoiceNumber],
          limit: 1,
        );
        if (debtRows.isNotEmpty) {
          final debt = CustomerDebtModel.fromMap(debtRows.first);
          await txn.update(
            'customer_debts',
            {
              'total_debt': debt.paidDebt, // Zeroes unpaid remainder without deleting payment ledger history
              'note': '${debt.note} [NOTA VOID - Sisa Tagihan Dibatalkan, Riwayat Bayar Dipertahankan]'.trim(),
            },
            where: 'id = ?',
            whereArgs: [debt.id],
          );
        }
      }

      // 5. Record immutable void/reversal event in `transaction_voids`
      final String recordedRefundMethod = effectiveVoidType == VoidTypes.prePaymentVoid
          ? 'none'
          : (trx.paymentMethod == 'kasbon' ? 'kasbon_cancel' : trx.paymentMethod);
      final double recordedRefundAmount = effectiveVoidType == VoidTypes.prePaymentVoid
          ? 0.0
          : (trx.paymentMethod == 'tunai' ? refundableCash : netDue);

      final voidModel = TransactionVoidModel(
        originalTransactionId: trxId,
        originalInvoiceNumber: trx.invoiceNumber,
        originalShiftId: trx.shiftId,
        originalCashRegisterId: trx.cashRegisterId,
        voidType: effectiveVoidType,
        refundMethod: recordedRefundMethod,
        refundAmount: recordedRefundAmount,
        creditRestored: trx.creditUsed,
        voidedAt: DateTime.parse(nowIso),
        voidedBy: effectiveVoidedBy,
        voidedByName: effectiveVoidedByName,
        voidReason: reason.trim(),
        settlementShiftId: settlementShift?.id,
        settlementCashRegisterId: settlementShift?.cashRegisterId,
        settlementTerminalId: effectiveTerm,
        cashFlowId: cashFlowId,
      );
      return await txn.insert('transaction_voids', voidModel.toMap());
    });
  }

  Future<List<TransactionVoidModel>> getTransactionVoids({
    int? originalTransactionId,
    int? settlementShiftId,
  }) async {
    final db = await database;
    final whereParts = <String>[];
    final args = <dynamic>[];
    if (originalTransactionId != null) {
      whereParts.add('original_transaction_id = ?');
      args.add(originalTransactionId);
    }
    if (settlementShiftId != null) {
      whereParts.add('settlement_shift_id = ?');
      args.add(settlementShiftId);
    }
    final rows = await db.query(
      'transaction_voids',
      where: whereParts.isEmpty ? null : whereParts.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'id DESC',
    );
    return rows.map((e) => TransactionVoidModel.fromMap(e)).toList();
  }

  Future<TransactionModel?> getTransactionByInvoice(String invoiceNumber) async {
    final db = await database;
    final res = await db.query(
      'transactions',
      where: 'invoice_number = ?',
      whereArgs: [invoiceNumber],
      limit: 1,
    );
    if (res.isEmpty) return null;

    final trx = TransactionModel.fromMap(res.first);
    final itemRes = await db.query(
      'transaction_items',
      where: 'transaction_id = ?',
      whereArgs: [trx.id],
    );
    trx.items = itemRes.map((e) => TransactionItemModel.fromMap(e)).toList();
    return trx;
  }

  Future<List<TransactionModel>> getRecentTransactions({int limit = 100}) async {
    final db = await database;
    final res = await db.query(
      'transactions',
      orderBy: 'date DESC',
      limit: limit,
    );
    final List<TransactionModel> list = [];
    for (final map in res) {
      final trx = TransactionModel.fromMap(map);
      final itemRes = await db.query(
        'transaction_items',
        where: 'transaction_id = ?',
        whereArgs: [trx.id],
      );
      trx.items = itemRes.map((e) => TransactionItemModel.fromMap(e)).toList();
      list.add(trx);
    }
    return list;
  }

  Future<List<TransactionModel>> getTransactionsByDateRange(
    DateTime start,
    DateTime end, {
    String? query,
    String? barcode,
    int limit = 200,
  }) async {
    final db = await database;
    final startIso = DateTime(start.year, start.month, start.day).toIso8601String();
    final endIso = DateTime(end.year, end.month, end.day, 23, 59, 59, 999).toIso8601String();

    final res = await db.query(
      'transactions',
      where: 'date >= ? AND date <= ?',
      whereArgs: [startIso, endIso],
      orderBy: 'date DESC',
      limit: limit,
    );

    final List<TransactionModel> list = [];
    final qLower = query?.trim().toLowerCase() ?? '';
    final bLower = barcode?.trim().toLowerCase() ?? '';

    for (final map in res) {
      final trx = TransactionModel.fromMap(map);
      final itemRes = await db.query(
        'transaction_items',
        where: 'transaction_id = ?',
        whereArgs: [trx.id],
      );
      trx.items = itemRes.map((e) => TransactionItemModel.fromMap(e)).toList();

      if (qLower.isNotEmpty) {
        final matchTrx = trx.invoiceNumber.toLowerCase().contains(qLower) ||
            trx.customerName.toLowerCase().contains(qLower) ||
            trx.items.any((i) =>
                i.productName.toLowerCase().contains(qLower) ||
                i.productCode.toLowerCase().contains(qLower));
        if (!matchTrx) continue;
      }
      if (bLower.isNotEmpty) {
        final matchBar = await db.rawQuery('''
          SELECT ti.id FROM transaction_items ti
          JOIN products p ON ti.product_id = p.id
          LEFT JOIN product_units pu ON pu.product_id = p.id
          WHERE ti.transaction_id = ? AND (LOWER(p.barcode) = ? OR LOWER(p.code) = ? OR LOWER(pu.barcode) = ?)
          LIMIT 1
        ''', [trx.id, bLower, bLower, bLower]);
        if (matchBar.isEmpty) continue;
      }
      list.add(trx);
    }
    return list;
  }

  Future<List<ReturnOrderModel>> getReturnOrders({
    DateTime? start,
    DateTime? end,
    int limit = 100,
    bool includeVoided = true,
  }) async {
    final db = await database;
    final whereParts = <String>[];
    final whereArgs = <dynamic>[];
    if (start != null && end != null) {
      whereParts.add('date >= ? AND date <= ?');
      whereArgs.addAll([
        DateTime(start.year, start.month, start.day).toIso8601String(),
        DateTime(end.year, end.month, end.day, 23, 59, 59, 999).toIso8601String(),
      ]);
    }
    if (!includeVoided) {
      whereParts.add("COALESCE(status, 'completed') != 'voided'");
    }
    final res = await db.query(
      'return_orders',
      where: whereParts.isEmpty ? null : whereParts.join(' AND '),
      whereArgs: whereArgs.isEmpty ? null : whereArgs,
      orderBy: 'date DESC, id DESC',
      limit: limit,
    );
    final List<ReturnOrderModel> list = [];
    for (final m in res) {
      list.add(await _hydrateReturnOrder(db, m));
    }
    return list;
  }

  Future<ReturnOrderModel?> getReturnOrderById(int returnOrderId) async {
    final db = await database;
    final res = await db.query('return_orders', where: 'id = ?', whereArgs: [returnOrderId], limit: 1);
    if (res.isEmpty) return null;
    return await _hydrateReturnOrder(db, res.first);
  }

  Future<ReturnOrderModel> _hydrateReturnOrder(DatabaseExecutor db, Map<String, dynamic> map) async {
    final ro = ReturnOrderModel.fromMap(map);
    final itemRows = await db.query('return_items', where: 'return_order_id = ?', whereArgs: [ro.id]);
    ro.items = itemRows.map((e) => ReturnItemModel.fromMap(e)).toList();
    final exRows = await db.query('return_exchange_items', where: 'return_order_id = ?', whereArgs: [ro.id]);
    ro.exchangeItems = exRows.map((e) => ReturnExchangeItemModel.fromMap(e)).toList();
    final stRows = await db.query('return_settlements', where: 'return_order_id = ?', whereArgs: [ro.id]);
    ro.settlements = stRows.map((e) => ReturnSettlementModel.fromMap(e)).toList();
    return ro;
  }

  // ================= RETURNS (RETUR BARANG & TUKAR BARANG) =================
  /// Computes effective historical per-unit refund value for an item on [trx],
  /// preserving item-level discounts, tiered prices, and proportional cart discounts/taxes
  /// instead of reading current catalog prices.
  static double effectiveUnitPriceForReturn(TransactionModel trx, TransactionItemModel item) {
    if (item.qty <= 0) return item.unitPrice;
    final perUnitItemNet = item.subtotal / item.qty;
    if (trx.subtotal > 0.01 && (trx.discountTotal.abs() > 0.01 || trx.taxAmount.abs() > 0.01)) {
      final headerRatio = trx.grandTotal / trx.subtotal;
      return (perUnitItemNet * headerRatio).clamp(0.0, double.infinity);
    }
    return perUnitItemNet.clamp(0.0, double.infinity);
  }

  Future<Map<String, double>> getReturnedQuantitiesForTransaction(int trxId) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT ri.product_id, ri.unit_name, SUM(ri.return_qty) as returned_qty
      FROM return_items ri
      JOIN return_orders ro ON ri.return_order_id = ro.id
      WHERE ro.transaction_id = ? AND COALESCE(ro.status, 'completed') != 'voided'
      GROUP BY ri.product_id, ri.unit_name
    ''', [trxId]);

    final map = <String, double>{};
    for (final r in rows) {
      final key = '${r['product_id']}_${r['unit_name']}';
      map[key] = (r['returned_qty'] as num?)?.toDouble() ?? 0.0;
    }
    return map;
  }

  Future<bool> _isRegisteredCustomerTxn(Transaction txn, int? customerId) async {
    if (customerId == null) return false;
    final rows = await txn.query('customers', where: 'id = ?', whereArgs: [customerId], limit: 1);
    if (rows.isEmpty) return false;
    final name = (rows.first['name'] ?? '').toString().trim().toLowerCase();
    return name.isNotEmpty && name != 'pelanggan umum';
  }

  Future<void> _ensureOpenShiftTxn(Transaction txn, int? shiftId) async {
    if (shiftId == null) {
      throw StateError('Shift kasir harus terbuka untuk memproses mutasi uang tunai laci.');
    }
    final shiftRows = await txn.query('shifts', where: 'id = ?', whereArgs: [shiftId], limit: 1);
    if (shiftRows.isEmpty || ShiftModel.fromMap(shiftRows.first).status != 'open') {
      throw StateError('Shift kasir tidak valid atau sudah ditutup.');
    }
  }

  Future<int> _insertCashFlowInTxn(
    Transaction txn, {
    int? shiftId,
    String? terminalId,
    int? cashRegisterId,
    required String type,
    required String category,
    required double amount,
    required String paymentMethod,
    required String accountName,
    required String sourceType,
    required String sourceId,
    required String note,
    required String cashierName,
  }) async {
    String resolvedTerm = (terminalId != null && terminalId.trim().isNotEmpty) ? terminalId.trim() : 'ADMIN';
    int resolvedReg = cashRegisterId ?? 1;
    if (shiftId != null && (terminalId == null || cashRegisterId == null)) {
      final sRows = await txn.query(
        'shifts',
        columns: ['terminal_id', 'cash_register_id'],
        where: 'id = ?',
        whereArgs: [shiftId],
        limit: 1,
      );
      if (sRows.isNotEmpty) {
        resolvedTerm = terminalId ?? (sRows.first['terminal_id']?.toString() ?? 'ADMIN');
        resolvedReg = cashRegisterId ?? ((sRows.first['cash_register_id'] as num?)?.toInt() ?? 1);
      }
    }
    return await txn.insert('cash_flows', {
      'shift_id': shiftId,
      'terminal_id': resolvedTerm,
      'cash_register_id': resolvedReg,
      'type': type,
      'category': category,
      'amount': amount,
      'payment_method': paymentMethod,
      'account_name': accountName,
      'source_type': sourceType,
      'source_id': sourceId,
      'is_internal_transfer': 0,
      'note': note,
      'date': DateTime.now().toIso8601String(),
      'cashier_name': cashierName,
    });
  }

  Future<void> _settleOutflowTxn(
    Transaction txn, {
    required int retId,
    required ReturnOrderModel ret,
    required String method,
    required double amount,
    required int? shiftId,
    required int? resolvedCustomerId,
    required String resolvedCustomerName,
    String? excessFallbackMethod,
    String labelPrefix = 'Retur',
  }) async {
    if (amount <= 0.001) return;
    final nowIso = DateTime.now().toIso8601String();

    switch (method) {
      case RefundMethods.tunai:
        await _ensureSufficientShiftCash(txn, shiftId, amount);
        int? settlementRegId;
        if (shiftId != null) {
          final sRows = await txn.query(
            'shifts',
            columns: ['cash_register_id'],
            where: 'id = ?',
            whereArgs: [shiftId],
            limit: 1,
          );
          if (sRows.isNotEmpty) {
            settlementRegId = (sRows.first['cash_register_id'] as num?)?.toInt() ?? 1;
          }
        }
        final cfId = await _insertCashFlowInTxn(
          txn,
          shiftId: shiftId,
          cashRegisterId: settlementRegId,
          type: 'out',
          category: '$labelPrefix Penjualan',
          amount: amount,
          paymentMethod: 'tunai',
          accountName: 'Laci Kasir',
          sourceType: 'retur',
          sourceId: ret.returnNumber,
          note: '$labelPrefix Nota #${ret.invoiceNumber} (${ret.returnNumber})',
          cashierName: ret.cashierName,
        );
        if (shiftId != null) {
          await txn.rawUpdate(
            'UPDATE shifts SET total_return_cash = total_return_cash + ? WHERE id = ?',
            [amount, shiftId],
          );
        }
        await txn.insert('return_settlements', {
          'return_order_id': retId,
          'settlement_type': 'refund_tunai',
          'direction': 'out_to_customer',
          'method': RefundMethods.tunai,
          'amount': amount,
          'account_name': 'Laci Kasir',
          'shift_id': shiftId,
          'settlement_shift_id': shiftId,
          'settlement_cash_register_id': settlementRegId,
          'customer_id': resolvedCustomerId,
          'cash_flow_id': cfId,
          'note': '$labelPrefix tunai dari laci kasir',
          'created_at': nowIso,
        });
        break;

      case RefundMethods.transfer:
        final bankAccount = ret.transferAccount.trim().isNotEmpty ? ret.transferAccount.trim() : 'Rekening Bank';
        final cfId = await _insertCashFlowInTxn(
          txn,
          shiftId: null,
          type: 'out',
          category: '$labelPrefix Transfer',
          amount: amount,
          paymentMethod: 'transfer',
          accountName: bankAccount,
          sourceType: 'retur',
          sourceId: ret.returnNumber,
          note: '$labelPrefix transfer #${ret.invoiceNumber} (${ret.returnNumber}) Ref: ${ret.transferReference.isEmpty ? "-" : ret.transferReference}',
          cashierName: ret.cashierName,
        );
        await txn.insert('return_settlements', {
          'return_order_id': retId,
          'settlement_type': 'refund_transfer',
          'direction': 'out_to_customer',
          'method': RefundMethods.transfer,
          'amount': amount,
          'account_name': bankAccount,
          'reference_number': ret.transferReference.trim(),
          'customer_id': resolvedCustomerId,
          'cash_flow_id': cfId,
          'note': '$labelPrefix transfer bank ke $resolvedCustomerName',
          'created_at': nowIso,
        });
        break;

      case RefundMethods.qrisManual:
        final ewalletAcc = ret.transferAccount.trim().isNotEmpty ? ret.transferAccount.trim() : 'QRIS / E-Wallet';
        final cfId = await _insertCashFlowInTxn(
          txn,
          shiftId: null,
          type: 'out',
          category: '$labelPrefix QRIS/E-Wallet',
          amount: amount,
          paymentMethod: 'qris',
          accountName: ewalletAcc,
          sourceType: 'retur',
          sourceId: ret.returnNumber,
          note: '$labelPrefix QRIS/E-Wallet #${ret.invoiceNumber} (${ret.returnNumber})',
          cashierName: ret.cashierName,
        );
        await txn.insert('return_settlements', {
          'return_order_id': retId,
          'settlement_type': 'refund_qris',
          'direction': 'out_to_customer',
          'method': RefundMethods.qrisManual,
          'amount': amount,
          'account_name': ewalletAcc,
          'reference_number': ret.transferReference.trim(),
          'customer_id': resolvedCustomerId,
          'cash_flow_id': cfId,
          'note': '$labelPrefix manual via $ewalletAcc',
          'created_at': nowIso,
        });
        break;

      case RefundMethods.saldoKredit:
        final isRegistered = await _isRegisteredCustomerTxn(txn, resolvedCustomerId);
        if (!isRegistered || resolvedCustomerId == null) {
          throw StateError(
            'Saldo Kredit Retur hanya berlaku untuk pelanggan terdaftar (bukan Pelanggan Umum). Pilih pelanggan terdaftar terlebih dahulu.',
          );
        }
        await _appendCustomerCreditLedgerTxn(
          txn,
          customerId: resolvedCustomerId,
          customerName: resolvedCustomerName,
          entryType: CustomerCreditTypes.creditIssued,
          amount: amount,
          referenceType: 'return_order',
          referenceId: retId,
          referenceNumber: ret.returnNumber,
          userId: ret.cashierId,
          userName: ret.cashierName,
          note: 'Kredit dari Retur #${ret.returnNumber} (Nota #${ret.invoiceNumber})',
        );
        await txn.insert('return_settlements', {
          'return_order_id': retId,
          'settlement_type': 'saldo_kredit',
          'direction': 'credit_issued',
          'method': RefundMethods.saldoKredit,
          'amount': amount,
          'account_name': 'Saldo Kredit Pelanggan',
          'customer_id': resolvedCustomerId,
          'note': 'Penambahan saldo kredit $resolvedCustomerName',
          'created_at': nowIso,
        });
        break;

      case RefundMethods.potongPiutang:
        // First prioritize invoice debt, then any active debts of this customer (oldest due_date first)
        final candidateDebts = <Map<String, dynamic>>[];
        final invoiceDebts = await txn.query(
          'customer_debts',
          where: 'invoice_number = ? AND (total_debt - paid_debt) > 0.001',
          whereArgs: [ret.invoiceNumber],
          orderBy: 'id ASC',
        );
        candidateDebts.addAll(invoiceDebts);

        if (resolvedCustomerId != null) {
          final otherDebts = await txn.query(
            'customer_debts',
            where:
                "(customer_id = ? OR (customer_id IS NULL AND LOWER(customer_name) = LOWER(?))) AND invoice_number != ? AND (total_debt - paid_debt) > 0.001",
            whereArgs: [resolvedCustomerId, resolvedCustomerName, ret.invoiceNumber],
            orderBy: 'due_date ASC, id ASC',
          );
          candidateDebts.addAll(otherDebts);
        }

        double remainingToOffset = amount;
        double totalOffsetApplied = 0.0;
        for (final row in candidateDebts) {
          if (remainingToOffset <= 0.001) break;
          final d = CustomerDebtModel.fromMap(row);
          if (d.remainingDebt <= 0.001 || d.id == null) continue;
          final applied = remainingToOffset.clamp(0.0, d.remainingDebt);
          final newPaid = (d.paidDebt + applied).clamp(0.0, d.totalDebt);
          await txn.update(
            'customer_debts',
            {
              'paid_debt': newPaid,
              'last_payment_date': nowIso,
              'note': '${d.note} [Potong Retur #${ret.returnNumber}]'.trim(),
            },
            where: 'id = ?',
            whereArgs: [d.id],
          );
          await txn.insert('customer_debt_payments', {
            'debt_id': d.id,
            'customer_id': d.customerId ?? resolvedCustomerId,
            'amount': applied,
            'payment_method': 'retur',
            'shift_id': shiftId,
            'cashier_name': ret.cashierName,
            'date': nowIso,
            'note': 'Potong piutang dari Retur #${ret.returnNumber} (Nota #${d.invoiceNumber})',
          });
          await txn.insert('return_settlements', {
            'return_order_id': retId,
            'settlement_type': 'potong_piutang',
            'direction': 'debt_offset',
            'method': RefundMethods.potongPiutang,
            'amount': applied,
            'account_name': 'Kasbon #${d.invoiceNumber}',
            'reference_number': d.invoiceNumber,
            'customer_id': d.customerId ?? resolvedCustomerId,
            'note': 'Pemotongan piutang Nota #${d.invoiceNumber}',
            'created_at': nowIso,
          });
          remainingToOffset -= applied;
          totalOffsetApplied += applied;
        }

        if (totalOffsetApplied <= 0.001) {
          throw StateError(
            'Pelanggan tidak memiliki sisa piutang kasbon aktif untuk dipotong. Gunakan metode Tunai, Transfer, atau Saldo Kredit.',
          );
        }

        if (remainingToOffset > 0.01) {
          final isRegCust = await _isRegisteredCustomerTxn(txn, resolvedCustomerId);
          final chosenExcess = (excessFallbackMethod != null &&
                  excessFallbackMethod.isNotEmpty &&
                  excessFallbackMethod != RefundMethods.potongPiutang &&
                  excessFallbackMethod != RefundMethods.tukarBarang)
              ? excessFallbackMethod
              : (isRegCust ? RefundMethods.saldoKredit : RefundMethods.tunai);
          await _settleOutflowTxn(
            txn,
            retId: retId,
            ret: ret,
            method: chosenExcess,
            amount: remainingToOffset,
            shiftId: shiftId,
            resolvedCustomerId: resolvedCustomerId,
            resolvedCustomerName: resolvedCustomerName,
            labelPrefix: 'Kelebihan Retur Kasbon',
          );
        }
        break;

      default:
        throw StateError('Metode pengembalian dana "$method" tidak dikenali.');
    }
  }

  Future<int> insertReturnOrder(ReturnOrderModel ret, {int? shiftId}) async {
    final db = await database;
    return await db.transaction((txn) async {
      // 0. Idempotency protection: never double-execute retried requests
      final idem = ret.idempotencyKey?.trim();
      if (idem != null && idem.isNotEmpty) {
        final existingIdem = await txn.query(
          'return_orders',
          columns: ['id'],
          where: 'idempotency_key = ?',
          whereArgs: [idem],
          limit: 1,
        );
        if (existingIdem.isNotEmpty) {
          return existingIdem.first['id'] as int;
        }
      }

      if (ret.items.isEmpty) {
        throw StateError('Minimal 1 barang harus dipilih untuk diproses retur.');
      }

      final trxRows = await txn.query('transactions', where: 'id = ?', whereArgs: [ret.transactionId], limit: 1);
      if (trxRows.isEmpty) {
        throw StateError('Transaksi asal tidak ditemukan.');
      }
      final origTrx = TransactionModel.fromMap(trxRows.first);
      if (origTrx.status == 'voided' || origTrx.status == 'void') {
        throw StateError('Transaksi yang sudah dibatalkan (VOID) tidak dapat diretur.');
      }

      if (!RefundMethods.all.contains(ret.refundMethod)) {
        throw StateError('Metode penyelesaian retur "${ret.refundMethod}" tidak valid.');
      }
      if (ret.refundMethod == RefundMethods.tukarBarang && ret.exchangeItems.isEmpty) {
        throw StateError('Metode Tukar Barang wajib memilih minimal 1 produk pengganti agar stok keluar tercatat.');
      }

      final int? resolvedCustomerId = ret.customerId ?? origTrx.customerId;
      final String resolvedCustomerName =
          ret.customerName.trim().isNotEmpty && ret.customerName.trim().toLowerCase() != 'pelanggan umum'
              ? ret.customerName.trim()
              : (origTrx.customerName.trim().isNotEmpty ? origTrx.customerName.trim() : 'Pelanggan Umum');

      // Validate return items against original purchased quantities & prior non-voided returns
      final origItems = await txn.query(
        'transaction_items',
        where: 'transaction_id = ?',
        whereArgs: [ret.transactionId],
      );
      final purchasedMap = <String, double>{};
      final origMetaByKey = <String, Map<String, dynamic>>{};
      for (final oi in origItems) {
        final key = '${oi['product_id']}_${oi['unit_name']}';
        purchasedMap[key] = (purchasedMap[key] ?? 0.0) + ((oi['qty'] as num).toDouble());
        origMetaByKey.putIfAbsent(key, () => oi);
      }

      final priorRetRows = await txn.rawQuery('''
        SELECT ri.product_id, ri.unit_name, SUM(ri.return_qty) as total_ret
        FROM return_items ri
        JOIN return_orders ro ON ri.return_order_id = ro.id
        WHERE ro.transaction_id = ? AND COALESCE(ro.status, 'completed') != 'voided'
        GROUP BY ri.product_id, ri.unit_name
      ''', [ret.transactionId]);
      final retMap = <String, double>{
        for (final r in priorRetRows)
          '${r['product_id']}_${r['unit_name']}': (r['total_ret'] as num?)?.toDouble() ?? 0.0,
      };

      final normalizedItems = <ReturnItemModel>[];
      double computedReturnSubtotal = 0.0;
      for (final item in ret.items) {
        final key = '${item.productId}_${item.unitName}';
        final purchased = purchasedMap[key] ?? 0.0;
        if (purchased <= 0.0001) {
          throw StateError('Produk "${item.productName}" tidak terdaftar pada transaksi #${origTrx.invoiceNumber}.');
        }
        final alreadyRet = retMap[key] ?? 0.0;
        final remainingAllowed = purchased - alreadyRet;
        if (item.returnQty <= 0 || item.returnQty > remainingAllowed + 0.0001) {
          throw StateError(
            'Jumlah retur "${item.productName}" (${item.returnQty}) melebihi sisa yang dapat diretur (${remainingAllowed.toStringAsFixed(1)} ${item.unitName}).',
          );
        }

        final origItem = origMetaByKey[key]!;
        final prodRows = await txn.query(
          'products',
          columns: ['code', 'cost_price', 'track_stock', 'is_service'],
          where: 'id = ?',
          whereArgs: [item.productId],
          limit: 1,
        );
        final prodMeta = prodRows.isNotEmpty ? prodRows.first : <String, dynamic>{};
        final tracksStock = prodRows.isEmpty ||
            ((prodMeta['track_stock'] ?? 1) == 1 && (prodMeta['is_service'] ?? 0) != 1);

        final effectiveTreatment = !tracksStock
            ? StockTreatments.noStockChange
            : (StockTreatments.all.contains(item.stockTreatment)
                ? item.stockTreatment
                : StockTreatments.defaultForCondition(item.condition, tracksStock: tracksStock));

        final baseCost = item.costPrice > 0
            ? item.costPrice
            : ((origItem['cost_price'] as num?)?.toDouble() ??
                (prodMeta['cost_price'] as num?)?.toDouble() ??
                0.0);
        final sku = item.sku.isNotEmpty
            ? item.sku
            : (origItem['product_code'] ?? prodMeta['code'] ?? '').toString();
        final lineSubtotal = item.subtotal > 0 ? item.subtotal : (item.returnQty * item.refundPrice);

        normalizedItems.add(
          ReturnItemModel(
            productId: item.productId,
            sku: sku,
            productName: item.productName,
            unitName: item.unitName,
            conversionFactor: item.conversionFactor,
            purchasedQty: item.purchasedQty > 0 ? item.purchasedQty : purchased,
            previouslyReturnedQty: alreadyRet,
            returnQty: item.returnQty,
            refundPrice: item.refundPrice,
            costPrice: baseCost,
            subtotal: lineSubtotal,
            condition: item.condition,
            stockTreatment: effectiveTreatment,
          ),
        );
        retMap[key] = alreadyRet + item.returnQty;
        computedReturnSubtotal += lineSubtotal;
      }

      final double effectiveReturnTotal = ret.totalRefund > 0 ? ret.totalRefund : computedReturnSubtotal;

      // Normalize & pre-validate exchange items if tukar_barang
      final normalizedExchangeItems = <ReturnExchangeItemModel>[];
      double computedExchangeTotal = 0.0;
      if (ret.refundMethod == RefundMethods.tukarBarang) {
        for (final ex in ret.exchangeItems) {
          if (ex.qty <= 0) {
            throw StateError('Qty barang pengganti "${ex.productName}" harus lebih dari 0.');
          }
          final pRows = await txn.query('products', where: 'id = ?', whereArgs: [ex.productId], limit: 1);
          if (pRows.isEmpty) {
            throw StateError('Produk pengganti "${ex.productName}" tidak ditemukan.');
          }
          final pm = pRows.first;
          final exSku = ex.sku.isNotEmpty ? ex.sku : (pm['code'] ?? '').toString();
          final exCost = ex.costPrice > 0 ? ex.costPrice : ((pm['cost_price'] as num?)?.toDouble() ?? 0.0);
          final exSubtotal = ex.subtotal > 0 ? ex.subtotal : (ex.qty * ex.unitPrice);
          normalizedExchangeItems.add(
            ReturnExchangeItemModel(
              productId: ex.productId,
              sku: exSku,
              productName: ex.productName.isNotEmpty ? ex.productName : (pm['name'] ?? '').toString(),
              unitName: ex.unitName,
              conversionFactor: ex.conversionFactor,
              qty: ex.qty,
              unitPrice: ex.unitPrice,
              costPrice: exCost,
              subtotal: exSubtotal,
            ),
          );
          computedExchangeTotal += exSubtotal;
        }
      }

      final double effectiveExchangeTotal =
          ret.refundMethod == RefundMethods.tukarBarang ? computedExchangeTotal : 0.0;
      final double differenceAmount =
          ret.refundMethod == RefundMethods.tukarBarang ? (effectiveExchangeTotal - effectiveReturnTotal) : 0.0;

      // Insert parent return_orders row
      final insertMap = ReturnOrderModel(
        returnNumber: ret.returnNumber,
        transactionId: ret.transactionId,
        invoiceNumber: ret.invoiceNumber,
        date: ret.date,
        cashierId: ret.cashierId,
        cashierName: ret.cashierName,
        customerId: resolvedCustomerId,
        customerName: resolvedCustomerName,
        totalRefund: effectiveReturnTotal,
        refundMethod: ret.refundMethod,
        reason: ret.reason,
        note: ret.note,
        status: 'completed',
        exchangeTotal: effectiveExchangeTotal,
        differenceAmount: differenceAmount,
        differencePaymentMethod: ret.differencePaymentMethod,
        idempotencyKey: idem,
      ).toMap();
      final retId = await txn.insert('return_orders', insertMap);

      // Process returned item records & inventory movements FIRST (so same-SKU restock precedes exchange_out cleanly)
      for (final item in normalizedItems) {
        await txn.insert('return_items', {
          ...item.toMap(),
          'return_order_id': retId,
        });

        late final String movementType;
        late final String bucket;
        late final double qtyDelta;
        switch (item.stockTreatment) {
          case StockTreatments.restockSellable:
            movementType = MovementTypes.returnIn;
            bucket = 'sellable';
            qtyDelta = item.baseStockQty;
            break;
          case StockTreatments.quarantine:
            movementType = MovementTypes.quarantineIn;
            bucket = 'quarantine';
            qtyDelta = item.baseStockQty;
            break;
          case StockTreatments.damaged:
            movementType = MovementTypes.damagedIn;
            bucket = 'damaged';
            qtyDelta = item.baseStockQty;
            break;
          case StockTreatments.noStockChange:
          default:
            movementType = MovementTypes.noStockChange;
            bucket = 'none';
            qtyDelta = 0.0;
            break;
        }

        await _recordStockMovement(
          txn,
          productId: item.productId,
          movementType: movementType,
          bucket: bucket,
          qtyDelta: qtyDelta,
          referenceType: 'return_order',
          referenceId: retId,
          referenceNumber: ret.returnNumber,
          userId: ret.cashierId,
          userName: ret.cashierName,
          note:
              'Retur #${ret.returnNumber} (Nota #${ret.invoiceNumber}) [${ReturnConditions.label(item.condition)} -> ${StockTreatments.label(item.stockTreatment)}]',
          enforceNonNegative: false,
          recordWhenUntracked: true,
        );
      }

      // Process exchange items OUT + record exchange_out ledger
      if (ret.refundMethod == RefundMethods.tukarBarang) {
        for (final ex in normalizedExchangeItems) {
          await txn.insert('return_exchange_items', {
            ...ex.toMap(),
            'return_order_id': retId,
          });
          await _recordStockMovement(
            txn,
            productId: ex.productId,
            movementType: MovementTypes.exchangeOut,
            bucket: 'sellable',
            qtyDelta: -ex.baseStockQty,
            referenceType: 'return_order',
            referenceId: retId,
            referenceNumber: ret.returnNumber,
            userId: ret.cashierId,
            userName: ret.cashierName,
            note: 'Tukar Barang Keluar Retur #${ret.returnNumber} (${ex.qty} ${ex.unitName})',
            enforceNonNegative: true,
            recordWhenUntracked: true,
          );
        }
      }

      // Update parent transaction status ('returned' vs 'partial_return')
      bool allReturned = origItems.isNotEmpty;
      for (final entry in purchasedMap.entries) {
        final returned = retMap[entry.key] ?? 0.0;
        if (returned + 0.0001 < entry.value) {
          allReturned = false;
          break;
        }
      }
      await txn.update(
        'transactions',
        {'status': allReturned ? 'returned' : 'partial_return'},
        where: 'id = ?',
        whereArgs: [ret.transactionId],
      );

      // Financial settlement
      final nowIso = DateTime.now().toIso8601String();
      if (ret.refundMethod == RefundMethods.tukarBarang) {
        if (differenceAmount.abs() <= 0.01) {
          await txn.insert('return_settlements', {
            'return_order_id': retId,
            'settlement_type': 'tukar_sama',
            'direction': 'none',
            'method': RefundMethods.tukarBarang,
            'amount': 0.0,
            'customer_id': resolvedCustomerId,
            'note': 'Tukar barang nilai setara (Rp ${effectiveReturnTotal.toInt()})',
            'created_at': nowIso,
          });
        } else if (differenceAmount > 0.01) {
          // Pelanggan bayar selisih tambahan (upgrade)
          final payDiffMethod =
              ret.differencePaymentMethod.trim().isNotEmpty ? ret.differencePaymentMethod.trim() : RefundMethods.tunai;
          if (payDiffMethod == RefundMethods.tunai) {
            await _ensureOpenShiftTxn(txn, shiftId);
            final cfId = await _insertCashFlowInTxn(
              txn,
              shiftId: shiftId,
              type: 'in',
              category: 'Selisih Tukar Barang',
              amount: differenceAmount,
              paymentMethod: 'tunai',
              accountName: 'Laci Kasir',
              sourceType: 'retur',
              sourceId: ret.returnNumber,
              note: 'Tambahan bayar tukar barang #${ret.returnNumber} (Nota #${ret.invoiceNumber})',
              cashierName: ret.cashierName,
            );
            await txn.rawUpdate(
              'UPDATE shifts SET total_cash_in = total_cash_in + ? WHERE id = ?',
              [differenceAmount, shiftId],
            );
            await txn.insert('return_settlements', {
              'return_order_id': retId,
              'settlement_type': 'tukar_bayar_selisih',
              'direction': 'in_from_customer',
              'method': RefundMethods.tunai,
              'amount': differenceAmount,
              'account_name': 'Laci Kasir',
              'shift_id': shiftId,
              'customer_id': resolvedCustomerId,
              'cash_flow_id': cfId,
              'note': 'Pelanggan bayar selisih upgrade secara tunai',
              'created_at': nowIso,
            });
          } else if (payDiffMethod == RefundMethods.transfer ||
              payDiffMethod == 'qris' ||
              payDiffMethod == RefundMethods.qrisManual) {
            final pm = payDiffMethod == RefundMethods.transfer ? 'transfer' : 'qris';
            final acc = ret.transferAccount.trim().isNotEmpty
                ? ret.transferAccount.trim()
                : (pm == 'transfer' ? 'Rekening Bank' : 'QRIS');
            final cfId = await _insertCashFlowInTxn(
              txn,
              shiftId: null,
              type: 'in',
              category: 'Selisih Tukar Barang ($pm)',
              amount: differenceAmount,
              paymentMethod: pm,
              accountName: acc,
              sourceType: 'retur',
              sourceId: ret.returnNumber,
              note: 'Tambahan bayar tukar barang #${ret.returnNumber} via $acc',
              cashierName: ret.cashierName,
            );
            await txn.insert('return_settlements', {
              'return_order_id': retId,
              'settlement_type': 'tukar_bayar_selisih',
              'direction': 'in_from_customer',
              'method': payDiffMethod,
              'amount': differenceAmount,
              'account_name': acc,
              'reference_number': ret.transferReference.trim(),
              'customer_id': resolvedCustomerId,
              'cash_flow_id': cfId,
              'note': 'Pelanggan bayar selisih upgrade via $acc',
              'created_at': nowIso,
            });
          } else if (payDiffMethod == RefundMethods.saldoKredit) {
            final isReg = await _isRegisteredCustomerTxn(txn, resolvedCustomerId);
            if (!isReg || resolvedCustomerId == null) {
              throw StateError('Pelanggan harus terdaftar untuk membayar selisih tukar barang dengan Saldo Kredit.');
            }
            await _appendCustomerCreditLedgerTxn(
              txn,
              customerId: resolvedCustomerId,
              customerName: resolvedCustomerName,
              entryType: CustomerCreditTypes.creditRedeemed,
              amount: differenceAmount,
              referenceType: 'return_order',
              referenceId: retId,
              referenceNumber: ret.returnNumber,
              userId: ret.cashierId,
              userName: ret.cashierName,
              note: 'Potong saldo kredit selisih tukar barang #${ret.returnNumber}',
            );
            await txn.insert('return_settlements', {
              'return_order_id': retId,
              'settlement_type': 'tukar_bayar_selisih',
              'direction': 'credit_used',
              'method': RefundMethods.saldoKredit,
              'amount': differenceAmount,
              'account_name': 'Saldo Kredit Pelanggan',
              'customer_id': resolvedCustomerId,
              'note': 'Pembayaran selisih memakai saldo kredit pelanggan',
              'created_at': nowIso,
            });
          } else {
            throw StateError('Metode bayar selisih tukar barang "$payDiffMethod" tidak didukung.');
          }
        } else {
          // Nilai barang pengganti lebih murah -> kembalikan selisih ke pelanggan
          final refundDiff = -differenceAmount;
          final diffOutMethod =
              ret.differencePaymentMethod.trim().isNotEmpty ? ret.differencePaymentMethod.trim() : RefundMethods.tunai;
          await _settleOutflowTxn(
            txn,
            retId: retId,
            ret: ret,
            method: diffOutMethod,
            amount: refundDiff,
            shiftId: shiftId,
            resolvedCustomerId: resolvedCustomerId,
            resolvedCustomerName: resolvedCustomerName,
            labelPrefix: 'Selisih Tukar Lebih Murah',
          );
        }
      } else {
        await _settleOutflowTxn(
          txn,
          retId: retId,
          ret: ret,
          method: ret.refundMethod,
          amount: effectiveReturnTotal,
          shiftId: shiftId,
          resolvedCustomerId: resolvedCustomerId,
          resolvedCustomerName: resolvedCustomerName,
          excessFallbackMethod: ret.differencePaymentMethod,
        );
      }

      return retId;
    });
  }

  /// Atomically reverses a completed return order: restores/pulls back inventory buckets,
  /// reverses exchange items, customer credit, debt offsets, and cash flows, and updates transaction status.
  Future<void> voidReturnOrder({
    required int returnOrderId,
    required int userId,
    required String userName,
    required String reason,
    int? shiftId,
  }) async {
    if (reason.trim().isEmpty) {
      throw StateError('Alasan pembatalan retur wajib diisi.');
    }
    final db = await database;
    await db.transaction((txn) async {
      final roRows = await txn.query('return_orders', where: 'id = ?', whereArgs: [returnOrderId], limit: 1);
      if (roRows.isEmpty) {
        throw StateError('Data retur tidak ditemukan.');
      }
      final ro = await _hydrateReturnOrder(txn, roRows.first);
      if (ro.isVoided) {
        throw StateError('Retur #${ro.returnNumber} sudah dibatalkan sebelumnya.');
      }

      // 1. Reverse returned items stock effect
      for (final item in ro.items) {
        late final String bucket;
        late final double reverseDelta;
        switch (item.stockTreatment) {
          case StockTreatments.restockSellable:
            bucket = 'sellable';
            reverseDelta = -item.baseStockQty;
            break;
          case StockTreatments.quarantine:
            bucket = 'quarantine';
            reverseDelta = -item.baseStockQty;
            break;
          case StockTreatments.damaged:
            bucket = 'damaged';
            reverseDelta = -item.baseStockQty;
            break;
          case StockTreatments.noStockChange:
          default:
            bucket = 'none';
            reverseDelta = 0.0;
            break;
        }
        await _recordStockMovement(
          txn,
          productId: item.productId,
          movementType: MovementTypes.returnVoidReverse,
          bucket: bucket,
          qtyDelta: reverseDelta,
          referenceType: 'return_void',
          referenceId: ro.id,
          referenceNumber: ro.returnNumber,
          userId: userId,
          userName: userName,
          note: 'Pembatalan Retur #${ro.returnNumber} ($reason)',
          enforceNonNegative: true,
          recordWhenUntracked: true,
        );
      }

      // 2. Restore exchange items back to sellable stock
      for (final ex in ro.exchangeItems) {
        await _recordStockMovement(
          txn,
          productId: ex.productId,
          movementType: MovementTypes.returnVoidReverse,
          bucket: 'sellable',
          qtyDelta: ex.baseStockQty,
          referenceType: 'return_void',
          referenceId: ro.id,
          referenceNumber: ro.returnNumber,
          userId: userId,
          userName: userName,
          note: 'Pengembalian stok pengganti akibat Void Retur #${ro.returnNumber}',
          enforceNonNegative: false,
          recordWhenUntracked: true,
        );
      }

      // 3. Reverse financial settlements
      final nowIso = DateTime.now().toIso8601String();
      for (final st in ro.settlements) {
        if (st.amount <= 0.001) continue;
        if (st.direction == 'credit_issued') {
          final cid = st.customerId ?? ro.customerId;
          if (cid != null) {
            await _appendCustomerCreditLedgerTxn(
              txn,
              customerId: cid,
              customerName: ro.customerName,
              entryType: CustomerCreditTypes.creditReversed,
              amount: st.amount,
              referenceType: 'return_void',
              referenceId: ro.id,
              referenceNumber: ro.returnNumber,
              userId: userId,
              userName: userName,
              note: 'Pembatalan kredit hasil Void Retur #${ro.returnNumber}',
            );
          }
        } else if (st.direction == 'credit_used') {
          final cid = st.customerId ?? ro.customerId;
          if (cid != null) {
            await _appendCustomerCreditLedgerTxn(
              txn,
              customerId: cid,
              customerName: ro.customerName,
              entryType: CustomerCreditTypes.creditIssued,
              amount: st.amount,
              referenceType: 'return_void',
              referenceId: ro.id,
              referenceNumber: ro.returnNumber,
              userId: userId,
              userName: userName,
              note: 'Pemulihan saldo kredit akibat Void Retur #${ro.returnNumber}',
            );
          }
        } else if (st.direction == 'debt_offset') {
          final debtInv = st.referenceNumber.isNotEmpty ? st.referenceNumber : ro.invoiceNumber;
          final dRows = await txn.query('customer_debts', where: 'invoice_number = ?', whereArgs: [debtInv], limit: 1);
          if (dRows.isNotEmpty) {
            final d = CustomerDebtModel.fromMap(dRows.first);
            final newPaid = (d.paidDebt - st.amount).clamp(0.0, d.totalDebt);
            await txn.update(
              'customer_debts',
              {
                'paid_debt': newPaid,
                'note': '${d.note} [Void Retur #${ro.returnNumber}]'.trim(),
              },
              where: 'id = ?',
              whereArgs: [d.id],
            );
            await txn.insert('customer_debt_payments', {
              'debt_id': d.id,
              'customer_id': d.customerId,
              'amount': -st.amount,
              'payment_method': 'retur_void',
              'shift_id': shiftId ?? st.shiftId,
              'cashier_name': userName,
              'date': nowIso,
              'note': 'Pembatalan potong piutang dari Void Retur #${ro.returnNumber}',
            });
          }
        } else if (st.direction == 'out_to_customer') {
          final targetShiftId = shiftId ?? st.shiftId;
          if (st.method == RefundMethods.tunai) {
            await _ensureOpenShiftTxn(txn, targetShiftId);
            await _insertCashFlowInTxn(
              txn,
              shiftId: targetShiftId,
              type: 'in',
              category: 'Pembalikan Refund Retur Void',
              amount: st.amount,
              paymentMethod: 'tunai',
              accountName: 'Laci Kasir',
              sourceType: 'retur_void',
              sourceId: ro.returnNumber,
              note: 'Void Retur #${ro.returnNumber} ($reason)',
              cashierName: userName,
            );
            if (targetShiftId != null) {
              final sRows = await txn.query('shifts', where: 'id = ?', whereArgs: [targetShiftId], limit: 1);
              if (sRows.isNotEmpty) {
                final curRetCash = (sRows.first['total_return_cash'] as num?)?.toDouble() ?? 0.0;
                final decRet = st.amount <= curRetCash ? st.amount : curRetCash;
                final remIn = st.amount - decRet;
                await txn.rawUpdate(
                  'UPDATE shifts SET total_return_cash = total_return_cash - ?, total_cash_in = total_cash_in + ? WHERE id = ?',
                  [decRet, remIn, targetShiftId],
                );
              }
            }
          } else {
            final pm = st.method == RefundMethods.transfer ? 'transfer' : 'qris';
            await _insertCashFlowInTxn(
              txn,
              shiftId: null,
              type: 'in',
              category: 'Pembalikan Refund Non-Tunai Void',
              amount: st.amount,
              paymentMethod: pm,
              accountName: st.accountName.isNotEmpty ? st.accountName : (pm == 'transfer' ? 'Rekening Bank' : 'QRIS'),
              sourceType: 'retur_void',
              sourceId: ro.returnNumber,
              note: 'Void Retur #${ro.returnNumber} ($reason)',
              cashierName: userName,
            );
          }
        } else if (st.direction == 'in_from_customer') {
          final targetShiftId = shiftId ?? st.shiftId;
          if (st.method == RefundMethods.tunai) {
            await _ensureSufficientShiftCash(txn, targetShiftId, st.amount);
            await _insertCashFlowInTxn(
              txn,
              shiftId: targetShiftId,
              type: 'out',
              category: 'Pembalikan Selisih Tukar Void',
              amount: st.amount,
              paymentMethod: 'tunai',
              accountName: 'Laci Kasir',
              sourceType: 'retur_void',
              sourceId: ro.returnNumber,
              note: 'Kembalikan selisih bayar akibat Void Retur #${ro.returnNumber} ($reason)',
              cashierName: userName,
            );
            if (targetShiftId != null) {
              await txn.rawUpdate(
                'UPDATE shifts SET total_cash_out = total_cash_out + ? WHERE id = ?',
                [st.amount, targetShiftId],
              );
            }
          } else {
            final pm = st.method == RefundMethods.transfer ? 'transfer' : 'qris';
            await _insertCashFlowInTxn(
              txn,
              shiftId: null,
              type: 'out',
              category: 'Pembalikan Selisih Tukar Non-Tunai Void',
              amount: st.amount,
              paymentMethod: pm,
              accountName: st.accountName.isNotEmpty ? st.accountName : (pm == 'transfer' ? 'Rekening Bank' : 'QRIS'),
              sourceType: 'retur_void',
              sourceId: ro.returnNumber,
              note: 'Kembalikan selisih transfer/QRIS akibat Void Retur #${ro.returnNumber}',
              cashierName: userName,
            );
          }
        }
      }

      // 4. Mark return_order voided (immutable history kept intact)
      await txn.update(
        'return_orders',
        {
          'status': 'voided',
          'voided_at': nowIso,
          'voided_by': userId,
          'voided_by_name': userName,
          'void_reason': reason.trim(),
        },
        where: 'id = ?',
        whereArgs: [returnOrderId],
      );

      // 5. Recalculate original transaction status among remaining active returns
      final origItems = await txn.query('transaction_items', where: 'transaction_id = ?', whereArgs: [ro.transactionId]);
      final purchasedMap = <String, double>{};
      for (final oi in origItems) {
        final key = '${oi['product_id']}_${oi['unit_name']}';
        purchasedMap[key] = (purchasedMap[key] ?? 0.0) + ((oi['qty'] as num).toDouble());
      }
      final remRetRows = await txn.rawQuery('''
        SELECT ri.product_id, ri.unit_name, SUM(ri.return_qty) as total_ret
        FROM return_items ri
        JOIN return_orders r ON ri.return_order_id = r.id
        WHERE r.transaction_id = ? AND COALESCE(r.status, 'completed') != 'voided'
        GROUP BY ri.product_id, ri.unit_name
      ''', [ro.transactionId]);
      final remMap = <String, double>{
        for (final r in remRetRows)
          '${r['product_id']}_${r['unit_name']}': (r['total_ret'] as num?)?.toDouble() ?? 0.0,
      };
      final double totalRemRet = remMap.values.fold(0.0, (s, e) => s + e);
      String nextTxStatus = 'completed';
      if (totalRemRet > 0.0001) {
        bool allRet = origItems.isNotEmpty;
        for (final e in purchasedMap.entries) {
          if ((remMap[e.key] ?? 0.0) + 0.0001 < e.value) {
            allRet = false;
            break;
          }
        }
        nextTxStatus = allRet ? 'returned' : 'partial_return';
      }
      await txn.update(
        'transactions',
        {'status': nextTxStatus},
        where: 'id = ?',
        whereArgs: [ro.transactionId],
      );

      // 6. Audit log
      await txn.insert('audit_logs', {
        'timestamp': nowIso,
        'user_id': userId,
        'user_name': userName,
        'user_role': '',
        'action_type': 'void_retur',
        'module': 'retur',
        'object_id': ro.returnNumber,
        'before_value': 'status=completed, refund=${ro.totalRefund}, exchange=${ro.exchangeTotal}',
        'after_value': 'status=voided, tx_status=$nextTxStatus',
        'details': 'Pembatalan Retur #${ro.returnNumber} (Nota #${ro.invoiceNumber}): ${reason.trim()}',
      });
    });
  }

  /// Releases quarantined stock to either 'sellable' (products.stock) or 'damaged' (products.damaged_stock).
  Future<void> releaseQuarantineStock({
    required int productId,
    required double qty,
    required String destination, // 'sellable' | 'damaged'
    required int userId,
    required String userName,
    String note = '',
  }) async {
    if (qty <= 0) {
      throw StateError('Jumlah karantina yang dilepas harus lebih dari 0.');
    }
    if (destination != 'sellable' && destination != 'damaged') {
      throw StateError('Tujuan pelepasan karantina harus "sellable" atau "damaged".');
    }
    final db = await database;
    await db.transaction((txn) async {
      final refNum = 'QRL-${DateTime.now().millisecondsSinceEpoch}';
      await _recordStockMovement(
        txn,
        productId: productId,
        movementType: MovementTypes.quarantineRelease,
        bucket: 'quarantine',
        qtyDelta: -qty,
        referenceType: 'quarantine_release',
        referenceNumber: refNum,
        userId: userId,
        userName: userName,
        note: 'Keluar karantina menuju ${destination == 'sellable' ? 'Stok Jual' : 'Stok Rusak'}${note.isNotEmpty ? ": $note" : ""}',
        enforceNonNegative: true,
      );
      await _recordStockMovement(
        txn,
        productId: productId,
        movementType: destination == 'sellable' ? MovementTypes.quarantineRelease : MovementTypes.damagedIn,
        bucket: destination,
        qtyDelta: qty,
        referenceType: 'quarantine_release',
        referenceNumber: refNum,
        userId: userId,
        userName: userName,
        note: 'Hasil inspeksi karantina (${destination == 'sellable' ? 'Layak Jual' : 'Rusak/Afkir'})${note.isNotEmpty ? ": $note" : ""}',
        enforceNonNegative: false,
      );
    });
  }

  Future<List<InventoryMovementModel>> getInventoryMovements({
    int? productId,
    String? movementType,
    DateTime? start,
    DateTime? end,
    int limit = 200,
  }) async {
    final db = await database;
    final whereParts = <String>[];
    final args = <dynamic>[];
    if (productId != null) {
      whereParts.add('product_id = ?');
      args.add(productId);
    }
    if (movementType != null && movementType.isNotEmpty) {
      whereParts.add('movement_type = ?');
      args.add(movementType);
    }
    if (start != null && end != null) {
      whereParts.add('created_at >= ? AND created_at <= ?');
      args.addAll([
        DateTime(start.year, start.month, start.day).toIso8601String(),
        DateTime(end.year, end.month, end.day, 23, 59, 59, 999).toIso8601String(),
      ]);
    }
    final res = await db.query(
      'inventory_movements',
      where: whereParts.isEmpty ? null : whereParts.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'id DESC',
      limit: limit,
    );
    return res.map((e) => InventoryMovementModel.fromMap(e)).toList();
  }

  Future<List<ProductModel>> getQuarantineAndDamagedProducts() async {
    final db = await database;
    final res = await db.query(
      'products',
      where: 'quarantine_stock > 0 OR damaged_stock > 0',
      orderBy: 'quarantine_stock DESC, damaged_stock DESC, name ASC',
    );
    return res.map((e) => ProductModel.fromMap(e)).toList();
  }

  Future<double> getCustomerCreditBalance(int customerId) async {
    final db = await database;
    return await _getCustomerCreditBalanceTxn(db, customerId);
  }

  Future<List<CustomerCreditEntryModel>> getCustomerCreditLedger(int customerId, {int limit = 100}) async {
    final db = await database;
    final res = await db.query(
      'customer_credit_ledger',
      where: 'customer_id = ?',
      whereArgs: [customerId],
      orderBy: 'id DESC',
      limit: limit,
    );
    return res.map((e) => CustomerCreditEntryModel.fromMap(e)).toList();
  }

  Future<Map<int, double>> getAllCustomerCreditBalances() async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT customer_id,
        COALESCE(SUM(
          CASE
            WHEN entry_type IN ('credit_issued', 'manual_adjustment') THEN amount
            WHEN entry_type IN ('credit_redeemed', 'credit_reversed') THEN -amount
            ELSE 0
          END
        ), 0.0) as bal
      FROM customer_credit_ledger
      GROUP BY customer_id
    ''');
    final map = <int, double>{};
    for (final r in rows) {
      final cid = r['customer_id'] as int?;
      final bal = (r['bal'] as num?)?.toDouble() ?? 0.0;
      if (cid != null && bal > 0.001) {
        map[cid] = bal;
      }
    }
    return map;
  }

  /// Non-destructively inspects historical pre-v4 returns that may have anomalous stock/exchange state
  /// (e.g., legacy 'tukar_barang' with no exchange items) so owner can audit & adjust via Stock Opname.
  Future<List<Map<String, dynamic>>> getLegacyReturnReconciliationReport() async {
    final db = await database;
    final rows = await db.query(
      'return_orders',
      where: "COALESCE(status, 'completed') != 'voided'",
      orderBy: 'date DESC',
    );
    final findings = <Map<String, dynamic>>[];
    for (final raw in rows) {
      final ro = await _hydrateReturnOrder(db, raw);
      final movCountRows = await db.rawQuery(
        "SELECT COUNT(*) as c FROM inventory_movements WHERE reference_type = 'return_order' AND reference_id = ?",
        [ro.id],
      );
      final hasMovements = ((movCountRows.first['c'] as num?)?.toInt() ?? 0) > 0;

      if (ro.refundMethod == RefundMethods.tukarBarang && ro.exchangeItems.isEmpty) {
        findings.add({
          'returnId': ro.id,
          'returnNumber': ro.returnNumber,
          'invoiceNumber': ro.invoiceNumber,
          'date': ro.date,
          'severity': 'HIGH',
          'issueType': 'legacy_tukar_tanpa_keluar',
          'message':
              'Retur Tukar Barang lama (#${ro.returnNumber}) belum memiliki catatan item keluar pengganti (${ro.items.map((i) => "${i.productName} x${i.returnQty}").join(", ")}). Periksa stok fisik & sesuaikan via Stok Opname bila berlebih.',
        });
      } else if (!hasMovements && ro.items.any((i) => i.condition != ReturnConditions.baik)) {
        findings.add({
          'returnId': ro.id,
          'returnNumber': ro.returnNumber,
          'invoiceNumber': ro.invoiceNumber,
          'date': ro.date,
          'severity': 'MEDIUM',
          'issueType': 'legacy_rusak_tanpa_ledger',
          'message':
              'Retur barang rusak/cacat versi lama (#${ro.returnNumber}) belum memiliki catatan mutasi bucket rusak pada ledger v4.',
        });
      }
    }
    return findings;
  }

  // ================= SHIFTS & CASH FLOW =================
  Future<List<ShiftModel>> getOpenShifts({
    int? cashRegisterId,
    int? cashierId,
  }) async {
    final db = await database;
    final whereParts = <String>["status = 'open'"];
    final args = <dynamic>[];
    if (cashRegisterId != null) {
      whereParts.add('cash_register_id = ?');
      args.add(cashRegisterId);
    }
    if (cashierId != null) {
      whereParts.add('cashier_id = ?');
      args.add(cashierId);
    }
    final res = await db.query(
      'shifts',
      where: whereParts.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'id DESC',
    );
    return res.map((e) => ShiftModel.fromMap(e)).toList();
  }

  Future<ShiftModel?> getCurrentOpenShift({
    int? cashierId,
    String? terminalId,
    int? cashRegisterId,
  }) async {
    final db = await database;
    if (cashRegisterId != null) {
      final res = await db.query(
        'shifts',
        where: "status = 'open' AND cash_register_id = ?",
        whereArgs: [cashRegisterId],
        orderBy: 'id DESC',
        limit: 1,
      );
      return res.isNotEmpty ? ShiftModel.fromMap(res.first) : null;
    }
    if (cashierId == null && terminalId == null) {
      final res = await db.query(
        'shifts',
        where: "status = 'open'",
        orderBy: 'id DESC',
        limit: 1,
      );
      return res.isNotEmpty ? ShiftModel.fromMap(res.first) : null;
    }

    final drawerMode = await _getDrawerModeTxn(db);
    if (drawerMode == DrawerMode.individualDrawer && cashierId != null) {
      if (terminalId != null && terminalId.trim().isNotEmpty) {
        try {
          final authReg = await resolveAuthorizedCashRegisterTxn(
            db,
            cashierId: cashierId,
            terminalId: terminalId,
          );
          final byReg = await db.query(
            'shifts',
            where: "status = 'open' AND cash_register_id = ? AND cashier_id = ?",
            whereArgs: [authReg.id, cashierId],
            orderBy: 'id DESC',
            limit: 1,
          );
          if (byReg.isNotEmpty) return ShiftModel.fromMap(byReg.first);
        } catch (_) {}
      }
      final byCashier = await db.query(
        'shifts',
        where: "status = 'open' AND cashier_id = ?",
        whereArgs: [cashierId],
        orderBy: 'id DESC',
        limit: 1,
      );
      return byCashier.isNotEmpty ? ShiftModel.fromMap(byCashier.first) : null;
    }

    // SHARED_DRAWER or legacy fallback without parameters
    if (drawerMode == DrawerMode.sharedDrawer) {
      int targetRegId = 1;
      if (cashierId != null && terminalId != null && terminalId.trim().isNotEmpty) {
        try {
          final reg = await resolveAuthorizedCashRegisterTxn(
            db,
            cashierId: cashierId,
            terminalId: terminalId,
          );
          targetRegId = reg.id ?? 1;
        } catch (_) {}
      }
      final res = await db.query(
        'shifts',
        where: "status = 'open' AND cash_register_id = ?",
        whereArgs: [targetRegId],
        orderBy: 'id DESC',
        limit: 1,
      );
      if (res.isNotEmpty) return ShiftModel.fromMap(res.first);
    }

    final res = await db.query(
      'shifts',
      where: "status = 'open'",
      orderBy: 'id DESC',
      limit: 1,
    );
    if (res.isNotEmpty) return ShiftModel.fromMap(res.first);
    return null;
  }

  Future<List<ShiftModel>> getShiftHistory({int limit = 30}) async {
    final db = await database;
    final res = await db.query('shifts', orderBy: 'id DESC', limit: limit);
    return res.map((e) => ShiftModel.fromMap(e)).toList();
  }

  Future<int> openShift(ShiftModel shift) async {
    final db = await database;
    return await db.transaction((txn) async {
      if (shift.startingCash < 0) {
        throw StateError('Modal awal shift tidak boleh negatif.');
      }

      final drawerMode = await _getDrawerModeTxn(txn);
      final cleanTerm = shift.terminalId.trim().isNotEmpty ? shift.terminalId.trim() : 'ADMIN';
      final authReg = await resolveAuthorizedCashRegisterTxn(
        txn,
        cashierId: shift.cashierId,
        terminalId: cleanTerm,
        requestedRegisterId: shift.cashRegisterId,
      );

      // Rule: Only 1 open shift allowed per cash register
      final existingOnReg = await txn.query(
        'shifts',
        where: "status = 'open' AND cash_register_id = ?",
        whereArgs: [authReg.id],
        orderBy: 'id DESC',
        limit: 1,
      );
      if (existingOnReg.isNotEmpty) {
        final active = ShiftModel.fromMap(existingOnReg.first);
        throw StateError(
          'Masih ada shift terbuka pada laci "${authReg.name}" atas nama "${active.cashierName}" (mulai ${active.startTime.toString().substring(0, 16)}). Tutup shift aktif terlebih dahulu sebelum membuka shift baru.',
        );
      }

      // Rule: In INDIVIDUAL_DRAWER mode, same cashier cannot open 2 simultaneous open individual shifts
      if (drawerMode == DrawerMode.individualDrawer) {
        final existingForCashier = await txn.query(
          'shifts',
          where: "status = 'open' AND drawer_mode = ? AND cashier_id = ?",
          whereArgs: [DrawerMode.individualDrawer, shift.cashierId],
          limit: 1,
        );
        if (existingForCashier.isNotEmpty) {
          final active = ShiftModel.fromMap(existingForCashier.first);
          throw StateError(
            'Kasir "${shift.cashierName}" masih memiliki shift individu yang terbuka pada laci #${active.cashRegisterId}. Tutup shift aktif terlebih dahulu sebelum membuka shift baru.',
          );
        }
      }

      final shiftMap = shift.toMap();
      shiftMap['terminal_id'] = cleanTerm;
      shiftMap['cash_register_id'] = authReg.id;
      shiftMap['drawer_mode'] = drawerMode;
      return await txn.insert('shifts', shiftMap);
    });
  }

  Future<void> closeShift(int shiftId, double actualCash, double difference, String note) async {
    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.query('shifts', where: 'id = ?', whereArgs: [shiftId], limit: 1);
      if (rows.isEmpty) {
        throw StateError('Shift tidak ditemukan.');
      }
      final current = ShiftModel.fromMap(rows.first);
      if (!current.isOpen) {
        throw StateError('Shift ini sudah ditutup dan tidak dapat diubah kembali.');
      }
      final liveDiff = actualCash - current.expectedCash;
      if (liveDiff.abs() > 0.01 && note.trim().isEmpty) {
        throw StateError('Terdapat selisih kas sebesar Rp ${liveDiff.toInt()}. Keterangan wajib diisi.');
      }
      await txn.update(
        'shifts',
        {
          'end_time': DateTime.now().toIso8601String(),
          'actual_cash': actualCash,
          'difference': liveDiff,
          'status': 'closed',
          'note': note.trim(),
        },
        where: "id = ? AND status = 'open'",
        whereArgs: [shiftId],
      );
    });
    onMultiDeviceEvent?.call('shift_changed', {'shift_id': shiftId, 'status': 'closed'});
  }

  Future<void> adminCorrectShift({
    required int shiftId,
    required double newActualCash,
    required String correctionNote,
    required UserModel admin,
  }) async {
    if (!admin.hasPermission(AppPermissions.manageStoreSettings) && !admin.isOwner) {
      throw StateError('Hanya Owner / Admin berwenang yang dapat melakukan koreksi shift.');
    }
    if (correctionNote.trim().isEmpty) {
      throw StateError('Alasan koreksi shift wajib diisi.');
    }
    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.query('shifts', where: 'id = ?', whereArgs: [shiftId], limit: 1);
      if (rows.isEmpty) throw StateError('Shift tidak ditemukan.');
      final s = ShiftModel.fromMap(rows.first);
      if (s.isOpen) throw StateError('Gunakan penutupan shift normal untuk shift yang masih aktif.');

      final newDiff = newActualCash - s.expectedCash;
      final beforeJson = 'actual=${s.actualCash ?? 0}, diff=${s.difference ?? 0}, note=${s.note}';
      final afterJson = 'actual=$newActualCash, diff=$newDiff, note=${correctionNote.trim()}';

      await txn.update(
        'shifts',
        {
          'actual_cash': newActualCash,
          'difference': newDiff,
          'note': '${s.note} [KOREKSI ${admin.name}: ${correctionNote.trim()}]'.trim(),
        },
        where: 'id = ?',
        whereArgs: [shiftId],
      );

      await txn.insert('audit_logs', {
        'timestamp': DateTime.now().toIso8601String(),
        'user_id': admin.id ?? 0,
        'user_name': admin.name,
        'user_role': admin.role,
        'action_type': 'koreksi_shift',
        'module': 'Kas & Shift',
        'object_id': 'SHIFT-$shiftId',
        'before_value': beforeJson,
        'after_value': afterJson,
        'details': 'Koreksi tutup shift #${s.id} (${s.cashierName}): ${correctionNote.trim()}',
      });
    });
  }

  Future<Map<String, dynamic>> getShiftStats(ShiftModel shift) async {
    final db = await database;
    final startIso = shift.startTime.toIso8601String();
    final endIso = (shift.endTime ?? DateTime.now()).toIso8601String();

    final List<Map<String, dynamic>> txRows;
    if (shift.id != null) {
      final allowLegacyNullBackfill =
          shift.drawerMode == DrawerMode.sharedDrawer && shift.cashRegisterId == 1;
      if (allowLegacyNullBackfill) {
        txRows = await db.query(
          'transactions',
          where:
              "status != 'voided' AND (shift_id = ? OR (shift_id IS NULL AND COALESCE(terminal_id, 'ADMIN') = 'ADMIN' AND COALESCE(cash_register_id, 1) = 1 AND date >= ? AND date <= ?))",
          whereArgs: [shift.id, startIso, endIso],
        );
      } else {
        // Strict shift isolation: INDIVIDUAL_DRAWER / secondary registers must NEVER absorb null-shift rows
        txRows = await db.query(
          'transactions',
          where: "status != 'voided' AND shift_id = ?",
          whereArgs: [shift.id],
        );
      }
    } else {
      txRows = await db.query(
        'transactions',
        where:
            "status != 'voided' AND COALESCE(cash_register_id, 1) = ? AND date >= ? AND date <= ?",
        whereArgs: [shift.cashRegisterId, startIso, endIso],
      );
    }

    double profit = 0.0;
    for (final map in txRows) {
      final tid = map['id'] as int;
      final items = await db.query('transaction_items', where: 'transaction_id = ?', whereArgs: [tid]);
      for (final itemMap in items) {
        final item = TransactionItemModel.fromMap(itemMap);
        if (!item.isService) {
          profit += (item.unitPrice - (item.costPrice * item.conversionFactor)) * item.qty - item.discount;
        } else {
          profit += item.subtotal;
        }
      }
    }

    return {
      'totalTransactions': txRows.length,
      'totalGrossProfit': profit,
    };
  }

  Future<int> insertCashFlow(CashFlowModel flow) async {
    final db = await database;
    return await db.transaction((txn) async {
      if (flow.isOut && flow.paymentMethod == 'tunai' && flow.accountName == 'Laci Kasir') {
        await _ensureSufficientShiftCash(txn, flow.shiftId, flow.amount);
      }
      final flowMap = flow.toMap();
      if (flow.shiftId != null) {
        final sRows = await txn.query(
          'shifts',
          columns: ['terminal_id', 'cash_register_id'],
          where: 'id = ?',
          whereArgs: [flow.shiftId],
          limit: 1,
        );
        if (sRows.isNotEmpty) {
          if (flow.terminalId == 'ADMIN') {
            flowMap['terminal_id'] = sRows.first['terminal_id'] ?? 'ADMIN';
          }
          if (flow.cashRegisterId == 1) {
            flowMap['cash_register_id'] = (sRows.first['cash_register_id'] as num?)?.toInt() ?? 1;
          }
        }
      }
      final id = await txn.insert('cash_flows', flowMap);
      if (flow.shiftId != null && flow.paymentMethod == 'tunai' && flow.accountName == 'Laci Kasir') {
        if (flow.isIn) {
          await txn.rawUpdate(
            'UPDATE shifts SET total_cash_in = total_cash_in + ? WHERE id = ?',
            [flow.amount, flow.shiftId],
          );
        } else if (flow.isOut) {
          await txn.rawUpdate(
            'UPDATE shifts SET total_cash_out = total_cash_out + ? WHERE id = ?',
            [flow.amount, flow.shiftId],
          );
        }
      }
      return id;
    });
  }

  Future<List<CashFlowModel>> getCashFlowsForShift(int shiftId) async {
    final db = await database;
    final res = await db.query(
      'cash_flows',
      where: 'shift_id = ?',
      whereArgs: [shiftId],
      orderBy: 'date DESC',
    );
    return res.map((e) => CashFlowModel.fromMap(e)).toList();
  }

  Future<List<CashFlowModel>> getRecentCashFlows({int limit = 50}) async {
    final db = await database;
    final res = await db.query('cash_flows', orderBy: 'date DESC', limit: limit);
    return res.map((e) => CashFlowModel.fromMap(e)).toList();
  }

  /// Builds a unified, accurate cash-flow report & ledger for a date range,
  /// distinguishing sales, shift starting cash, debt payments, purchases,
  /// operational expenses, returns, and internal transfers (never double-counted).
  Future<Map<String, dynamic>> getCashFlowReport(DateTime start, DateTime end) async {
    final db = await database;
    final startBoundary = DateTime(start.year, start.month, start.day);
    final endBoundary = DateTime(end.year, end.month, end.day, 23, 59, 59, 999);
    final startIso = startBoundary.toIso8601String();
    final endIso = endBoundary.toIso8601String();

    // Opening cash balance prior to startBoundary (from shifts starting cash + cash sales + cash_in - cash_out - cash_returns)
    final prevShiftStartRes = await db.rawQuery(
      'SELECT COALESCE(SUM(starting_cash), 0) as s FROM shifts WHERE start_time < ?',
      [startIso],
    );
    final prevSalesCashRes = await db.rawQuery(
      "SELECT COALESCE(SUM(MAX(0, grand_total - COALESCE(credit_used, 0))), 0) as s FROM transactions WHERE status != 'voided' AND payment_method = 'tunai' AND date < ?",
      [startIso],
    );
    final prevCashInRes = await db.rawQuery(
      "SELECT COALESCE(SUM(amount), 0) as s FROM cash_flows WHERE type = 'in' AND payment_method = 'tunai' AND date < ?",
      [startIso],
    );
    final prevCashOutRes = await db.rawQuery(
      "SELECT COALESCE(SUM(amount), 0) as s FROM cash_flows WHERE type = 'out' AND payment_method = 'tunai' AND date < ?",
      [startIso],
    );

    final openingBalance = ((prevShiftStartRes.first['s'] as num?)?.toDouble() ?? 0.0) +
        ((prevSalesCashRes.first['s'] as num?)?.toDouble() ?? 0.0) +
        ((prevCashInRes.first['s'] as num?)?.toDouble() ?? 0.0) -
        ((prevCashOutRes.first['s'] as num?)?.toDouble() ?? 0.0);

    final entries = <Map<String, dynamic>>[];

    // 1. Shift starting modal entries in range
    final shiftsInRange = await db.query(
      'shifts',
      where: 'start_time >= ? AND start_time <= ?',
      whereArgs: [startIso, endIso],
    );
    double totalShiftModal = 0.0;
    for (final row in shiftsInRange) {
      final s = ShiftModel.fromMap(row);
      totalShiftModal += s.startingCash;
      if (s.startingCash > 0) {
        entries.add({
          'date': s.startTime,
          'type': 'in',
          'category': 'Modal Awal Shift',
          'amount': s.startingCash,
          'paymentMethod': 'tunai',
          'accountName': 'Laci Kasir',
          'sourceType': 'shift_open',
          'sourceId': 'SHIFT-${s.id}',
          'cashierName': s.cashierName,
          'note': 'Buka shift kasir (${s.cashierName})',
          'isInternalTransfer': false,
        });
      }
    }

    // 2. Sales transactions in range (Tunai, QRIS, Transfer - excluding unpaid Kasbon)
    final txInRange = await db.query(
      'transactions',
      where: "status != 'voided' AND date >= ? AND date <= ?",
      whereArgs: [startIso, endIso],
    );
    double totalSalesCash = 0.0;
    double totalSalesNonCash = 0.0;
    for (final row in txInRange) {
      final t = TransactionModel.fromMap(row);
      final netCashOrBank = (t.grandTotal - t.creditUsed).clamp(0.0, t.grandTotal);
      if (t.paymentMethod == 'tunai' && netCashOrBank > 0) {
        totalSalesCash += netCashOrBank;
        entries.add({
          'date': t.date,
          'type': 'in',
          'category': 'Penjualan Tunai',
          'amount': netCashOrBank,
          'paymentMethod': 'tunai',
          'accountName': 'Laci Kasir',
          'sourceType': 'penjualan',
          'sourceId': t.invoiceNumber,
          'cashierName': t.cashierName,
          'note': t.creditUsed > 0
              ? 'Nota #${t.invoiceNumber} (${t.customerName}) - Potong Kredit Rp ${t.creditUsed.toInt()}'
              : 'Nota #${t.invoiceNumber} (${t.customerName})',
          'isInternalTransfer': false,
        });
      } else if ((t.paymentMethod == 'qris' || t.paymentMethod == 'transfer') && netCashOrBank > 0) {
        totalSalesNonCash += netCashOrBank;
        entries.add({
          'date': t.date,
          'type': 'in',
          'category': 'Penjualan ${t.paymentMethod.toUpperCase()}',
          'amount': netCashOrBank,
          'paymentMethod': t.paymentMethod,
          'accountName': t.paymentMethod == 'qris' ? 'QRIS' : 'Rekening Bank',
          'sourceType': 'penjualan',
          'sourceId': t.invoiceNumber,
          'cashierName': t.cashierName,
          'note': 'Nota #${t.invoiceNumber} (${t.customerName})',
          'isInternalTransfer': false,
        });
      }
    }

    // 3. Explicit cash_flows entries in range
    final cfRows = await db.query(
      'cash_flows',
      where: 'date >= ? AND date <= ?',
      whereArgs: [startIso, endIso],
    );
    double totalDebtPayments = 0.0;
    double totalOtherIn = 0.0;
    double totalCashPurchases = 0.0;
    double totalTransferPurchases = 0.0;
    double totalSupplierPayments = 0.0;
    double totalOpExpenses = 0.0;
    double totalRefundOut = 0.0;
    double totalInternalTransfers = 0.0;
    double cashInDrawerRange = totalShiftModal + totalSalesCash;
    double cashOutDrawerRange = 0.0;

    for (final row in cfRows) {
      final f = CashFlowModel.fromMap(row);
      if (f.isInternalTransfer) {
        totalInternalTransfers += f.amount;
        if (f.accountName == 'Laci Kasir' && f.paymentMethod == 'tunai') {
          if (f.isIn) cashInDrawerRange += f.amount;
          if (f.isOut) cashOutDrawerRange += f.amount;
        }
      } else if (f.isIn) {
        if (f.sourceType == 'kasbon_bayar' || f.category.toLowerCase().contains('kasbon')) {
          totalDebtPayments += f.amount;
        } else if (f.sourceType == 'retur_void') {
          totalRefundOut = (totalRefundOut - f.amount).clamp(0.0, double.infinity);
        } else {
          totalOtherIn += f.amount;
        }
        if (f.paymentMethod == 'tunai' && f.accountName == 'Laci Kasir') {
          cashInDrawerRange += f.amount;
        }
      } else if (f.isOut) {
        if (f.sourceType == 'pembelian' || f.category.toLowerCase().contains('pembelian')) {
          if (f.paymentMethod == 'tunai') {
            totalCashPurchases += f.amount;
          } else {
            totalTransferPurchases += f.amount;
          }
        } else if (f.sourceType == 'utang_supplier_bayar') {
          totalSupplierPayments += f.amount;
        } else if (f.sourceType == 'retur_void') {
          totalOtherIn = (totalOtherIn - f.amount).clamp(0.0, double.infinity);
        } else if (f.sourceType == 'retur' || f.category.toLowerCase().contains('retur')) {
          totalRefundOut += f.amount;
        } else {
          totalOpExpenses += f.amount;
        }
        if (f.paymentMethod == 'tunai' && f.accountName == 'Laci Kasir') {
          cashOutDrawerRange += f.amount;
        }
      }

      entries.add({
        'date': f.date,
        'type': f.type,
        'category': f.category,
        'amount': f.amount,
        'paymentMethod': f.paymentMethod,
        'accountName': f.accountName,
        'sourceType': f.sourceType,
        'sourceId': f.sourceId,
        'cashierName': f.cashierName,
        'note': f.note,
        'isInternalTransfer': f.isInternalTransfer,
      });
    }

    entries.sort((a, b) => (b['date'] as DateTime).compareTo(a['date'] as DateTime));

    final totalOperationalIn = totalSalesCash + totalSalesNonCash + totalDebtPayments + totalOtherIn;
    final totalOperationalOut =
        totalCashPurchases + totalTransferPurchases + totalSupplierPayments + totalOpExpenses + totalRefundOut;
    final endingCashBalance = openingBalance + cashInDrawerRange - cashOutDrawerRange;

    return {
      'openingBalance': openingBalance,
      'endingCashBalance': endingCashBalance,
      'totalShiftModal': totalShiftModal,
      'totalSalesCash': totalSalesCash,
      'totalSalesNonCash': totalSalesNonCash,
      'totalDebtPayments': totalDebtPayments,
      'totalOtherIn': totalOtherIn,
      'totalCashPurchases': totalCashPurchases,
      'totalTransferPurchases': totalTransferPurchases,
      'totalSupplierPayments': totalSupplierPayments,
      'totalOpExpenses': totalOpExpenses,
      'totalRefundOut': totalRefundOut,
      'totalInternalTransfers': totalInternalTransfers,
      'totalOperationalIn': totalOperationalIn,
      'totalOperationalOut': totalOperationalOut,
      'entries': entries,
    };
  }

  // ================= ATTENDANCE & AUDIT LOGS =================
  Future<AttendanceModel?> getLatestAttendanceForEmployee(int employeeId) async {
    final db = await database;
    final rows = await db.query(
      'attendances',
      where: 'employee_id = ?',
      whereArgs: [employeeId],
      orderBy: 'timestamp DESC, id DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return AttendanceModel.fromMap(rows.first);
  }

  Future<List<AttendanceModel>> getAttendancesTodayForEmployee(int employeeId, DateTime refDate) async {
    final db = await database;
    final start = DateTime(refDate.year, refDate.month, refDate.day).toIso8601String();
    final end = DateTime(refDate.year, refDate.month, refDate.day, 23, 59, 59, 999).toIso8601String();
    final rows = await db.query(
      'attendances',
      where: 'employee_id = ? AND timestamp >= ? AND timestamp <= ?',
      whereArgs: [employeeId, start, end],
      orderBy: 'timestamp ASC, id ASC',
    );
    return rows.map((e) => AttendanceModel.fromMap(e)).toList();
  }

  Future<DateTime?> getMaxSystemActivityTimestamp() async {
    final db = await database;
    final dates = <DateTime>[];
    for (final q in [
      'SELECT MAX(timestamp) as dt FROM attendances',
      'SELECT MAX(date) as dt FROM transactions',
      'SELECT MAX(timestamp) as dt FROM audit_logs',
    ]) {
      final r = await db.rawQuery(q);
      final raw = r.first['dt']?.toString();
      if (raw != null && raw.isNotEmpty) {
        final parsed = DateTime.tryParse(raw);
        if (parsed != null) dates.add(parsed);
      }
    }
    if (dates.isEmpty) return null;
    dates.sort();
    return dates.last;
  }

  Future<int> insertAttendance(AttendanceModel att) async {
    final db = await database;
    return await db.transaction((txn) async {
      // 1. Device clock anti-tampering check
      final maxRows = await txn.rawQuery('''
        SELECT MAX(dt) as max_dt FROM (
          SELECT MAX(timestamp) as dt FROM attendances
          UNION ALL
          SELECT MAX(date) as dt FROM transactions
          UNION ALL
          SELECT MAX(timestamp) as dt FROM audit_logs
        )
      ''');
      final maxRaw = maxRows.first['max_dt']?.toString();
      if (maxRaw != null && maxRaw.isNotEmpty) {
        final latestSystemTime = DateTime.tryParse(maxRaw);
        if (latestSystemTime != null &&
            att.timestamp.isBefore(latestSystemTime.subtract(const Duration(minutes: 2)))) {
          throw StateError(
            'Waktu perangkat terdeteksi mundur dari aktivitas terakhir di database. Sinkronkan jam perangkat sebelum absensi.',
          );
        }
      }

      // 2. Anti-replay challenge token check (prevent duplicate submission with same token by employee)
      final dupToken = await txn.query(
        'attendances',
        where: 'employee_id = ? AND challenge_code = ? AND timestamp >= ?',
        whereArgs: [
          att.employeeId,
          att.challengeCode,
          DateTime(att.timestamp.year, att.timestamp.month, att.timestamp.day).toIso8601String(),
        ],
        limit: 1,
      );
      if (dupToken.isNotEmpty && att.challengeCode != 'ADMIN-CORRECTION') {
        throw StateError('Token tantangan sudah digunakan (cegah duplikasi / replay). Muat ulang kamera.');
      }

      // 3. Strict session sequence check on same work day
      final dayStart = DateTime(att.timestamp.year, att.timestamp.month, att.timestamp.day).toIso8601String();
      final dayEnd =
          DateTime(att.timestamp.year, att.timestamp.month, att.timestamp.day, 23, 59, 59, 999).toIso8601String();
      final todayRows = await txn.query(
        'attendances',
        where: 'employee_id = ? AND timestamp >= ? AND timestamp <= ?',
        whereArgs: [att.employeeId, dayStart, dayEnd],
        orderBy: 'timestamp DESC, id DESC',
      );

      final hasCheckedInToday = todayRows.any((r) => r['type'] == 'masuk');
      final hasCheckedOutToday = todayRows.any((r) => r['type'] == 'pulang');

      if (att.type == 'masuk') {
        if (hasCheckedInToday) {
          final prev = AttendanceModel.fromMap(
            todayRows.firstWhere((r) => r['type'] == 'masuk'),
          );
          final hhmm =
              '${prev.timestamp.hour.toString().padLeft(2, '0')}:${prev.timestamp.minute.toString().padLeft(2, '0')}';
          throw StateError(
            'Anda sudah melakukan absensi MASUK hari ini pada pukul $hhmm. Tidak dapat absen masuk dua kali.',
          );
        }
      } else if (att.type == 'pulang') {
        if (!hasCheckedInToday) {
          throw StateError('Anda belum melakukan absensi MASUK hari ini. Lakukan absensi masuk terlebih dahulu.');
        }
        if (hasCheckedOutToday) {
          final prevOut = AttendanceModel.fromMap(
            todayRows.firstWhere((r) => r['type'] == 'pulang'),
          );
          final hhmm =
              '${prevOut.timestamp.hour.toString().padLeft(2, '0')}:${prevOut.timestamp.minute.toString().padLeft(2, '0')}';
          throw StateError(
            'Anda sudah melakukan absensi PULANG hari ini pada pukul $hhmm. Tidak dapat absen pulang dua kali.',
          );
        }
      }

      return await txn.insert('attendances', att.toMap());
    });
  }

  Future<void> correctAttendanceByAdmin({
    required int attendanceId,
    required String newStatus,
    required int newLateMinutes,
    required String correctionNote,
    required UserModel admin,
  }) async {
    if (!admin.hasPermission(AppPermissions.manageEmployees) && !admin.isOwner) {
      throw StateError('Hanya Admin / Owner yang berwenang melakukan koreksi absensi.');
    }
    if (correctionNote.trim().isEmpty) {
      throw StateError('Alasan koreksi wajib diisi.');
    }
    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.query('attendances', where: 'id = ?', whereArgs: [attendanceId], limit: 1);
      if (rows.isEmpty) throw StateError('Data absensi tidak ditemukan.');
      final oldAtt = AttendanceModel.fromMap(rows.first);

      await txn.update(
        'attendances',
        {
          'status': newStatus,
          'late_minutes': newLateMinutes,
          'is_corrected': 1,
          'correction_note': '${correctionNote.trim()} (oleh ${admin.name})',
        },
        where: 'id = ?',
        whereArgs: [attendanceId],
      );

      await txn.insert('audit_logs', {
        'timestamp': DateTime.now().toIso8601String(),
        'user_id': admin.id ?? 0,
        'user_name': admin.name,
        'user_role': admin.role,
        'action_type': 'koreksi_absensi',
        'module': 'Absensi',
        'object_id': 'ATT-$attendanceId',
        'before_value': 'status=${oldAtt.status}, lateMinutes=${oldAtt.lateMinutes}',
        'after_value': 'status=$newStatus, lateMinutes=$newLateMinutes',
        'details': 'Koreksi absensi ${oldAtt.employeeName} (${oldAtt.type}): ${correctionNote.trim()}',
      });
    });
  }

  Future<List<AttendanceModel>> getRecentAttendances({int limit = 150}) async {
    final db = await database;
    final res = await db.query('attendances', orderBy: 'timestamp DESC', limit: limit);
    return res.map((e) => AttendanceModel.fromMap(e)).toList();
  }

  Future<int> insertAuditLog(AuditLogModel log) async {
    final db = await database;
    return await db.insert('audit_logs', log.toMap());
  }

  Future<List<AuditLogModel>> getAuditLogs({int limit = 100}) async {
    final db = await database;
    final res = await db.query('audit_logs', orderBy: 'timestamp DESC', limit: limit);
    return res.map((e) => AuditLogModel.fromMap(e)).toList();
  }

  Future<List<AuditLogModel>> getAuditLogsFiltered({
    DateTime? start,
    DateTime? end,
    int? userId,
    String? actionType,
    String? searchQuery,
    int limit = 30,
    int offset = 0,
  }) async {
    final db = await database;
    final whereParts = <String>[];
    final whereArgs = <dynamic>[];

    if (start != null && end != null) {
      whereParts.add('timestamp >= ? AND timestamp <= ?');
      whereArgs.addAll([
        DateTime(start.year, start.month, start.day).toIso8601String(),
        DateTime(end.year, end.month, end.day, 23, 59, 59, 999).toIso8601String(),
      ]);
    }
    if (userId != null) {
      whereParts.add('user_id = ?');
      whereArgs.add(userId);
    }
    if (actionType != null && actionType.isNotEmpty && actionType != 'semua') {
      whereParts.add('action_type = ?');
      whereArgs.add(actionType);
    }
    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final q = '%${searchQuery.trim()}%';
      whereParts.add('(module LIKE ? OR details LIKE ? OR user_name LIKE ? OR object_id LIKE ?)');
      whereArgs.addAll([q, q, q, q]);
    }

    final res = await db.query(
      'audit_logs',
      where: whereParts.isEmpty ? null : whereParts.join(' AND '),
      whereArgs: whereParts.isEmpty ? null : whereArgs,
      orderBy: 'timestamp DESC, id DESC',
      limit: limit,
      offset: offset,
    );
    return res.map((e) => AuditLogModel.fromMap(e)).toList();
  }

  // ================= CUSTOMER DEBTS (KASBON) =================
  Future<List<CustomerDebtModel>> getCustomerDebts() async {
    final db = await database;
    final res = await db.query('customer_debts', orderBy: 'due_date ASC');
    return res.map((e) => CustomerDebtModel.fromMap(e)).toList();
  }

  Future<List<CustomerDebtPaymentModel>> getCustomerDebtPayments(int debtId) async {
    final db = await database;
    final res = await db.query(
      'customer_debt_payments',
      where: 'debt_id = ?',
      whereArgs: [debtId],
      orderBy: 'date DESC',
    );
    return res.map((e) => CustomerDebtPaymentModel.fromMap(e)).toList();
  }

  Future<double> getCustomerOutstandingDebt(int customerId, String customerName) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT COALESCE(SUM(MAX(0, total_debt - paid_debt)), 0) as rem
      FROM customer_debts
      WHERE customer_id = ? OR (customer_id IS NULL AND LOWER(customer_name) = LOWER(?))
    ''', [customerId, customerName]);
    return (rows.first['rem'] as num?)?.toDouble() ?? 0.0;
  }

  Future<List<TransactionModel>> getCustomerPurchaseHistory(int customerId, String customerName) async {
    final db = await database;
    final rows = await db.query(
      'transactions',
      where: "(customer_id = ? OR (customer_id IS NULL AND LOWER(customer_name) = LOWER(?))) AND status != 'voided'",
      whereArgs: [customerId, customerName],
      orderBy: 'date DESC',
      limit: 50,
    );
    final list = <TransactionModel>[];
    for (final m in rows) {
      final t = TransactionModel.fromMap(m);
      final items = await db.query('transaction_items', where: 'transaction_id = ?', whereArgs: [t.id]);
      t.items = items.map((e) => TransactionItemModel.fromMap(e)).toList();
      list.add(t);
    }
    return list;
  }

  Future<void> payCustomerDebt(
    int debtId,
    double amountPaid, {
    String paymentMethod = 'tunai',
    int? shiftId,
    String cashierName = 'Kasir',
    String note = '',
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      final debtRes = await txn.query('customer_debts', where: 'id = ?', whereArgs: [debtId]);
      if (debtRes.isEmpty) return;

      final debt = CustomerDebtModel.fromMap(debtRes.first);
      if (debt.remainingDebt <= 0) {
        throw StateError('Kasbon ini sudah lunas.');
      }
      final actualPayment = amountPaid > debt.remainingDebt ? debt.remainingDebt : amountPaid;
      if (actualPayment <= 0) {
        throw StateError('Nominal pembayaran harus lebih dari Rp 0.');
      }
      if (paymentMethod == 'tunai' && shiftId == null) {
        throw StateError('Buka shift kasir terlebih dahulu untuk menerima pembayaran kasbon tunai.');
      }
      final newPaid = debt.paidDebt + actualPayment;
      final nowIso = DateTime.now().toIso8601String();

      await txn.update(
        'customer_debts',
        {
          'paid_debt': newPaid,
          'last_payment_date': nowIso,
        },
        where: 'id = ?',
        whereArgs: [debtId],
      );

      await txn.insert('customer_debt_payments', {
        'debt_id': debtId,
        'customer_id': debt.customerId,
        'amount': actualPayment,
        'payment_method': paymentMethod,
        'shift_id': shiftId,
        'cashier_name': cashierName,
        'date': nowIso,
        'note': note.isNotEmpty ? note : 'Cicilan / Pelunasan #${debt.invoiceNumber}',
      });

      await txn.insert('cash_flows', {
        'shift_id': paymentMethod == 'tunai' ? shiftId : null,
        'type': 'in',
        'category': 'Pelunasan Kasbon',
        'amount': actualPayment,
        'payment_method': paymentMethod,
        'account_name': paymentMethod == 'tunai' ? 'Laci Kasir' : (paymentMethod == 'qris' ? 'QRIS' : 'Rekening Bank'),
        'source_type': 'kasbon_bayar',
        'source_id': debt.invoiceNumber,
        'is_internal_transfer': 0,
        'note': 'Pelunasan dari ${debt.customerName} (#${debt.invoiceNumber})',
        'date': nowIso,
        'cashier_name': cashierName,
      });

      if (shiftId != null && paymentMethod == 'tunai') {
        await txn.rawUpdate(
          'UPDATE shifts SET total_cash_in = total_cash_in + ? WHERE id = ?',
          [actualPayment, shiftId],
        );
      }
    });
  }

  // ================= CUSTOMERS CRUD =================
  Future<List<CustomerModel>> getCustomers({String? query}) async {
    final db = await database;
    if (query != null && query.isNotEmpty) {
      final res = await db.query(
        'customers',
        where: 'name LIKE ? OR phone LIKE ?',
        whereArgs: ['%$query%', '%$query%'],
        orderBy: 'name ASC',
      );
      return res.map((e) => CustomerModel.fromMap(e)).toList();
    }
    final res = await db.query('customers', orderBy: 'name ASC');
    return res.map((e) => CustomerModel.fromMap(e)).toList();
  }

  Future<int> insertCustomer(CustomerModel customer) async {
    final db = await database;
    late final int id;
    final nextVer = await db.transaction((txn) async {
      id = await txn.insert('customers', customer.toMap());
      return bumpSyncVersionTxn(txn, customerId: id);
    });
    onMultiDeviceEvent?.call('customer_changed', {'sync_version': nextVer, 'customer_id': id});
    return id;
  }

  Future<void> updateCustomer(CustomerModel customer) async {
    final db = await database;
    final nextVer = await db.transaction((txn) async {
      await txn.update('customers', customer.toMap(), where: 'id = ?', whereArgs: [customer.id]);
      return bumpSyncVersionTxn(txn, customerId: customer.id);
    });
    onMultiDeviceEvent?.call('customer_changed', {'sync_version': nextVer, 'customer_id': customer.id});
  }

  Future<void> deleteCustomer(int id) async {
    final db = await database;
    final nextVer = await db.transaction((txn) async {
      await txn.delete('customers', where: 'id = ?', whereArgs: [id]);
      return bumpSyncVersionTxn(txn);
    });
    onMultiDeviceEvent?.call('customer_changed', {'sync_version': nextVer, 'customer_id': id, 'deleted': true});
  }

  // ================= PURCHASES (RESTOCK / PEMBELIAN) & SUPPLIER DEBTS =================
  Future<List<PurchaseModel>> getPurchases({int limit = 100}) async {
    final db = await database;
    final res = await db.query('purchases', orderBy: 'date DESC', limit: limit);
    final List<PurchaseModel> list = [];
    for (final m in res) {
      final itemRows = await db.query('purchase_items', where: 'purchase_id = ?', whereArgs: [m['id']]);
      final items = itemRows.map((e) => PurchaseItemModel.fromMap(e)).toList();
      final p = PurchaseModel.fromMap(m);
      list.add(PurchaseModel(
        id: p.id,
        purchaseNumber: p.purchaseNumber,
        supplierName: p.supplierName,
        supplierPhone: p.supplierPhone,
        date: p.date,
        totalAmount: p.totalAmount,
        paymentMethod: p.paymentMethod,
        cashPaid: p.cashPaid,
        transferPaid: p.transferPaid,
        creditAmount: p.creditAmount,
        transferAccount: p.transferAccount,
        transferRef: p.transferRef,
        dueDate: p.dueDate,
        status: p.status,
        shiftId: p.shiftId,
        note: p.note,
        createdBy: p.createdBy,
        items: items,
      ));
    }
    return list;
  }

  Future<int> insertPurchase(
    PurchaseModel purchase, {
    int? shiftId,
    bool updateProductCostPrice = true,
  }) async {
    final db = await database;
    final targetShiftId = shiftId ?? purchase.shiftId;
    return await db.transaction((txn) async {
      final paidSum = purchase.cashPaid + purchase.transferPaid + purchase.creditAmount;
      if ((paidSum - purchase.totalAmount).abs() > 0.01) {
        throw StateError(
          'Total komponen pembayaran (Tunai + Transfer + Kredit) tidak sama dengan total pembelian.',
        );
      }
      if (purchase.cashPaid > 0) {
        await _ensureSufficientShiftCash(txn, targetShiftId, purchase.cashPaid);
      }
      if (purchase.transferPaid > 0 && purchase.transferAccount.trim().isEmpty) {
        throw StateError('Pilih atau isi rekening pembayaran untuk komponen transfer.');
      }

      final pMap = purchase.toMap();
      if (targetShiftId != null) pMap['shift_id'] = targetShiftId;
      final pid = await txn.insert('purchases', pMap);

      for (final item in purchase.items) {
        await txn.insert('purchase_items', {
          'purchase_id': pid,
          'product_id': item.productId,
          'product_name': item.productName,
          'qty': item.qty,
          'unit_name': item.unitName,
          'conversion_factor': item.conversionFactor,
          'cost_price': item.costPrice,
          'subtotal': item.subtotal,
        });

        await _recordStockMovement(
          txn,
          productId: item.productId,
          movementType: MovementTypes.purchaseIn,
          bucket: 'sellable',
          qtyDelta: item.baseStockQty,
          referenceType: 'purchase',
          referenceId: pid,
          referenceNumber: purchase.purchaseNumber,
          userName: purchase.createdBy,
          note: 'Pembelian #${purchase.purchaseNumber} (${item.qty} ${item.unitName})',
          enforceNonNegative: false,
        );

        if (updateProductCostPrice && item.conversionFactor > 0) {
          final baseCost = item.costPrice / item.conversionFactor;
          await txn.update(
            'products',
            {'cost_price': baseCost},
            where: 'id = ?',
            whereArgs: [item.productId],
          );
        }
      }

      if (purchase.cashPaid > 0) {
        await txn.insert('cash_flows', {
          'shift_id': targetShiftId,
          'type': 'out',
          'category': 'Pembelian Stok Tunai',
          'amount': purchase.cashPaid,
          'payment_method': 'tunai',
          'account_name': 'Laci Kasir',
          'source_type': 'pembelian',
          'source_id': purchase.purchaseNumber,
          'is_internal_transfer': 0,
          'note': 'Pembelian #${purchase.purchaseNumber} (${purchase.supplierName})',
          'date': purchase.date.toIso8601String(),
          'cashier_name': purchase.createdBy,
        });
        await txn.rawUpdate(
          'UPDATE shifts SET total_cash_out = total_cash_out + ? WHERE id = ?',
          [purchase.cashPaid, targetShiftId],
        );
      }

      if (purchase.transferPaid > 0) {
        await txn.insert('cash_flows', {
          'shift_id': null,
          'type': 'out',
          'category': 'Pembelian Stok Transfer',
          'amount': purchase.transferPaid,
          'payment_method': 'transfer',
          'account_name': purchase.transferAccount.isNotEmpty ? purchase.transferAccount : 'Rekening Bank',
          'source_type': 'pembelian',
          'source_id': purchase.purchaseNumber,
          'is_internal_transfer': 0,
          'note':
              'Transfer ke ${purchase.supplierName} (#${purchase.purchaseNumber}) Ref: ${purchase.transferRef.isEmpty ? "-" : purchase.transferRef}',
          'date': purchase.date.toIso8601String(),
          'cashier_name': purchase.createdBy,
        });
      }

      if (purchase.creditAmount > 0) {
        await txn.insert('supplier_debts', {
          'purchase_id': pid,
          'purchase_number': purchase.purchaseNumber,
          'supplier_name': purchase.supplierName,
          'supplier_phone': purchase.supplierPhone,
          'total_debt': purchase.creditAmount,
          'paid_debt': 0.0,
          'purchase_date': purchase.date.toIso8601String(),
          'due_date': (purchase.dueDate ?? purchase.date.add(const Duration(days: 30))).toIso8601String(),
          'status': 'belum_lunas',
          'note': purchase.note,
        });
      }

      return pid;
    });
  }

  Future<void> voidPurchase(int purchaseId, {int? shiftId, String cancelledBy = 'Admin'}) async {
    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.query('purchases', where: 'id = ?', whereArgs: [purchaseId], limit: 1);
      if (rows.isEmpty) return;
      final p = PurchaseModel.fromMap(rows.first);
      if (p.isVoided) return;

      final itemRows = await txn.query('purchase_items', where: 'purchase_id = ?', whereArgs: [purchaseId]);
      for (final m in itemRows) {
        final item = PurchaseItemModel.fromMap(m);
        await _recordStockMovement(
          txn,
          productId: item.productId,
          movementType: MovementTypes.purchaseVoidOut,
          bucket: 'sellable',
          qtyDelta: -item.baseStockQty,
          referenceType: 'purchase_void',
          referenceId: purchaseId,
          referenceNumber: p.purchaseNumber,
          userName: cancelledBy,
          note: 'Batal Pembelian #${p.purchaseNumber}',
          enforceNonNegative: false,
        );
      }

      final targetShiftId = shiftId ?? p.shiftId;
      final nowIso = DateTime.now().toIso8601String();

      if (p.cashPaid > 0) {
        await txn.insert('cash_flows', {
          'shift_id': targetShiftId,
          'type': 'in',
          'category': 'Pembalikan Pembelian Batal',
          'amount': p.cashPaid,
          'payment_method': 'tunai',
          'account_name': 'Laci Kasir',
          'source_type': 'pembelian',
          'source_id': p.purchaseNumber,
          'is_internal_transfer': 0,
          'note': 'Batal Pembelian #${p.purchaseNumber} (${p.supplierName})',
          'date': nowIso,
          'cashier_name': cancelledBy,
        });
        if (targetShiftId != null) {
          await txn.rawUpdate(
            'UPDATE shifts SET total_cash_in = total_cash_in + ? WHERE id = ?',
            [p.cashPaid, targetShiftId],
          );
        }
      }
      if (p.transferPaid > 0) {
        await txn.insert('cash_flows', {
          'shift_id': null,
          'type': 'in',
          'category': 'Pembalikan Transfer Pembelian Batal',
          'amount': p.transferPaid,
          'payment_method': 'transfer',
          'account_name': p.transferAccount.isNotEmpty ? p.transferAccount : 'Rekening Bank',
          'source_type': 'pembelian',
          'source_id': p.purchaseNumber,
          'is_internal_transfer': 0,
          'note': 'Pengembalian Transfer Batal #${p.purchaseNumber}',
          'date': nowIso,
          'cashier_name': cancelledBy,
        });
      }

      await txn.update(
        'supplier_debts',
        {'status': 'dibatalkan', 'note': 'Pembelian dibatalkan oleh $cancelledBy'},
        where: 'purchase_id = ?',
        whereArgs: [purchaseId],
      );
      await txn.update('purchases', {'status': 'voided'}, where: 'id = ?', whereArgs: [purchaseId]);
    });
  }

  Future<List<SupplierDebtModel>> getSupplierDebts() async {
    final db = await database;
    final res = await db.query('supplier_debts', orderBy: 'purchase_date DESC');
    return res.map((e) => SupplierDebtModel.fromMap(e)).toList();
  }

  Future<List<SupplierDebtPaymentModel>> getSupplierDebtPayments(int supplierDebtId) async {
    final db = await database;
    final res = await db.query(
      'supplier_debt_payments',
      where: 'supplier_debt_id = ?',
      whereArgs: [supplierDebtId],
      orderBy: 'date DESC',
    );
    return res.map((e) => SupplierDebtPaymentModel.fromMap(e)).toList();
  }

  Future<void> paySupplierDebt({
    required int supplierDebtId,
    required double amount,
    required String paymentSource, // 'kas_laci' | 'transfer'
    String accountName = 'Laci Kasir',
    String referenceNumber = '',
    int? shiftId,
    String paidBy = 'Admin',
    String note = '',
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.query('supplier_debts', where: 'id = ?', whereArgs: [supplierDebtId], limit: 1);
      if (rows.isEmpty) throw StateError('Data utang supplier tidak ditemukan.');
      final debt = SupplierDebtModel.fromMap(rows.first);
      if (debt.isCancelled) throw StateError('Utang supplier ini berasal dari pembelian yang dibatalkan.');
      if (debt.isPaidOff) throw StateError('Utang supplier ini sudah lunas.');

      final actualPay = amount > debt.remainingDebt ? debt.remainingDebt : amount;
      if (actualPay <= 0) throw StateError('Nominal pembayaran harus lebih dari Rp 0.');

      if (paymentSource == 'kas_laci') {
        await _ensureSufficientShiftCash(txn, shiftId, actualPay);
      }

      final newPaid = debt.paidDebt + actualPay;
      final newStatus = (debt.totalDebt - newPaid) <= 0.001 ? 'lunas' : 'cicilan';
      final nowIso = DateTime.now().toIso8601String();

      await txn.update(
        'supplier_debts',
        {
          'paid_debt': newPaid,
          'last_payment_date': nowIso,
          'status': newStatus,
        },
        where: 'id = ?',
        whereArgs: [supplierDebtId],
      );

      await txn.insert('supplier_debt_payments', {
        'supplier_debt_id': supplierDebtId,
        'amount': actualPay,
        'payment_source': paymentSource,
        'account_name': paymentSource == 'kas_laci' ? 'Laci Kasir' : accountName,
        'reference_number': referenceNumber,
        'shift_id': paymentSource == 'kas_laci' ? shiftId : null,
        'paid_by': paidBy,
        'date': nowIso,
        'note': note,
      });

      await txn.insert('cash_flows', {
        'shift_id': paymentSource == 'kas_laci' ? shiftId : null,
        'type': 'out',
        'category': 'Pembayaran Utang Supplier',
        'amount': actualPay,
        'payment_method': paymentSource == 'kas_laci' ? 'tunai' : 'transfer',
        'account_name': paymentSource == 'kas_laci' ? 'Laci Kasir' : accountName,
        'source_type': 'utang_supplier_bayar',
        'source_id': debt.purchaseNumber,
        'is_internal_transfer': 0,
        'note':
            'Bayar utang ${debt.supplierName} (#${debt.purchaseNumber})${referenceNumber.isNotEmpty ? " Ref: $referenceNumber" : ""}',
        'date': nowIso,
        'cashier_name': paidBy,
      });

      if (paymentSource == 'kas_laci' && shiftId != null) {
        await txn.rawUpdate(
          'UPDATE shifts SET total_cash_out = total_cash_out + ? WHERE id = ?',
          [actualPay, shiftId],
        );
      }
    });
  }

  // ================= WAREHOUSE DOCS & STOCK OPNAME =================
  Future<int> insertWarehouseDoc(WarehouseDocModel doc) async {
    final db = await database;
    return await db.insert('warehouse_docs', doc.toMap());
  }

  Future<void> updateWarehouseDoc(WarehouseDocModel doc) async {
    final db = await database;
    await db.update(
      'warehouse_docs',
      doc.toMap(),
      where: 'id = ?',
      whereArgs: [doc.id],
    );
  }

  Future<void> updateWarehouseDocStatus(int docId, String status) async {
    final db = await database;
    await db.update(
      'warehouse_docs',
      {'status': status},
      where: 'id = ?',
      whereArgs: [docId],
    );
  }

  Future<List<WarehouseDocModel>> getWarehouseDocs() async {
    final db = await database;
    final res = await db.query('warehouse_docs', orderBy: 'date DESC');
    return res.map((e) => WarehouseDocModel.fromMap(e)).toList();
  }

  Future<int> insertStockOpname(StockOpnameModel opname) async {
    final ids = await insertStockOpnamesBatch([opname]);
    return ids.first;
  }

  Future<List<int>> insertStockOpnamesBatch(List<StockOpnameModel> entries) async {
    if (entries.isEmpty) return [];
    final db = await database;
    return await db.transaction((txn) async {
      final seenProductIds = <int>{};
      final insertedIds = <int>[];

      for (final entry in entries) {
        if (!seenProductIds.add(entry.productId)) {
          throw StateError('Duplikasi produk "${entry.productName}" dalam satu sesi stock opname dicegah.');
        }
        final prodRows = await txn.query('products', where: 'id = ?', whereArgs: [entry.productId], limit: 1);
        if (prodRows.isEmpty) {
          throw StateError('Produk "${entry.productName}" tidak ditemukan.');
        }
        final freshSystemStock = (prodRows.first['stock'] as num?)?.toDouble() ?? 0.0;
        final diff = entry.physicalStock - freshSystemStock;

        final synced = StockOpnameModel(
          date: entry.date,
          productId: entry.productId,
          productCode: entry.productCode,
          productName: entry.productName,
          systemStock: freshSystemStock,
          physicalStock: entry.physicalStock,
          difference: diff,
          note: entry.note,
          auditedBy: entry.auditedBy,
        );

        final id = await txn.insert('stock_opnames', synced.toMap());
        insertedIds.add(id);
        await _recordStockMovement(
          txn,
          productId: entry.productId,
          movementType: MovementTypes.opnameAdjust,
          bucket: 'sellable',
          qtyDelta: diff,
          referenceType: 'stock_opname',
          referenceId: id,
          referenceNumber: 'OPN-$id',
          userName: entry.auditedBy,
          note: entry.note.isNotEmpty ? entry.note : 'Stok opname fisik ${entry.physicalStock}',
          enforceNonNegative: false,
        );
      }
      return insertedIds;
    });
  }

  Future<List<StockOpnameModel>> getStockOpnames() async {
    final db = await database;
    final res = await db.query('stock_opnames', orderBy: 'date DESC');
    return res.map((e) => StockOpnameModel.fromMap(e)).toList();
  }

  // ================= PROMOS =================
  Future<List<PromoModel>> getActivePromos({bool includeInactive = false}) async {
    final db = await database;
    final res = includeInactive
        ? await db.query('promos', orderBy: 'id DESC')
        : await db.query('promos', where: 'is_active = 1', orderBy: 'id DESC');
    return res.map((e) => PromoModel.fromMap(e)).toList();
  }

  Future<int> insertPromo(PromoModel promo) async {
    final db = await database;
    late final int id;
    final nextVer = await db.transaction((txn) async {
      id = await txn.insert('promos', promo.toMap());
      return bumpSyncVersionTxn(txn, promoId: id);
    });
    onMultiDeviceEvent?.call('promo_changed', {'sync_version': nextVer, 'promo_id': id});
    return id;
  }

  Future<void> togglePromoActive(int id, bool isActive) async {
    final db = await database;
    final nextVer = await db.transaction((txn) async {
      await txn.update('promos', {'is_active': isActive ? 1 : 0}, where: 'id = ?', whereArgs: [id]);
      return bumpSyncVersionTxn(txn, promoId: id);
    });
    onMultiDeviceEvent?.call('promo_changed', {'sync_version': nextVer, 'promo_id': id});
  }

  Future<void> deletePromo(int id) async {
    final db = await database;
    final nextVer = await db.transaction((txn) async {
      await txn.delete('promos', where: 'id = ?', whereArgs: [id]);
      return bumpSyncVersionTxn(txn);
    });
    onMultiDeviceEvent?.call('promo_changed', {'sync_version': nextVer, 'promo_id': id, 'deleted': true});
  }

  // ================= PRINTERS CRUD =================
  Future<List<PrinterDeviceModel>> getPrinters() async {
    final db = await database;
    final res = await db.query('printers', orderBy: 'is_default DESC, id ASC');
    return res.map((e) => PrinterDeviceModel.fromMap(e)).toList();
  }

  Future<int> insertPrinter(PrinterDeviceModel printer) async {
    final db = await database;
    return await db.transaction((txn) async {
      if (printer.isDefault) {
        await txn.update('printers', {'is_default': 0});
      }
      final newId = await txn.insert('printers', printer.toMap());
      if (printer.isDefault && printer.connectionType != PrinterConnectionType.system) {
        await _promotePrinterForDefaultRegistersTxn(txn, newId);
      }
      return newId;
    });
  }

  Future<void> updatePrinter(PrinterDeviceModel printer) async {
    final db = await database;
    await db.transaction((txn) async {
      if (printer.isDefault) {
        await txn.update('printers', {'is_default': 0});
      }
      await txn.update('printers', printer.toMap(), where: 'id = ?', whereArgs: [printer.id]);
      if (printer.isDefault &&
          printer.id != null &&
          printer.connectionType != PrinterConnectionType.system) {
        await _promotePrinterForDefaultRegistersTxn(txn, printer.id!);
      }
    });
  }

  Future<void> setDefaultPrinter(int printerId) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.update('printers', {'is_default': 0});
      await txn.update('printers', {'is_default': 1}, where: 'id = ?', whereArgs: [printerId]);
      final rows = await txn.query('printers', where: 'id = ?', whereArgs: [printerId], limit: 1);
      if (rows.isNotEmpty &&
          (rows.first['connection_type'] ?? '') != PrinterConnectionType.system) {
        await _promotePrinterForDefaultRegistersTxn(txn, printerId);
      }
    });
  }

  Future<void> _promotePrinterForDefaultRegistersTxn(Transaction txn, int printerId) async {
    await txn.rawUpdate('''
      UPDATE cash_registers
      SET printer_id = ?
      WHERE printer_id IS NULL
         OR printer_id IN (SELECT id FROM printers WHERE connection_type = ?)
    ''', [printerId, PrinterConnectionType.system]);
  }

  Future<void> deletePrinter(int printerId) async {
    final db = await database;
    await db.delete('printers', where: 'id = ?', whereArgs: [printerId]);
  }

  // ================= SERVICE ORDERS (JASA SERVIS) =================
  Future<ServiceOrderModel?> getServiceOrderById(int id) async {
    final db = await database;
    final rows = await db.query('service_orders', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    final order = ServiceOrderModel.fromMap(rows.first);
    final partRows = await db.query('service_parts', where: 'service_order_id = ?', whereArgs: [id]);
    return ServiceOrderModel(
      id: order.id,
      ticketNumber: order.ticketNumber,
      customerId: order.customerId,
      customerName: order.customerName,
      customerPhone: order.customerPhone,
      deviceType: order.deviceType,
      brand: order.brand,
      model: order.model,
      imeiSn: order.imeiSn,
      accessories: order.accessories,
      complaint: order.complaint,
      physicalCondition: order.physicalCondition,
      photoPaths: order.photoPaths,
      technicianId: order.technicianId,
      technicianName: order.technicianName,
      estimatedCost: order.estimatedCost,
      serviceFee: order.serviceFee,
      partsTotal: order.partsTotal,
      downPayment: order.downPayment,
      paidAmount: order.paidAmount,
      status: order.status,
      createdAt: order.createdAt,
      updatedAt: order.updatedAt,
      completedAt: order.completedAt,
      pickedUpAt: order.pickedUpAt,
      warrantyDays: order.warrantyDays,
      notes: order.notes,
      parts: partRows.map((e) => ServicePartModel.fromMap(e)).toList(),
    );
  }

  Future<List<ServiceOrderModel>> getServiceOrders({
    String? status,
    int? technicianId,
    String? query,
  }) async {
    final db = await database;
    final whereParts = <String>[];
    final whereArgs = <dynamic>[];

    if (status != null && status.isNotEmpty && status != 'semua') {
      whereParts.add('status = ?');
      whereArgs.add(status);
    }
    if (technicianId != null) {
      whereParts.add('technician_id = ?');
      whereArgs.add(technicianId);
    }
    if (query != null && query.isNotEmpty) {
      whereParts.add('(ticket_number LIKE ? OR customer_name LIKE ? OR customer_phone LIKE ? OR model LIKE ? OR imei_sn LIKE ?)');
      whereArgs.addAll(['%$query%', '%$query%', '%$query%', '%$query%', '%$query%']);
    }

    final rows = await db.query(
      'service_orders',
      where: whereParts.isEmpty ? null : whereParts.join(' AND '),
      whereArgs: whereParts.isEmpty ? null : whereArgs,
      orderBy: 'updated_at DESC',
    );

    final result = <ServiceOrderModel>[];
    for (final r in rows) {
      final id = r['id'] as int;
      final partRows = await db.query('service_parts', where: 'service_order_id = ?', whereArgs: [id]);
      final base = ServiceOrderModel.fromMap(r);
      result.add(ServiceOrderModel(
        id: base.id,
        ticketNumber: base.ticketNumber,
        customerId: base.customerId,
        customerName: base.customerName,
        customerPhone: base.customerPhone,
        deviceType: base.deviceType,
        brand: base.brand,
        model: base.model,
        imeiSn: base.imeiSn,
        accessories: base.accessories,
        complaint: base.complaint,
        physicalCondition: base.physicalCondition,
        photoPaths: base.photoPaths,
        technicianId: base.technicianId,
        technicianName: base.technicianName,
        estimatedCost: base.estimatedCost,
        serviceFee: base.serviceFee,
        partsTotal: base.partsTotal,
        downPayment: base.downPayment,
        paidAmount: base.paidAmount,
        status: base.status,
        createdAt: base.createdAt,
        updatedAt: base.updatedAt,
        completedAt: base.completedAt,
        pickedUpAt: base.pickedUpAt,
        warrantyDays: base.warrantyDays,
        notes: base.notes,
        parts: partRows.map((e) => ServicePartModel.fromMap(e)).toList(),
      ));
    }
    return result;
  }

  Future<int> insertServiceOrder(
    ServiceOrderModel order, {
    int? shiftId,
    String cashierName = 'Kasir',
  }) async {
    final db = await database;
    return await db.transaction((txn) async {
      final id = await txn.insert('service_orders', order.toMap());
      for (final part in order.parts) {
        await txn.insert('service_parts', {
          'service_order_id': id,
          'product_id': part.productId,
          'product_name': part.productName,
          'qty': part.qty,
          'unit_name': part.unitName,
          'conversion_factor': part.conversionFactor,
          'unit_price': part.unitPrice,
          'cost_price': part.costPrice,
          'subtotal': part.subtotal,
        });
        if (part.productId != null) {
          await txn.rawUpdate(
            'UPDATE products SET stock = MAX(0, stock - ?) WHERE id = ?',
            [part.baseStockQty, part.productId],
          );
        }
      }

      if (order.downPayment > 0) {
        await txn.insert('cash_flows', {
          'shift_id': shiftId,
          'type': 'in',
          'category': 'DP Servis',
          'amount': order.downPayment,
          'note': 'DP Servis #${order.ticketNumber} (${order.customerName})',
          'date': DateTime.now().toIso8601String(),
          'cashier_name': cashierName,
        });
        if (shiftId != null) {
          await txn.rawUpdate(
            'UPDATE shifts SET total_cash_in = total_cash_in + ? WHERE id = ?',
            [order.downPayment, shiftId],
          );
        }
      }
      return id;
    });
  }

  Future<void> updateServiceOrder(ServiceOrderModel order) async {
    final db = await database;
    await db.update(
      'service_orders',
      order.toMap(),
      where: 'id = ?',
      whereArgs: [order.id],
    );
  }

  Future<void> addServicePart(int serviceOrderId, ServicePartModel part) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.insert('service_parts', {
        'service_order_id': serviceOrderId,
        'product_id': part.productId,
        'product_name': part.productName,
        'qty': part.qty,
        'unit_name': part.unitName,
        'conversion_factor': part.conversionFactor,
        'unit_price': part.unitPrice,
        'cost_price': part.costPrice,
        'subtotal': part.subtotal,
      });

      if (part.productId != null) {
        await txn.rawUpdate(
          'UPDATE products SET stock = MAX(0, stock - ?) WHERE id = ?',
          [part.baseStockQty, part.productId],
        );
      }

      final parts = await txn.query('service_parts', where: 'service_order_id = ?', whereArgs: [serviceOrderId]);
      final partsTotal = parts.fold(0.0, (s, e) => s + ((e['subtotal'] as num).toDouble()));
      await txn.update(
        'service_orders',
        {
          'parts_total': partsTotal,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [serviceOrderId],
      );
    });
  }

  Future<void> removeServicePart(int partId, int serviceOrderId) async {
    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.query('service_parts', where: 'id = ?', whereArgs: [partId], limit: 1);
      if (rows.isNotEmpty) {
        final part = ServicePartModel.fromMap(rows.first);
        if (part.productId != null) {
          await txn.rawUpdate(
            'UPDATE products SET stock = stock + ? WHERE id = ?',
            [part.baseStockQty, part.productId],
          );
        }
        await txn.delete('service_parts', where: 'id = ?', whereArgs: [partId]);
      }

      final parts = await txn.query('service_parts', where: 'service_order_id = ?', whereArgs: [serviceOrderId]);
      final partsTotal = parts.fold(0.0, (s, e) => s + ((e['subtotal'] as num).toDouble()));
      await txn.update(
        'service_orders',
        {
          'parts_total': partsTotal,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [serviceOrderId],
      );
    });
  }

  Future<void> updateServiceStatus(int orderId, String newStatus) async {
    final db = await database;
    await db.transaction((txn) async {
      final existingRows = await txn.query('service_orders', where: 'id = ?', whereArgs: [orderId], limit: 1);
      if (existingRows.isEmpty) return;
      final prevStatus = (existingRows.first['status'] ?? '').toString();

      // If cancelling an order that wasn't already cancelled, restore attached spareparts stock
      if (newStatus == ServiceStatus.dibatalkan && prevStatus != ServiceStatus.dibatalkan) {
        final parts = await txn.query('service_parts', where: 'service_order_id = ?', whereArgs: [orderId]);
        for (final pRow in parts) {
          final part = ServicePartModel.fromMap(pRow);
          if (part.productId != null) {
            await txn.rawUpdate(
              'UPDATE products SET stock = stock + ? WHERE id = ?',
              [part.baseStockQty, part.productId],
            );
          }
        }
      }

      final now = DateTime.now().toIso8601String();
      final updates = <String, dynamic>{
        'status': newStatus,
        'updated_at': now,
      };
      if (newStatus == ServiceStatus.selesai) updates['completed_at'] = now;
      if (newStatus == ServiceStatus.sudahDiambil) updates['picked_up_at'] = now;

      await txn.update('service_orders', updates, where: 'id = ?', whereArgs: [orderId]);
    });
  }

  Future<void> recordServicePayment({
    required int orderId,
    required double amount,
    required String paymentMethod, // 'tunai' | 'qris' | 'transfer'
    int? shiftId,
    String cashierName = 'Kasir',
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.query('service_orders', where: 'id = ?', whereArgs: [orderId], limit: 1);
      if (rows.isEmpty) return;
      final order = ServiceOrderModel.fromMap(rows.first);
      final newPaid = order.paidAmount + amount;

      await txn.update(
        'service_orders',
        {
          'paid_amount': newPaid,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [orderId],
      );

      await txn.insert('cash_flows', {
        'shift_id': paymentMethod == 'tunai' ? shiftId : null,
        'type': 'in',
        'category': 'Pembayaran Servis (${paymentMethod.toUpperCase()})',
        'amount': amount,
        'note': 'Servis #${order.ticketNumber} (${order.customerName})',
        'date': DateTime.now().toIso8601String(),
        'cashier_name': cashierName,
      });

      if (shiftId != null) {
        if (paymentMethod == 'tunai') {
          await txn.rawUpdate(
            'UPDATE shifts SET total_cash_in = total_cash_in + ? WHERE id = ?',
            [amount, shiftId],
          );
        } else if (paymentMethod == 'qris') {
          await txn.rawUpdate(
            'UPDATE shifts SET total_sales_qris = total_sales_qris + ? WHERE id = ?',
            [amount, shiftId],
          );
        } else if (paymentMethod == 'transfer') {
          await txn.rawUpdate(
            'UPDATE shifts SET total_sales_transfer = total_sales_transfer + ? WHERE id = ?',
            [amount, shiftId],
          );
        }
      }
    });
  }

  // ================= DASHBOARD ANALYTICS & ACTIVITY =================
  Future<Map<String, dynamic>> getDashboardAnalytics() async {
    final db = await database;
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day).toIso8601String();
    final endOfDay = DateTime(now.year, now.month, now.day, 23, 59, 59, 999).toIso8601String();

    final todayTxRows = await db.query(
      'transactions',
      where: "status != 'voided' AND date >= ? AND date <= ?",
      whereArgs: [startOfDay, endOfDay],
      orderBy: 'date DESC',
    );

    double todayRevenue = 0.0;
    double todayGrossProfit = 0.0;
    double todayCashSales = 0.0;
    double todayQrisSales = 0.0;
    double todayOtherSales = 0.0;

    for (final row in todayTxRows) {
      final trx = TransactionModel.fromMap(row);
      todayRevenue += trx.grandTotal;
      if (trx.paymentMethod == 'tunai') {
        todayCashSales += trx.grandTotal;
      } else if (trx.paymentMethod == 'qris') {
        todayQrisSales += trx.grandTotal;
      } else {
        todayOtherSales += trx.grandTotal;
      }

      final items = await db.query('transaction_items', where: 'transaction_id = ?', whereArgs: [trx.id]);
      for (final itemMap in items) {
        final item = TransactionItemModel.fromMap(itemMap);
        if (!item.isService) {
          todayGrossProfit +=
              (item.unitPrice - (item.costPrice * item.conversionFactor)) * item.qty - item.discount;
        } else {
          todayGrossProfit += item.subtotal;
        }
      }
    }

    final expenseRows = await db.rawQuery('''
      SELECT SUM(amount) as total_out FROM cash_flows
      WHERE type = 'out' AND date >= ? AND date <= ?
    ''', [startOfDay, endOfDay]);
    final todayExpense = (expenseRows.first['total_out'] as num?)?.toDouble() ?? 0.0;

    final productCountRes = await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM products WHERE is_active = 1',
    );
    final totalProducts = (productCountRes.first['cnt'] as num?)?.toInt() ?? 0;

    final activeServicesRes = await db.rawQuery(
      "SELECT COUNT(*) as cnt FROM service_orders WHERE status NOT IN ('sudah_diambil', 'dibatalkan')",
    );
    final activeServiceCount = (activeServicesRes.first['cnt'] as num?)?.toInt() ?? 0;

    final recentTx = await getRecentTransactions(limit: 5);
    final recentServices = await db.query('service_orders', orderBy: 'updated_at DESC', limit: 5);
    final recentOpnames = await db.query('stock_opnames', orderBy: 'date DESC', limit: 5);
    final recentFlows = await db.query('cash_flows', orderBy: 'date DESC', limit: 5);
    final recentAudits = await db.query('audit_logs', orderBy: 'timestamp DESC', limit: 5);

    return {
      'todayRevenue': todayRevenue,
      'todayTxCount': todayTxRows.length,
      'totalProducts': totalProducts,
      'todayGrossProfit': todayGrossProfit,
      'todayExpense': todayExpense,
      'todayCashSales': todayCashSales,
      'todayQrisSales': todayQrisSales,
      'todayOtherSales': todayOtherSales,
      'activeServiceCount': activeServiceCount,
      'recentTransactions': recentTx,
      'recentServices': recentServices.map((e) => ServiceOrderModel.fromMap(e)).toList(),
      'recentOpnames': recentOpnames.map((e) => StockOpnameModel.fromMap(e)).toList(),
      'recentCashFlows': recentFlows.map((e) => CashFlowModel.fromMap(e)).toList(),
      'recentAudits': recentAudits.map((e) => AuditLogModel.fromMap(e)).toList(),
    };
  }

  /// Actual SQLite-backed business intelligence report across Sales, Products,
  /// Customers, Suppliers, and Profit for any selected date range.
  Future<Map<String, dynamic>> getBusinessAnalyticsReport(DateTime start, DateTime end) async {
    final db = await database;
    final startIso = DateTime(start.year, start.month, start.day).toIso8601String();
    final endIso = DateTime(end.year, end.month, end.day, 23, 59, 59, 999).toIso8601String();

    final txRows = await db.query(
      'transactions',
      where: 'date >= ? AND date <= ?',
      whereArgs: [startIso, endIso],
      orderBy: 'date DESC',
    );

    final validTx = <TransactionModel>[];
    double grossSales = 0.0;
    double totalDiscount = 0.0;
    double cashSales = 0.0;
    double transferSales = 0.0;
    double qrisSales = 0.0;
    double kasbonSales = 0.0;
    double totalItemsSold = 0.0;
    double totalHpp = 0.0;

    final productStats = <int, Map<String, dynamic>>{};
    final categoryStats = <String, Map<String, dynamic>>{};
    final customerStats = <String, Map<String, dynamic>>{};
    final dailyTrend = <String, double>{};

    // Load active products map for category + zero-sales detection + low stock
    final allProdRows = await db.query('products', where: 'is_active = 1');
    final prodById = <int, ProductModel>{};
    for (final pm in allProdRows) {
      final p = ProductModel.fromMap(pm);
      if (p.id != null) prodById[p.id!] = p;
    }

    double creditRedeemedSales = 0.0;
    for (final row in txRows) {
      final t = TransactionModel.fromMap(row);
      final itemRows = await db.query('transaction_items', where: 'transaction_id = ?', whereArgs: [t.id]);
      t.items = itemRows.map((e) => TransactionItemModel.fromMap(e)).toList();

      if (t.status == 'voided' || t.status == 'void') continue;
      validTx.add(t);

      grossSales += t.grandTotal;
      totalDiscount += t.discountTotal;
      creditRedeemedSales += t.creditUsed;

      final dayKey = '${t.date.year}-${t.date.month.toString().padLeft(2, '0')}-${t.date.day.toString().padLeft(2, '0')}';
      dailyTrend[dayKey] = (dailyTrend[dayKey] ?? 0.0) + t.grandTotal;

      final netCollectedMethod = (t.grandTotal - t.creditUsed).clamp(0.0, t.grandTotal);
      switch (t.paymentMethod) {
        case 'tunai':
          cashSales += netCollectedMethod;
          break;
        case 'transfer':
          transferSales += netCollectedMethod;
          break;
        case 'qris':
          qrisSales += netCollectedMethod;
          break;
        case 'kasbon':
          kasbonSales += netCollectedMethod;
          break;
      }

      // Customer breakdown
      final custKey = t.customerId != null ? 'ID:${t.customerId}' : 'NAME:${t.customerName.toLowerCase()}';
      final cEntry = customerStats.putIfAbsent(custKey, () => {
            'customerId': t.customerId,
            'name': t.customerName,
            'phone': t.customerPhone,
            'freq': 0,
            'totalSpent': 0.0,
            'maxTrx': 0.0,
          });
      cEntry['freq'] = (cEntry['freq'] as int) + 1;
      cEntry['totalSpent'] = (cEntry['totalSpent'] as double) + t.grandTotal;
      if (t.grandTotal > (cEntry['maxTrx'] as double)) {
        cEntry['maxTrx'] = t.grandTotal;
      }

      for (final item in t.items) {
        totalItemsSold += item.qty;
        final itemHpp = item.isService ? 0.0 : (item.costPrice * item.conversionFactor * item.qty);
        totalHpp += itemHpp;
        final itemProfit = item.isService ? item.subtotal : (item.subtotal - itemHpp);

        final baseUnits = item.isService ? item.qty : (item.qty * item.conversionFactor);
        final pMeta = prodById[item.productId];
        final category = pMeta?.category ?? 'Umum';

        final pEntry = productStats.putIfAbsent(item.productId, () => {
              'productId': item.productId,
              'code': item.productCode,
              'name': item.productName,
              'category': category,
              'qtySold': 0.0,
              'revenue': 0.0,
              'hpp': 0.0,
              'profit': 0.0,
              'stock': pMeta?.stock ?? 0.0,
              'unit': pMeta?.baseUnit ?? item.unitName,
            });
        pEntry['qtySold'] = (pEntry['qtySold'] as double) + baseUnits;
        pEntry['revenue'] = (pEntry['revenue'] as double) + item.subtotal;
        pEntry['hpp'] = (pEntry['hpp'] as double) + itemHpp;
        pEntry['profit'] = (pEntry['profit'] as double) + itemProfit;

        final catEntry = categoryStats.putIfAbsent(category, () => {
              'category': category,
              'qtySold': 0.0,
              'revenue': 0.0,
              'profit': 0.0,
            });
        catEntry['qtySold'] = (catEntry['qtySold'] as double) + baseUnits;
        catEntry['revenue'] = (catEntry['revenue'] as double) + item.subtotal;
        catEntry['profit'] = (catEntry['profit'] as double) + itemProfit;
      }
    }

    // Actual active (non-voided) returns & exchanges in period
    final returnRows = await db.query(
      'return_orders',
      where: "COALESCE(status, 'completed') != 'voided' AND date >= ? AND date <= ?",
      whereArgs: [startIso, endIso],
    );
    double grossReturnValue = 0.0;
    double exchangeOutValue = 0.0;
    double netReturnAdjustment = 0.0;
    double totalHppRecovered = 0.0;
    double totalExchangeHpp = 0.0;
    double totalDamagedLoss = 0.0;
    double cashReturnOut = 0.0;
    double transferReturnOut = 0.0;
    double qrisReturnOut = 0.0;
    double creditIssuedTotal = 0.0;
    double debtOffsetTotal = 0.0;
    double exchangeDiffInCash = 0.0;
    double exchangeDiffInNonCash = 0.0;

    for (final rr in returnRows) {
      final ro = await _hydrateReturnOrder(db, rr);
      grossReturnValue += ro.totalRefund;
      exchangeOutValue += ro.exchangeTotal;
      netReturnAdjustment += (ro.totalRefund - ro.exchangeTotal);

      for (final ri in ro.items) {
        final itemCostTotal = ri.costPrice * ri.conversionFactor * ri.returnQty;
        if (ri.stockTreatment == StockTreatments.restockSellable) {
          totalHppRecovered += itemCostTotal;
        } else if (ri.stockTreatment == StockTreatments.damaged) {
          totalDamagedLoss += itemCostTotal;
        }
      }
      for (final ex in ro.exchangeItems) {
        totalExchangeHpp += (ex.costPrice * ex.conversionFactor * ex.qty);
      }
      for (final st in ro.settlements) {
        if (st.direction == 'out_to_customer') {
          if (st.method == RefundMethods.tunai) cashReturnOut += st.amount;
          if (st.method == RefundMethods.transfer) transferReturnOut += st.amount;
          if (st.method == RefundMethods.qrisManual) qrisReturnOut += st.amount;
        } else if (st.direction == 'credit_issued') {
          creditIssuedTotal += st.amount;
        } else if (st.direction == 'debt_offset') {
          debtOffsetTotal += st.amount;
        } else if (st.direction == 'in_from_customer') {
          if (st.method == RefundMethods.tunai) {
            exchangeDiffInCash += st.amount;
          } else {
            exchangeDiffInNonCash += st.amount;
          }
        }
      }
    }

    // Account for quarantine releases inspected & moved in period (sellable recovers HPP; damaged records write-off loss)
    final quarantineMovRows = await db.query(
      'inventory_movements',
      where: "movement_type IN ('quarantine_release', 'damaged_in') AND reference_type = 'quarantine_release' AND created_at >= ? AND created_at <= ?",
      whereArgs: [startIso, endIso],
    );
    for (final qm in quarantineMovRows) {
      final pid = qm['product_id'] as int;
      final delta = (qm['qty_delta'] as num?)?.toDouble() ?? 0.0;
      final bucket = (qm['bucket'] ?? '').toString();
      if (delta <= 0) continue;
      final unitCost = prodById[pid]?.costPrice ?? 0.0;
      if (bucket == 'sellable') {
        totalHppRecovered += (unitCost * delta);
      } else if (bucket == 'damaged') {
        totalDamagedLoss += (unitCost * delta);
      }
    }

    final adjustedHpp = (totalHpp - totalHppRecovered + totalExchangeHpp).clamp(0.0, double.infinity);
    final totalReturn = netReturnAdjustment;
    final netSales = (grossSales - totalReturn).clamp(0.0, double.infinity);
    final grossProfit = netSales - adjustedHpp;
    final avgTrxValue = validTx.isNotEmpty ? grossSales / validTx.length : 0.0;

    final soldProductsList = productStats.values.toList();
    final topSellingProducts = List<Map<String, dynamic>>.from(soldProductsList)
      ..sort((a, b) => (b['qtySold'] as double).compareTo(a['qtySold'] as double));
    final leastSellingProducts = List<Map<String, dynamic>>.from(soldProductsList)
      ..sort((a, b) => (a['qtySold'] as double).compareTo(b['qtySold'] as double));
    final topRevenueProducts = List<Map<String, dynamic>>.from(soldProductsList)
      ..sort((a, b) => (b['revenue'] as double).compareTo(a['revenue'] as double));
    final topProfitProducts = List<Map<String, dynamic>>.from(soldProductsList)
      ..sort((a, b) => (b['profit'] as double).compareTo(a['profit'] as double));

    final unsoldProducts = prodById.values
        .where((p) => !productStats.containsKey(p.id))
        .map((p) => {
              'productId': p.id,
              'code': p.code,
              'name': p.name,
              'category': p.category,
              'stock': p.stock,
              'unit': p.baseUnit,
              'sellingPrice': p.sellingPrice,
            })
        .toList();
    final lowStockProducts = prodById.values.where((p) => p.isLowStock).toList();

    // Active customer debts summary
    final debtRows = await db.query('customer_debts');
    final activeDebts = debtRows
        .map((e) => CustomerDebtModel.fromMap(e))
        .where((d) => !d.isPaidOff)
        .toList();

    final customersByFreq = List<Map<String, dynamic>>.from(customerStats.values)
      ..sort((a, b) => (b['freq'] as int).compareTo(a['freq'] as int));
    final customersBySpent = List<Map<String, dynamic>>.from(customerStats.values)
      ..sort((a, b) => (b['totalSpent'] as double).compareTo(a['totalSpent'] as double));
    final customersByMax = List<Map<String, dynamic>>.from(customerStats.values)
      ..sort((a, b) => (b['maxTrx'] as double).compareTo(a['maxTrx'] as double));

    // Supplier purchases & debts in period + active AP
    final purchaseRows = await db.query(
      'purchases',
      where: "status != 'voided' AND date >= ? AND date <= ?",
      whereArgs: [startIso, endIso],
      orderBy: 'date DESC',
    );
    final supplierMap = <String, Map<String, dynamic>>{};
    for (final pr in purchaseRows) {
      final p = PurchaseModel.fromMap(pr);
      final sKey = p.supplierName.toLowerCase();
      final sEntry = supplierMap.putIfAbsent(sKey, () => {
            'supplierName': p.supplierName,
            'phone': p.supplierPhone,
            'purchaseCount': 0,
            'totalPurchaseValue': 0.0,
            'activeDebt': 0.0,
            'paidDebt': 0.0,
          });
      sEntry['purchaseCount'] = (sEntry['purchaseCount'] as int) + 1;
      sEntry['totalPurchaseValue'] = (sEntry['totalPurchaseValue'] as double) + p.totalAmount;
    }

    final supDebtRows = await db.query('supplier_debts', where: "status != 'dibatalkan'");
    final supDebts = supDebtRows.map((e) => SupplierDebtModel.fromMap(e)).toList();
    for (final sd in supDebts) {
      final sKey = sd.supplierName.toLowerCase();
      final sEntry = supplierMap.putIfAbsent(sKey, () => {
            'supplierName': sd.supplierName,
            'phone': sd.supplierPhone,
            'purchaseCount': 0,
            'totalPurchaseValue': 0.0,
            'activeDebt': 0.0,
            'paidDebt': 0.0,
          });
      sEntry['activeDebt'] = (sEntry['activeDebt'] as double) + sd.remainingDebt;
      sEntry['paidDebt'] = (sEntry['paidDebt'] as double) + sd.paidDebt;
    }

    final supplierPayRows = await db.query(
      'supplier_debt_payments',
      where: 'date >= ? AND date <= ?',
      whereArgs: [startIso, endIso],
      orderBy: 'date DESC',
    );
    final supplierList = supplierMap.values.toList()
      ..sort((a, b) => (b['totalPurchaseValue'] as double).compareTo(a['totalPurchaseValue'] as double));

    final sortedDailyKeys = dailyTrend.keys.toList()..sort();

    return {
      'sales': {
        'totalRevenue': grossSales,
        'netSales': netSales,
        'trxCount': validTx.length,
        'totalItemsSold': totalItemsSold,
        'avgTrxValue': avgTrxValue,
        'cashSales': cashSales,
        'transferSales': transferSales,
        'qrisSales': qrisSales,
        'kasbonSales': kasbonSales,
        'creditRedeemedSales': creditRedeemedSales,
        'totalDiscount': totalDiscount,
        'totalReturn': totalReturn,
        'grossReturnValue': grossReturnValue,
        'exchangeOutValue': exchangeOutValue,
        'netReturnAdjustment': netReturnAdjustment,
        'dailySeries': [
          for (final k in sortedDailyKeys) {'date': k, 'total': dailyTrend[k] ?? 0.0},
        ],
      },
      'profit': {
        'totalHpp': adjustedHpp,
        'grossSalesHpp': totalHpp,
        'hppRecovered': totalHppRecovered,
        'exchangeHpp': totalExchangeHpp,
        'damagedLoss': totalDamagedLoss,
        'grossSales': grossSales,
        'totalDiscount': totalDiscount,
        'totalReturn': totalReturn,
        'grossReturnValue': grossReturnValue,
        'exchangeOutValue': exchangeOutValue,
        'netSales': netSales,
        'grossProfit': grossProfit,
        'profitMargin': netSales > 0 ? (grossProfit / netSales) * 100 : 0.0,
      },
      'returns': {
        'count': returnRows.length,
        'grossReturnValue': grossReturnValue,
        'exchangeOutValue': exchangeOutValue,
        'netReturnAdjustment': netReturnAdjustment,
        'cashReturnOut': cashReturnOut,
        'transferReturnOut': transferReturnOut,
        'qrisReturnOut': qrisReturnOut,
        'creditIssuedTotal': creditIssuedTotal,
        'debtOffsetTotal': debtOffsetTotal,
        'exchangeDiffInCash': exchangeDiffInCash,
        'exchangeDiffInNonCash': exchangeDiffInNonCash,
        'hppRecovered': totalHppRecovered,
        'exchangeHpp': totalExchangeHpp,
        'damagedLoss': totalDamagedLoss,
      },
      'products': {
        'topSelling': topSellingProducts,
        'leastSelling': leastSellingProducts,
        'unsold': unsoldProducts,
        'topRevenue': topRevenueProducts,
        'topProfit': topProfitProducts,
        'lowStock': lowStockProducts,
        'categories': categoryStats.values.toList()
          ..sort((a, b) => (b['revenue'] as double).compareTo(a['revenue'] as double)),
      },
      'customers': {
        'byFreq': customersByFreq,
        'bySpent': customersBySpent,
        'byMaxTrx': customersByMax,
        'activeDebts': activeDebts,
      },
      'suppliers': {
        'summary': supplierList,
        'purchases': purchaseRows.map((e) => PurchaseModel.fromMap(e)).toList(),
        'debts': supDebts,
        'payments': supplierPayRows.map((e) => SupplierDebtPaymentModel.fromMap(e)).toList(),
      },
      'transactions': validTx,
    };
  }

  // ================= SETTINGS =================
  Future<String> getSetting(String key, {String defaultValue = ''}) async {
    final db = await database;
    final res = await db.query('store_settings', where: 'key = ?', whereArgs: [key]);
    if (res.isNotEmpty) return res.first['value'] as String;
    return defaultValue;
  }

  Future<void> setSetting(String key, String value) async {
    final db = await database;
    await db.insert(
      'store_settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    if (key != 'catalog_sync_version') {
      final ver = await bumpSyncVersionTxn(db);
      onMultiDeviceEvent?.call('settings_changed', {'sync_version': ver, 'key': key});
    }
  }

  Future<Map<String, String>> getAllSettings() async {
    final db = await database;
    final res = await db.query('store_settings');
    return {for (final item in res) item['key'] as String: item['value'] as String};
  }
}
