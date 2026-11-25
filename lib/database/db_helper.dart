import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/attendance.dart';
import '../models/audit_log.dart';
import '../models/cash_flow.dart';
import '../models/customer.dart';
import '../models/customer_debt.dart';
import '../models/printer_device.dart';
import '../models/product.dart';
import '../models/product_batch.dart';
import '../models/product_unit.dart';
import '../models/promo.dart';
import '../models/purchase.dart';
import '../models/return_order.dart';
import '../models/service_order.dart';
import '../models/shift.dart';
import '../models/stock_opname.dart';
import '../models/tiered_price.dart';
import '../models/transaction.dart';
import '../models/transaction_item.dart';
import '../models/user.dart';
import '../models/warehouse_doc.dart';
import '../utils/security_helper.dart';

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
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null && _database!.isOpen) return _database!;
    _database = await _initDB('kasirtoko.db');
    return _database!;
  }

  /// Resets the singleton database connection (essential after restore).
  Future<void> resetConnection() async {
    if (_database != null && _database!.isOpen) {
      await _database!.close();
    }
    _database = null;
  }

  Future<Database> _initDB(String filePath) async {
    final dbDir = await getApplicationDocumentsDirectory();
    final path = p.join(dbDir.path, filePath);

    // Pre-migration safety backup for existing v1 databases
    final dbFile = File(path);
    final preV2Backup = File(p.join(dbDir.path, 'kasirtoko_pre_v2_backup.db'));
    if (await dbFile.exists() && !await preV2Backup.exists()) {
      try {
        await dbFile.copy(preV2Backup.path);
      } catch (_) {}
    }

    return await openDatabase(
      path,
      version: 2,
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
    );
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
          final hashedPin = SecurityHelper.hashSecret(pinToHash, salt);
          // Default initial password matches PIN so migrated users can log in cleanly and later update password
          final hashedPw = SecurityHelper.hashSecret(pinToHash, salt);
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
        base_unit TEXT NOT NULL,
        cost_price REAL NOT NULL,
        selling_price REAL NOT NULL,
        stock REAL NOT NULL,
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
        customer_name TEXT NOT NULL,
        customer_phone TEXT,
        subtotal REAL NOT NULL,
        discount_total REAL NOT NULL,
        tax_amount REAL NOT NULL DEFAULT 0.0,
        promo_name TEXT NOT NULL DEFAULT '',
        grand_total REAL NOT NULL,
        payment_method TEXT NOT NULL,
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
        total_refund REAL NOT NULL,
        refund_method TEXT NOT NULL,
        note TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE return_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        return_order_id INTEGER NOT NULL,
        product_id INTEGER NOT NULL,
        product_name TEXT NOT NULL,
        unit_name TEXT NOT NULL,
        conversion_factor REAL NOT NULL DEFAULT 1.0,
        return_qty REAL NOT NULL,
        refund_price REAL NOT NULL,
        subtotal REAL NOT NULL,
        condition TEXT NOT NULL,
        FOREIGN KEY (return_order_id) REFERENCES return_orders (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE shifts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        cashier_id INTEGER NOT NULL,
        cashier_name TEXT NOT NULL,
        start_time TEXT NOT NULL,
        end_time TEXT,
        starting_cash REAL NOT NULL,
        total_sales_cash REAL NOT NULL DEFAULT 0.0,
        total_sales_qris REAL NOT NULL DEFAULT 0.0,
        total_sales_transfer REAL NOT NULL DEFAULT 0.0,
        total_sales_kasbon REAL NOT NULL DEFAULT 0.0,
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
        type TEXT NOT NULL,
        category TEXT NOT NULL,
        amount REAL NOT NULL,
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
        is_liveness_passed INTEGER NOT NULL DEFAULT 1
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
        details TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE customer_debts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
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
    };

    for (final entry in defaultSettings.entries) {
      await db.insert('store_settings', {'key': entry.key, 'value': entry.value});
    }

    // Seed hashed default accounts
    final defaultUsers = [
      {'name': 'Pemilik Toko', 'username': 'owner', 'pin': '123456', 'role': AppRoles.owner},
      {'name': 'Supervisor Toko', 'username': 'supervisor', 'pin': '3333', 'role': AppRoles.supervisor},
      {'name': 'Kasir 1', 'username': 'kasir', 'pin': '1111', 'role': AppRoles.cashier},
      {'name': 'Petugas Gudang', 'username': 'gudang', 'pin': '2222', 'role': AppRoles.warehouse},
      {'name': 'Teknisi Servis', 'username': 'teknisi', 'pin': '4444', 'role': AppRoles.technician},
    ];

    for (final u in defaultUsers) {
      final salt = SecurityHelper.generateSalt();
      final pin = u['pin']!;
      final hash = SecurityHelper.hashSecret(pin, salt);
      final user = UserModel(
        name: u['name']!,
        username: u['username']!,
        passwordHash: hash,
        passwordSalt: salt,
        pin: '',
        pinHash: hash,
        role: u['role']!,
        isActive: true,
      );
      await db.insert('users', user.toMap());
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
  Future<List<UserModel>> getUsers({bool includeInactive = false}) async {
    final db = await database;
    final res = includeInactive
        ? await db.query('users', orderBy: 'id ASC')
        : await db.query('users', where: 'is_active = ?', whereArgs: [1], orderBy: 'id ASC');
    return res.map((e) => UserModel.fromMap(e)).toList();
  }

  Future<UserModel?> loginWithPin(String pin) async {
    final db = await database;
    final res = await db.query('users', where: 'is_active = ?', whereArgs: [1]);
    for (final map in res) {
      final user = UserModel.fromMap(map);
      if (user.pinHash.isNotEmpty && user.passwordSalt.isNotEmpty) {
        if (SecurityHelper.verifySecret(pin, user.passwordSalt, user.pinHash)) {
          return user;
        }
      } else if (user.pin.isNotEmpty && user.pin == pin) {
        return user;
      }
    }
    return null;
  }

  Future<UserModel?> loginWithPassword(String username, String password) async {
    final db = await database;
    final cleanUser = username.trim().toLowerCase();
    final res = await db.query(
      'users',
      where: 'LOWER(username) = ? AND is_active = ?',
      whereArgs: [cleanUser, 1],
      limit: 1,
    );
    if (res.isEmpty) return null;
    final user = UserModel.fromMap(res.first);
    if (user.passwordHash.isNotEmpty && user.passwordSalt.isNotEmpty) {
      if (SecurityHelper.verifySecret(password, user.passwordSalt, user.passwordHash)) {
        return user;
      }
    }
    return null;
  }

  Future<UserModel?> login(String pin) => loginWithPin(pin);

  Future<int> insertUser(UserModel user) async {
    final db = await database;
    return await db.insert('users', user.toMap());
  }

  Future<int> updateUser(UserModel user) async {
    final db = await database;
    return await db.update(
      'users',
      user.toMap(),
      where: 'id = ?',
      whereArgs: [user.id],
    );
  }

  Future<void> setUserActive(int userId, bool isActive) async {
    final db = await database;
    await db.update(
      'users',
      {'is_active': isActive ? 1 : 0},
      where: 'id = ?',
      whereArgs: [userId],
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
    return await db.transaction((txn) async {
      final id = await txn.insert('products', product.toMap());
      await _saveProductRelations(txn, id, product);
      return id;
    });
  }

  Future<void> updateProduct(ProductModel product) async {
    final db = await database;
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
    });
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
    await db.update('products', {'is_active': 0}, where: 'id = ?', whereArgs: [id]);
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

  // ================= TRANSACTIONS & SHIFT SYNC =================
  Future<int> insertTransaction(TransactionModel trx, {int? shiftId}) async {
    final db = await database;
    return await db.transaction((txn) async {
      final trxId = await txn.insert('transactions', trx.toMap());

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
          final deductAmount = item.baseStockQty;
          await txn.rawUpdate(
            'UPDATE products SET stock = MAX(0, stock - ?) WHERE id = ?',
            [deductAmount, item.productId],
          );
        }
      }

      // Sync active shift sales totals
      if (shiftId != null) {
        if (trx.paymentMethod == 'tunai') {
          await txn.rawUpdate(
            'UPDATE shifts SET total_sales_cash = total_sales_cash + ? WHERE id = ?',
            [trx.grandTotal, shiftId],
          );
        } else if (trx.paymentMethod == 'qris') {
          await txn.rawUpdate(
            'UPDATE shifts SET total_sales_qris = total_sales_qris + ? WHERE id = ?',
            [trx.grandTotal, shiftId],
          );
        } else if (trx.paymentMethod == 'transfer') {
          await txn.rawUpdate(
            'UPDATE shifts SET total_sales_transfer = total_sales_transfer + ? WHERE id = ?',
            [trx.grandTotal, shiftId],
          );
        } else if (trx.paymentMethod == 'kasbon') {
          await txn.rawUpdate(
            'UPDATE shifts SET total_sales_kasbon = total_sales_kasbon + ? WHERE id = ?',
            [trx.grandTotal, shiftId],
          );
          if (trx.amountPaid > 0) {
            await txn.rawUpdate(
              'UPDATE shifts SET total_cash_in = total_cash_in + ? WHERE id = ?',
              [trx.amountPaid, shiftId],
            );
          }
        }
      }

      if (trx.paymentMethod == 'kasbon') {
        final dueDate = DateTime.now().add(const Duration(days: 30));
        await txn.insert('customer_debts', {
          'customer_name': trx.customerName,
          'customer_phone': trx.customerPhone,
          'invoice_number': trx.invoiceNumber,
          'total_debt': trx.grandTotal,
          'paid_debt': trx.amountPaid,
          'transaction_date': trx.date.toIso8601String(),
          'due_date': dueDate.toIso8601String(),
          'note': trx.note,
        });
      }

      return trxId;
    });
  }

  Future<void> voidTransaction(int trxId, {int? shiftId}) async {
    final db = await database;
    await db.transaction((txn) async {
      final res = await txn.query('transactions', where: 'id = ?', whereArgs: [trxId], limit: 1);
      if (res.isEmpty) return;
      final trx = TransactionModel.fromMap(res.first);
      if (trx.status == 'voided') return;

      final itemsRes = await txn.query('transaction_items', where: 'transaction_id = ?', whereArgs: [trxId]);
      for (final m in itemsRes) {
        final item = TransactionItemModel.fromMap(m);
        if (!item.isService) {
          await txn.rawUpdate(
            'UPDATE products SET stock = stock + ? WHERE id = ?',
            [item.baseStockQty, item.productId],
          );
        }
      }

      await txn.update('transactions', {'status': 'voided'}, where: 'id = ?', whereArgs: [trxId]);

      if (shiftId != null && trx.paymentMethod == 'tunai') {
        await txn.rawUpdate(
          'UPDATE shifts SET total_sales_cash = MAX(0, total_sales_cash - ?) WHERE id = ?',
          [trx.grandTotal, shiftId],
        );
      }
    });
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

  // ================= RETURNS (RETUR BARANG) =================
  Future<Map<String, double>> getReturnedQuantitiesForTransaction(int trxId) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT ri.product_id, ri.unit_name, SUM(ri.return_qty) as returned_qty
      FROM return_items ri
      JOIN return_orders ro ON ri.return_order_id = ro.id
      WHERE ro.transaction_id = ?
      GROUP BY ri.product_id, ri.unit_name
    ''', [trxId]);

    final map = <String, double>{};
    for (final r in rows) {
      final key = '${r['product_id']}_${r['unit_name']}';
      map[key] = (r['returned_qty'] as num?)?.toDouble() ?? 0.0;
    }
    return map;
  }

  Future<int> insertReturnOrder(ReturnOrderModel ret, {int? shiftId}) async {
    final db = await database;
    return await db.transaction((txn) async {
      final retId = await txn.insert('return_orders', ret.toMap());

      for (final item in ret.items) {
        await txn.insert('return_items', {
          'return_order_id': retId,
          'product_id': item.productId,
          'product_name': item.productName,
          'unit_name': item.unitName,
          'conversion_factor': item.conversionFactor,
          'return_qty': item.returnQty,
          'refund_price': item.refundPrice,
          'subtotal': item.subtotal,
          'condition': item.condition,
        });

        if (item.condition == 'baik') {
          await txn.rawUpdate(
            'UPDATE products SET stock = stock + ? WHERE id = ?',
            [item.baseStockQty, item.productId],
          );
        }
      }

      // Compute whether this completes a full return or partial return
      final origItems = await txn.query(
        'transaction_items',
        where: 'transaction_id = ?',
        whereArgs: [ret.transactionId],
      );
      final allRetItems = await txn.rawQuery('''
        SELECT ri.product_id, ri.unit_name, SUM(ri.return_qty) as total_ret
        FROM return_items ri
        JOIN return_orders ro ON ri.return_order_id = ro.id
        WHERE ro.transaction_id = ?
        GROUP BY ri.product_id, ri.unit_name
      ''', [ret.transactionId]);

      final retMap = <String, double>{};
      for (final r in allRetItems) {
        retMap['${r['product_id']}_${r['unit_name']}'] =
            (r['total_ret'] as num?)?.toDouble() ?? 0.0;
      }

      bool allReturned = origItems.isNotEmpty;
      for (final oi in origItems) {
        final key = '${oi['product_id']}_${oi['unit_name']}';
        final purchased = (oi['qty'] as num).toDouble();
        final returned = retMap[key] ?? 0.0;
        if (returned + 0.0001 < purchased) {
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

      // Sync refund method
      if (ret.refundMethod == 'tunai') {
        await txn.insert('cash_flows', {
          'shift_id': shiftId,
          'type': 'out',
          'category': 'Retur Penjualan',
          'amount': ret.totalRefund,
          'note': 'Retur Nota #${ret.invoiceNumber}',
          'date': DateTime.now().toIso8601String(),
          'cashier_name': ret.cashierName,
        });
        if (shiftId != null) {
          await txn.rawUpdate(
            'UPDATE shifts SET total_return_cash = total_return_cash + ? WHERE id = ?',
            [ret.totalRefund, shiftId],
          );
        }
      } else if (ret.refundMethod == 'potong_piutang') {
        final debts = await txn.query(
          'customer_debts',
          where: 'invoice_number = ?',
          whereArgs: [ret.invoiceNumber],
          limit: 1,
        );
        if (debts.isNotEmpty) {
          final d = CustomerDebtModel.fromMap(debts.first);
          final newPaid = (d.paidDebt + ret.totalRefund).clamp(0.0, d.totalDebt);
          await txn.update(
            'customer_debts',
            {
              'paid_debt': newPaid,
              'last_payment_date': DateTime.now().toIso8601String(),
              'note': '${d.note} [Dipotong Retur #${ret.returnNumber}]'.trim(),
            },
            where: 'id = ?',
            whereArgs: [d.id],
          );
        }
      }

      return retId;
    });
  }

  // ================= SHIFTS & CASH FLOW =================
  Future<ShiftModel?> getCurrentOpenShift() async {
    final db = await database;
    final res = await db.query(
      'shifts',
      where: "status = 'open'",
      orderBy: 'id DESC',
      limit: 1,
    );
    if (res.isNotEmpty) return ShiftModel.fromMap(res.first);
    return null;
  }

  Future<int> openShift(ShiftModel shift) async {
    final db = await database;
    return await db.insert('shifts', shift.toMap());
  }

  Future<void> closeShift(int shiftId, double actualCash, double difference, String note) async {
    final db = await database;
    await db.update(
      'shifts',
      {
        'end_time': DateTime.now().toIso8601String(),
        'actual_cash': actualCash,
        'difference': difference,
        'status': 'closed',
        'note': note,
      },
      where: 'id = ?',
      whereArgs: [shiftId],
    );
  }

  Future<Map<String, dynamic>> getShiftStats(ShiftModel shift) async {
    final db = await database;
    final startIso = shift.startTime.toIso8601String();
    final endIso = (shift.endTime ?? DateTime.now()).toIso8601String();

    final txRows = await db.query(
      'transactions',
      where: "status != 'voided' AND date >= ? AND date <= ?",
      whereArgs: [startIso, endIso],
    );

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
      final id = await txn.insert('cash_flows', flow.toMap());
      if (flow.shiftId != null) {
        if (flow.isIn) {
          await txn.rawUpdate(
            'UPDATE shifts SET total_cash_in = total_cash_in + ? WHERE id = ?',
            [flow.amount, flow.shiftId],
          );
        } else {
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

  // ================= ATTENDANCE & AUDIT LOGS =================
  Future<int> insertAttendance(AttendanceModel att) async {
    final db = await database;
    return await db.insert('attendances', att.toMap());
  }

  Future<List<AttendanceModel>> getRecentAttendances({int limit = 100}) async {
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

  // ================= CUSTOMER DEBTS (KASBON) =================
  Future<List<CustomerDebtModel>> getCustomerDebts() async {
    final db = await database;
    final res = await db.query('customer_debts', orderBy: 'due_date ASC');
    return res.map((e) => CustomerDebtModel.fromMap(e)).toList();
  }

  Future<void> payCustomerDebt(
    int debtId,
    double amountPaid, {
    int? shiftId,
    String cashierName = 'Kasir',
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      final debtRes = await txn.query('customer_debts', where: 'id = ?', whereArgs: [debtId]);
      if (debtRes.isEmpty) return;

      final debt = CustomerDebtModel.fromMap(debtRes.first);
      final actualPayment = amountPaid > debt.remainingDebt ? debt.remainingDebt : amountPaid;
      final newPaid = debt.paidDebt + actualPayment;

      await txn.update(
        'customer_debts',
        {
          'paid_debt': newPaid,
          'last_payment_date': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [debtId],
      );

      await txn.insert('cash_flows', {
        'shift_id': shiftId,
        'type': 'in',
        'category': 'Pelunasan Kasbon',
        'amount': actualPayment,
        'note': 'Pelunasan dari ${debt.customerName} (#${debt.invoiceNumber})',
        'date': DateTime.now().toIso8601String(),
        'cashier_name': cashierName,
      });

      if (shiftId != null) {
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
    return await db.insert('customers', customer.toMap());
  }

  Future<void> updateCustomer(CustomerModel customer) async {
    final db = await database;
    await db.update('customers', customer.toMap(), where: 'id = ?', whereArgs: [customer.id]);
  }

  Future<void> deleteCustomer(int id) async {
    final db = await database;
    await db.delete('customers', where: 'id = ?', whereArgs: [id]);
  }

  // ================= PURCHASES (RESTOCK / PEMBELIAN) =================
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
    return await db.transaction((txn) async {
      final pid = await txn.insert('purchases', purchase.toMap());
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

        await txn.rawUpdate(
          'UPDATE products SET stock = stock + ? WHERE id = ?',
          [item.baseStockQty, item.productId],
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

      if (purchase.paymentMethod == 'kas_laci') {
        await txn.insert('cash_flows', {
          'shift_id': shiftId,
          'type': 'out',
          'category': 'Pembelian Stok',
          'amount': purchase.totalAmount,
          'note': 'Pembelian #${purchase.purchaseNumber} (${purchase.supplierName})',
          'date': purchase.date.toIso8601String(),
          'cashier_name': purchase.createdBy,
        });
        if (shiftId != null) {
          await txn.rawUpdate(
            'UPDATE shifts SET total_cash_out = total_cash_out + ? WHERE id = ?',
            [purchase.totalAmount, shiftId],
          );
        }
      }
      return pid;
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
    final db = await database;
    return await db.transaction((txn) async {
      final id = await txn.insert('stock_opnames', opname.toMap());
      await txn.update(
        'products',
        {'stock': opname.physicalStock},
        where: 'id = ?',
        whereArgs: [opname.productId],
      );
      return id;
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
    return await db.insert('promos', promo.toMap());
  }

  Future<void> togglePromoActive(int id, bool isActive) async {
    final db = await database;
    await db.update('promos', {'is_active': isActive ? 1 : 0}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deletePromo(int id) async {
    final db = await database;
    await db.delete('promos', where: 'id = ?', whereArgs: [id]);
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
      return await txn.insert('printers', printer.toMap());
    });
  }

  Future<void> updatePrinter(PrinterDeviceModel printer) async {
    final db = await database;
    await db.transaction((txn) async {
      if (printer.isDefault) {
        await txn.update('printers', {'is_default': 0});
      }
      await txn.update('printers', printer.toMap(), where: 'id = ?', whereArgs: [printer.id]);
    });
  }

  Future<void> setDefaultPrinter(int printerId) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.update('printers', {'is_default': 0});
      await txn.update('printers', {'is_default': 1}, where: 'id = ?', whereArgs: [printerId]);
    });
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
  }

  Future<Map<String, String>> getAllSettings() async {
    final db = await database;
    final res = await db.query('store_settings');
    return {for (final item in res) item['key'] as String: item['value'] as String};
  }
}
