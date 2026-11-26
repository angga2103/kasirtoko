import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:kasirtoko/database/db_helper.dart';
import 'package:kasirtoko/models/user.dart';
import 'package:kasirtoko/utils/date_format.dart';
import 'package:kasirtoko/utils/security_helper.dart';

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await DateHelper.ensureInitialized();
  });

  tearDown(() async {
    SecurityHelper.resetTestConfiguration();
    await DatabaseHelper.instance.closeTestDatabase();
  });

  group('Phase 1 — Database Schema v5 & Non-Destructive Migration (v4 -> v5)', () {
    test('backs up & verifies v4 DB, preserves all legacy data, enables WAL/FK/busy_timeout, and creates v5 tables & indexes', () async {
      final dbDir = await databaseFactoryFfi.getDatabasesPath();
      final dbPath = p.join(dbDir, 'legacy_v4_to_v5_test.db');
      final backupPath = p.join(dbDir, 'legacy_v4_to_v5_test_pre_v5_backup.db');
      for (final path in [dbPath, backupPath, '$dbPath-wal', '$dbPath-shm']) {
        final f = File(path);
        if (await f.exists()) await f.delete();
      }

      SecurityHelper.configureForTesting(
        pepperProvider: InMemoryPepperProvider(Uint8List.fromList(List.filled(32, 5))),
        iterations: 50000,
      );

      // 1. Build a genuine v4 schema database containing heterogeneous legacy records
      final v4 = await openDatabase(
        dbPath,
        version: 4,
        onCreate: (db, _) async {
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
              barcode TEXT
            )
          ''');
          await db.execute('''
            CREATE TABLE tiered_prices (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              product_id INTEGER NOT NULL,
              min_qty REAL NOT NULL,
              price REAL NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE product_batches (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              product_id INTEGER NOT NULL,
              batch_number TEXT NOT NULL,
              expiry_date TEXT NOT NULL,
              stock_qty REAL NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE transactions (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              invoice_number TEXT NOT NULL UNIQUE,
              date TEXT NOT NULL,
              cashier_id INTEGER NOT NULL,
              cashier_name TEXT NOT NULL,
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
              is_service INTEGER NOT NULL DEFAULT 0
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
              stock_treatment TEXT NOT NULL DEFAULT 'restock_sellable'
            )
          ''');
          await db.execute('''
            CREATE TABLE return_exchange_items (
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
              subtotal REAL NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE return_settlements (
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
            CREATE TABLE printers (
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
          await db.execute('CREATE TABLE store_settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)');

          final s = SecurityHelper.generateSalt();
          final h = SecurityHelper.hashLegacyV1Secret('1234', s);
          await db.insert('users', {
            'name': 'Kasir V4',
            'username': 'kasir_v4',
            'password_hash': h,
            'password_salt': s,
            'pin': '',
            'pin_hash': h,
            'role': AppRoles.cashier,
            'is_active': 1,
          });
          await db.insert('printers', {
            'name': 'Printer Toko',
            'is_default': 1,
          });
          await db.insert('products', {
            'code': 'LEG-01',
            'name': 'Produk Lama V4',
            'category': 'Umum',
            'base_unit': 'Pcs',
            'cost_price': 10000.0,
            'selling_price': 15000.0,
            'stock': 20.0,
            'min_stock_alert': 2.0,
          });
          final closedShiftId = await db.insert('shifts', {
            'cashier_id': 1,
            'cashier_name': 'Kasir V4',
            'start_time': '2026-11-20T08:00:00.000',
            'end_time': '2026-11-20T17:00:00.000',
            'starting_cash': 100000.0,
            'total_sales_cash': 15000.0,
            'actual_cash': 115000.0,
            'difference': 0.0,
            'status': 'closed',
          });
          // Include BOTH normal legacy tx AND null-shift orphan tx with deleted customer_id
          await db.insert('transactions', {
            'invoice_number': 'INV-LEG-1',
            'date': '2026-11-20T10:00:00.000',
            'cashier_id': 1,
            'cashier_name': 'Kasir V4',
            'customer_id': 999, // Deleted customer reference must never break v5 FK PRAGMA
            'shift_id': closedShiftId,
            'customer_name': 'Pelanggan Lama Terhapus',
            'subtotal': 15000.0,
            'discount_total': 0.0,
            'grand_total': 15000.0,
            'payment_method': 'tunai',
            'amount_paid': 15000.0,
            'change_amount': 0.0,
            'status': 'completed',
            'qr_code_payload': 'TRX|INV-LEG-1|15000',
          });
          await db.insert('transactions', {
            'invoice_number': 'INV-ORPHAN-1',
            'date': '2026-11-20T11:00:00.000',
            'cashier_id': 1,
            'cashier_name': 'Kasir V4',
            'shift_id': null,
            'customer_name': 'Pelanggan Umum',
            'subtotal': 20000.0,
            'discount_total': 0.0,
            'grand_total': 20000.0,
            'payment_method': 'tunai',
            'amount_paid': 20000.0,
            'change_amount': 0.0,
            'status': 'completed',
            'qr_code_payload': 'TRX|INV-ORPHAN-1|20000',
          });
          final roId = await db.insert('return_orders', {
            'return_number': 'RET-LEG-1',
            'transaction_id': 1,
            'invoice_number': 'INV-LEG-1',
            'date': '2026-11-20T12:00:00.000',
            'cashier_id': 1,
            'cashier_name': 'Kasir V4',
            'total_refund': 5000.0,
            'refund_method': 'tunai',
          });
          await db.insert('return_settlements', {
            'return_order_id': roId,
            'settlement_type': 'refund_tunai',
            'direction': 'out_to_customer',
            'method': 'tunai',
            'amount': 5000.0,
            'shift_id': closedShiftId,
            'created_at': '2026-11-20T12:00:00.000',
          });
          await db.insert('store_settings', {'key': 'store_name', 'value': 'TOKO LEGACY V4'});
        },
      );
      await v4.close();

      // 2. Run real DatabaseHelper v4 -> v5 migration
      final migrated = await DatabaseHelper.instance.openTestDatabase(
        path: dbPath,
        deleteIfExists: false,
      );

      // 3. Verify pre-v5 backup exists and is intact at user_version 4
      expect(await File(backupPath).exists(), isTrue);
      final checkBackup = await openReadOnlyDatabase(backupPath, singleInstance: false);
      try {
        final integ = await checkBackup.rawQuery('PRAGMA integrity_check');
        expect(integ.first.values.first.toString().toLowerCase(), 'ok');
        final ver = await checkBackup.rawQuery('PRAGMA user_version');
        expect((ver.first.values.first as num).toInt(), 4);
      } finally {
        await checkBackup.close();
      }

      // 4. Verify SQLite PRAGMAs on upgraded database (v4 -> current dbVersion)
      final verRows = await migrated.rawQuery('PRAGMA user_version');
      expect((verRows.first.values.first as num).toInt(), DatabaseHelper.dbVersion);
      final fkRows = await migrated.rawQuery('PRAGMA foreign_keys');
      expect((fkRows.first.values.first as num).toInt(), 1);
      final jmRows = await migrated.rawQuery('PRAGMA journal_mode');
      expect(jmRows.first.values.first.toString().toLowerCase(), 'wal');
      final btRows = await migrated.rawQuery('PRAGMA busy_timeout');
      expect((btRows.first.values.first as num).toInt(), greaterThanOrEqualTo(5000));

      // 5. Verify legacy data preserved + backfilled
      expect(await DatabaseHelper.instance.getSetting('store_name'), 'TOKO LEGACY V4');
      expect(await DatabaseHelper.instance.getDrawerMode(), 'SHARED_DRAWER');
      final prods = await DatabaseHelper.instance.getProducts();
      expect(prods.any((pr) => pr.code == 'LEG-01' && pr.stock == 20.0), isTrue);

      final txs = await migrated.query('transactions', orderBy: 'id ASC');
      expect(txs.length, 2);
      expect(txs[0]['terminal_id'], 'ADMIN');
      expect(txs[0]['cash_register_id'], 1);
      expect(txs[1]['shift_id'], isNull);

      final rsRows = await migrated.query('return_settlements', limit: 1);
      expect(rsRows.first['settlement_shift_id'], 1);
      expect(rsRows.first['settlement_cash_register_id'], 1);

      // Legacy user can still login cleanly and transparently upgrades to KDF v2
      final authRes = await DatabaseHelper.instance.authenticateWithPin('1234');
      expect(authRes.isSuccess, isTrue);
      expect(SecurityHelper.isV2PhcHash(authRes.user!.pinHash), isTrue);

      // 6. Verify all new v5 tables exist and REG-MAIN is seeded
      for (final tbl in [
        'cash_registers',
        'cash_register_assignments',
        'paired_terminals',
        'terminal_sessions',
        'print_jobs',
        'transaction_voids',
      ]) {
        final exists = await migrated.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
          [tbl],
        );
        expect(exists, isNotEmpty, reason: 'Table $tbl must exist in v5');
      }
      final regs = await DatabaseHelper.instance.getCashRegisters();
      expect(regs.any((r) => r.id == 1 && r.registerCode == 'REG-MAIN'), isTrue);

      // Partial unique index on idempotency_key allows multiple NULL/empty, blocks duplicate non-empty
      await expectLater(
        () => migrated.insert('transactions', {
          'invoice_number': 'INV-DUP-TEST-2',
          'date': '2026-11-26T10:00:00.000',
          'cashier_id': 1,
          'cashier_name': 'Kasir',
          'idempotency_key': 'KEY-UNIQUE-1',
          'customer_name': 'Umum',
          'subtotal': 1000.0,
          'discount_total': 0.0,
          'grand_total': 1000.0,
          'payment_method': 'tunai',
          'amount_paid': 1000.0,
          'change_amount': 0.0,
          'status': 'completed',
          'qr_code_payload': 'Q1',
        }),
        returnsNormally,
      );
      await expectLater(
        () => migrated.insert('transactions', {
          'invoice_number': 'INV-DUP-TEST-3',
          'date': '2026-11-26T10:01:00.000',
          'cashier_id': 1,
          'cashier_name': 'Kasir',
          'idempotency_key': 'KEY-UNIQUE-1',
          'customer_name': 'Umum',
          'subtotal': 1000.0,
          'discount_total': 0.0,
          'grand_total': 1000.0,
          'payment_method': 'tunai',
          'amount_paid': 1000.0,
          'change_amount': 0.0,
          'status': 'completed',
          'qr_code_payload': 'Q2',
        }),
        throwsException,
      );
    });

    test('safely normalizes corrupted pre-v5 duplicate open shifts during upgrade instead of crashing index creation', () async {
      final dbDir = await databaseFactoryFfi.getDatabasesPath();
      final dbPath = p.join(dbDir, 'legacy_corrupt_open_shifts.db');
      for (final path in [dbPath, '$dbPath-wal', '$dbPath-shm', p.join(dbDir, 'legacy_corrupt_open_shifts_pre_v5_backup.db')]) {
        final f = File(path);
        if (await f.exists()) await f.delete();
      }

      final v4 = await openDatabase(
        dbPath,
        version: 4,
        onCreate: (db, _) async {
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
          await db.execute(
            'CREATE TABLE transactions (id INTEGER PRIMARY KEY AUTOINCREMENT, invoice_number TEXT NOT NULL UNIQUE, date TEXT NOT NULL, cashier_id INTEGER NOT NULL, cashier_name TEXT NOT NULL, customer_id INTEGER, shift_id INTEGER, customer_name TEXT NOT NULL, customer_phone TEXT, subtotal REAL NOT NULL, discount_total REAL NOT NULL, tax_amount REAL NOT NULL DEFAULT 0.0, promo_name TEXT NOT NULL DEFAULT "", grand_total REAL NOT NULL, payment_method TEXT NOT NULL, credit_used REAL NOT NULL DEFAULT 0.0, amount_paid REAL NOT NULL, change_amount REAL NOT NULL, status TEXT NOT NULL, qr_code_payload TEXT NOT NULL, note TEXT, printer_snapshot_json TEXT NOT NULL DEFAULT "")',
          );
          await db.execute(
            'CREATE TABLE shifts (id INTEGER PRIMARY KEY AUTOINCREMENT, cashier_id INTEGER NOT NULL, cashier_name TEXT NOT NULL, start_time TEXT NOT NULL, end_time TEXT, starting_cash REAL NOT NULL, total_sales_cash REAL NOT NULL DEFAULT 0.0, total_sales_qris REAL NOT NULL DEFAULT 0.0, total_sales_transfer REAL NOT NULL DEFAULT 0.0, total_sales_kasbon REAL NOT NULL DEFAULT 0.0, total_sales_credit REAL NOT NULL DEFAULT 0.0, total_cash_in REAL NOT NULL DEFAULT 0.0, total_cash_out REAL NOT NULL DEFAULT 0.0, total_return_cash REAL NOT NULL DEFAULT 0.0, actual_cash REAL, difference REAL, status TEXT NOT NULL DEFAULT "open", note TEXT)',
          );
          await db.execute(
            'CREATE TABLE cash_flows (id INTEGER PRIMARY KEY AUTOINCREMENT, shift_id INTEGER, type TEXT NOT NULL, category TEXT NOT NULL, amount REAL NOT NULL, payment_method TEXT NOT NULL DEFAULT "tunai", account_name TEXT NOT NULL DEFAULT "Laci Kasir", source_type TEXT NOT NULL DEFAULT "manual", source_id TEXT NOT NULL DEFAULT "", is_internal_transfer INTEGER NOT NULL DEFAULT 0, note TEXT, date TEXT NOT NULL, cashier_name TEXT NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE return_settlements (id INTEGER PRIMARY KEY AUTOINCREMENT, return_order_id INTEGER NOT NULL, settlement_type TEXT NOT NULL, direction TEXT NOT NULL, method TEXT NOT NULL, amount REAL NOT NULL, account_name TEXT NOT NULL DEFAULT "", reference_number TEXT NOT NULL DEFAULT "", shift_id INTEGER, customer_id INTEGER, cash_flow_id INTEGER, note TEXT NOT NULL DEFAULT "", created_at TEXT NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE printers (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, is_default INTEGER NOT NULL DEFAULT 0)',
          );
          await db.execute(
            'CREATE TABLE audit_logs (id INTEGER PRIMARY KEY AUTOINCREMENT, timestamp TEXT NOT NULL, user_id INTEGER NOT NULL, user_name TEXT NOT NULL, user_role TEXT NOT NULL, action_type TEXT NOT NULL, module TEXT NOT NULL DEFAULT "", object_id TEXT NOT NULL DEFAULT "", before_value TEXT NOT NULL DEFAULT "", after_value TEXT NOT NULL DEFAULT "", details TEXT NOT NULL)',
          );
          await db.execute('CREATE TABLE store_settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)');

          await db.insert('shifts', {
            'cashier_id': 1,
            'cashier_name': 'Shift Lama 1',
            'start_time': '2026-11-18T08:00:00.000',
            'starting_cash': 50000.0,
            'status': 'open',
          });
          await db.insert('shifts', {
            'cashier_id': 2,
            'cashier_name': 'Shift Terbaru 2',
            'start_time': '2026-11-20T08:00:00.000',
            'starting_cash': 100000.0,
            'status': 'open',
          });
        },
      );
      await v4.close();

      await DatabaseHelper.instance.openTestDatabase(path: dbPath, deleteIfExists: false);
      final openShifts = await DatabaseHelper.instance.getOpenShifts();
      expect(openShifts.length, 1);
      expect(openShifts.first.cashierName, 'Shift Terbaru 2');
    });

    test('corrupted/interrupted migration restores intact pre-v5 backup cleanly', () async {
      final dbDir = await databaseFactoryFfi.getDatabasesPath();
      final dbPath = p.join(dbDir, 'broken_migration_recovery.db');
      final backupPath = p.join(dbDir, 'broken_migration_recovery_pre_v5_backup.db');
      for (final path in [dbPath, backupPath, '$dbPath-wal', '$dbPath-shm']) {
        final f = File(path);
        if (await f.exists()) await f.delete();
      }

      // Create incomplete v4 DB missing required tables so v5 upgrade throws mid-upgrade
      final broken = await openDatabase(
        dbPath,
        version: 4,
        onCreate: (db, _) async {
          await db.execute('CREATE TABLE custom_important_data (id INTEGER PRIMARY KEY, label TEXT)');
          await db.insert('custom_important_data', {'label': 'JANGAN HILANG'});
        },
      );
      await broken.close();

      await expectLater(
        () => DatabaseHelper.instance.openTestDatabase(path: dbPath, deleteIfExists: false),
        throwsStateError,
      );

      // Verify pre-v5 backup was verified AND live file was restored intact from backup!
      expect(await File(backupPath).exists(), isTrue);
      final restoredDb = await openReadOnlyDatabase(dbPath, singleInstance: false);
      try {
        final rows = await restoredDb.query('custom_important_data');
        expect(rows.single['label'], 'JANGAN HILANG');
        final ver = await restoredDb.rawQuery('PRAGMA user_version');
        expect((ver.first.values.first as num).toInt(), 4);
      } finally {
        await restoredDb.close();
      }
    });
  });
}
