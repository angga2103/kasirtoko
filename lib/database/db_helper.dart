import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/user.dart';
import '../models/product.dart';
import '../models/product_unit.dart';
import '../models/tiered_price.dart';
import '../models/product_batch.dart';
import '../models/transaction.dart';
import '../models/transaction_item.dart';
import '../models/return_order.dart';
import '../models/return_item.dart';
import '../models/shift.dart';
import '../models/cash_flow.dart';
import '../models/attendance.dart';
import '../models/audit_log.dart';
import '../models/customer_debt.dart';
import '../models/warehouse_doc.dart';
import '../models/stock_opname.dart';
import '../models/promo.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('kasirtoko.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getApplicationDocumentsDirectory();
    final path = p.join(dbPath.path, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    // 1. Users table
    await db.execute('''
      CREATE TABLE users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        pin TEXT NOT NULL,
        role TEXT NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1
      )
    ''');

    // 2. Products table
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
        is_active INTEGER NOT NULL DEFAULT 1
      )
    ''');

    // 3. Product Units table
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

    // 4. Tiered Prices table
    await db.execute('''
      CREATE TABLE tiered_prices (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        product_id INTEGER NOT NULL,
        min_qty REAL NOT NULL,
        price REAL NOT NULL,
        FOREIGN KEY (product_id) REFERENCES products (id) ON DELETE CASCADE
      )
    ''');

    // 5. Product Batches table
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

    // 6. Transactions table
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
        grand_total REAL NOT NULL,
        payment_method TEXT NOT NULL,
        amount_paid REAL NOT NULL,
        change_amount REAL NOT NULL,
        status TEXT NOT NULL,
        qr_code_payload TEXT NOT NULL,
        note TEXT
      )
    ''');

    // 7. Transaction Items table
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

    // 8. Return Orders table
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

    // 9. Return Items table
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

    // 10. Shifts table
    await db.execute('''
      CREATE TABLE shifts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        cashier_id INTEGER NOT NULL,
        cashier_name TEXT NOT NULL,
        start_time TEXT NOT NULL,
        end_time TEXT,
        starting_cash REAL NOT NULL,
        total_sales_cash REAL NOT NULL DEFAULT 0.0,
        total_cash_in REAL NOT NULL DEFAULT 0.0,
        total_cash_out REAL NOT NULL DEFAULT 0.0,
        total_return_cash REAL NOT NULL DEFAULT 0.0,
        actual_cash REAL,
        difference REAL,
        status TEXT NOT NULL DEFAULT 'open',
        note TEXT
      )
    ''');

    // 11. Cash Flows table
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

    // 12. Attendances table
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

    // 13. Audit Logs table
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

    // 14. Customer Debts table
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

    // 15. Warehouse Docs table
    await db.execute('''
      CREATE TABLE warehouse_docs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        doc_number TEXT NOT NULL UNIQUE,
        doc_type TEXT NOT NULL,
        date TEXT NOT NULL,
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

    // 16. Stock Opnames table
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

    // 17. Promos table
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

    // 18. Store Settings table
    await db.execute('''
      CREATE TABLE store_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    // Seed default settings and users
    await _seedInitialData(db);
  }

  Future<void> _seedInitialData(Database db) async {
    // Default Settings
    final defaultSettings = {
      'store_name': 'TOKO BERKAH JAYA',
      'store_address': 'Jl. Ahmad Yani No. 88, Kota',
      'store_phone': '081234567890',
      'owner_phone': '081234567890',
      'receipt_footer': 'Terima kasih atas kunjungan Anda!\nBarang yang sudah dibeli dapat ditukar maksimal 2 hari.',
      'printer_paper_size': '58mm',
      'shift_start_hour': '08:00',
    };

    for (final entry in defaultSettings.entries) {
      await db.insert('store_settings', {'key': entry.key, 'value': entry.value});
    }

    // Default Users (Owner, Supervisor, Kasir, Gudang)
    final defaultUsers = [
      {'name': 'Pemilik Toko', 'pin': '123456', 'role': 'owner'},
      {'name': 'Supervisor Toko', 'pin': '3333', 'role': 'supervisor'},
      {'name': 'Kasir 1', 'pin': '1111', 'role': 'cashier'},
      {'name': 'Petugas Gudang', 'pin': '2222', 'role': 'warehouse'},
    ];

    for (final u in defaultUsers) {
      await db.insert('users', {
        'name': u['name'],
        'pin': u['pin'],
        'role': u['role'],
        'is_active': 1,
      });
    }

    // Seed initial products with multi-satuan, tiered prices, & batch expiry
    final now = DateTime.now();

    // 1. Minyak Goreng 2L
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
    // Multi satuan: 1 Dus = 6 Pcs
    await db.insert('product_units', {
      'product_id': p1Id,
      'unit_name': 'Dus',
      'conversion_factor': 6.0,
      'selling_price': 200000.0, // lebih murah daripada 34.500 x 6 = 207.000
      'barcode': '8992345001-DUS',
    });
    // Harga bertingkat: beli >= 3 Pcs @ 33.500
    await db.insert('tiered_prices', {
      'product_id': p1Id,
      'min_qty': 3.0,
      'price': 33500.0,
    });
    // Batch expired
    await db.insert('product_batches', {
      'product_id': p1Id,
      'batch_number': 'BATCH-MG26',
      'expiry_date': now.add(const Duration(days: 180)).toIso8601String(),
      'stock_qty': 48.0,
    });

    // 2. Beras Premium 5Kg
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
    // Tiered price
    await db.insert('tiered_prices', {
      'product_id': p2Id,
      'min_qty': 5.0,
      'price': 70000.0,
    });

    // 3. Susu UHT Cokelat 1L (Contoh barang mendekati kadaluarsa untuk demo H-15)
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
      'expiry_date': now.add(const Duration(days: 15)).toIso8601String(), // Peringatan H-15!
      'stock_qty': 30.0,
    });

    // 4. Jasa Servis Ringan / Pengiriman (Produk Jasa tanpa potong stok)
    await db.insert('products', {
      'code': 'SRV-001',
      'name': 'Jasa Antar Barang ke Rumah',
      'category': 'Jasa',
      'barcode': 'SRV001',
      'is_service': 1,
      'base_unit': 'Trip',
      'cost_price': 5000.0,
      'selling_price': 10000.0,
      'stock': 999.0,
      'min_stock_alert': 0.0,
      'is_active': 1,
    });
  }

  // ================= USERS CRUD =================
  Future<List<UserModel>> getUsers() async {
    final db = await database;
    final res = await db.query('users', where: 'is_active = ?', whereArgs: [1]);
    return res.map((e) => UserModel.fromMap(e)).toList();
  }

  Future<UserModel?> login(String pin) async {
    final db = await database;
    final res = await db.query(
      'users',
      where: 'pin = ? AND is_active = ?',
      whereArgs: [pin, 1],
      limit: 1,
    );
    if (res.isNotEmpty) return UserModel.fromMap(res.first);
    return null;
  }

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

  // ================= PRODUCTS CRUD =================
  Future<List<ProductModel>> getProducts({String? query, String? category}) async {
    final db = await database;
    String whereClause = 'is_active = 1';
    List<dynamic> whereArgs = [];

    if (category != null && category.isNotEmpty && category != 'Semua') {
      whereClause += ' AND category = ?';
      whereArgs.add(category);
    }

    if (query != null && query.isNotEmpty) {
      whereClause += ' AND (name LIKE ? OR code LIKE ? OR barcode LIKE ?)';
      whereArgs.addAll(['%$query%', '%$query%', '%$query%']);
    }

    final res = await db.query('products', where: whereClause, whereArgs: whereArgs);
    List<ProductModel> products = [];

    for (final map in res) {
      final p = ProductModel.fromMap(map);
      p.units = await getProductUnits(p.id!);
      p.tieredPrices = await getTieredPrices(p.id!);
      p.batches = await getProductBatches(p.id!);
      products.add(p);
    }
    return products;
  }

  Future<ProductModel?> getProductByBarcode(String barcode) async {
    final db = await database;
    // Check main product barcode
    final res = await db.query(
      'products',
      where: '(barcode = ? OR code = ?) AND is_active = 1',
      whereArgs: [barcode, barcode],
      limit: 1,
    );
    if (res.isNotEmpty) {
      final p = ProductModel.fromMap(res.first);
      p.units = await getProductUnits(p.id!);
      p.tieredPrices = await getTieredPrices(p.id!);
      p.batches = await getProductBatches(p.id!);
      return p;
    }

    // Check unit barcode
    final unitRes = await db.query(
      'product_units',
      where: 'barcode = ?',
      whereArgs: [barcode],
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
        final p = ProductModel.fromMap(prodRes.first);
        p.units = await getProductUnits(p.id!);
        p.tieredPrices = await getTieredPrices(p.id!);
        p.batches = await getProductBatches(p.id!);
        return p;
      }
    }
    return null;
  }

  Future<int> insertProduct(ProductModel product) async {
    final db = await database;
    return await db.transaction((txn) async {
      final id = await txn.insert('products', product.toMap());

      for (final unit in product.units) {
        await txn.insert('product_units', {
          'product_id': id,
          'unit_name': unit.unitName,
          'conversion_factor': unit.conversionFactor,
          'selling_price': unit.sellingPrice,
          'barcode': unit.barcode,
        });
      }

      for (final tp in product.tieredPrices) {
        await txn.insert('tiered_prices', {
          'product_id': id,
          'min_qty': tp.minQty,
          'price': tp.price,
        });
      }

      for (final batch in product.batches) {
        await txn.insert('product_batches', {
          'product_id': id,
          'batch_number': batch.batchNumber,
          'expiry_date': batch.expiryDate.toIso8601String(),
          'stock_qty': batch.stockQty,
        });
      }

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

      // Re-insert units
      await txn.delete('product_units', where: 'product_id = ?', whereArgs: [product.id]);
      for (final unit in product.units) {
        await txn.insert('product_units', {
          'product_id': product.id,
          'unit_name': unit.unitName,
          'conversion_factor': unit.conversionFactor,
          'selling_price': unit.sellingPrice,
          'barcode': unit.barcode,
        });
      }

      // Re-insert tiered prices
      await txn.delete('tiered_prices', where: 'product_id = ?', whereArgs: [product.id]);
      for (final tp in product.tieredPrices) {
        await txn.insert('tiered_prices', {
          'product_id': product.id,
          'min_qty': tp.minQty,
          'price': tp.price,
        });
      }

      // Re-insert batches
      await txn.delete('product_batches', where: 'product_id = ?', whereArgs: [product.id]);
      for (final batch in product.batches) {
        await txn.insert('product_batches', {
          'product_id': product.id,
          'batch_number': batch.batchNumber,
          'expiry_date': batch.expiryDate.toIso8601String(),
          'stock_qty': batch.stockQty,
        });
      }
    });
  }

  Future<void> deleteProduct(int id) async {
    final db = await database;
    await db.update('products', {'is_active': 0}, where: 'id = ?', whereArgs: [id]);
  }

  Future<List<ProductUnitModel>> getProductUnits(int productId) async {
    final db = await database;
    final res = await db.query(
      'product_units',
      where: 'product_id = ?',
      whereArgs: [productId],
    );
    return res.map((e) => ProductUnitModel.fromMap(e)).toList();
  }

  Future<List<TieredPriceModel>> getTieredPrices(int productId) async {
    final db = await database;
    final res = await db.query(
      'tiered_prices',
      where: 'product_id = ?',
      whereArgs: [productId],
    );
    return res.map((e) => TieredPriceModel.fromMap(e)).toList();
  }

  Future<List<ProductBatchModel>> getProductBatches(int productId) async {
    final db = await database;
    final res = await db.query(
      'product_batches',
      where: 'product_id = ?',
      whereArgs: [productId],
    );
    return res.map((e) => ProductBatchModel.fromMap(e)).toList();
  }

  Future<List<Map<String, dynamic>>> getExpiringBatches() async {
    final db = await database;
    final res = await db.rawQuery('''
      SELECT b.*, p.name as product_name, p.code as product_code, p.base_unit
      FROM product_batches b
      JOIN products p ON b.product_id = p.id
      WHERE p.is_active = 1 AND b.stock_qty > 0
      ORDER BY b.expiry_date ASC
    ''');
    return res;
  }

  // ================= TRANSACTIONS =================
  Future<int> insertTransaction(TransactionModel trx) async {
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

        // Deduct inventory if not service
        if (!item.isService) {
          final deductAmount = item.baseStockQty;
          await txn.rawUpdate(
            'UPDATE products SET stock = stock - ? WHERE id = ?',
            [deductAmount, item.productId],
          );
        }
      }

      // If payment is kasbon, insert to customer_debts
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

  Future<List<TransactionModel>> getRecentTransactions({int limit = 50}) async {
    final db = await database;
    final res = await db.query(
      'transactions',
      orderBy: 'date DESC',
      limit: limit,
    );
    List<TransactionModel> list = [];
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
  Future<int> insertReturnOrder(ReturnOrderModel ret) async {
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

        // Restock if condition is good
        if (item.condition == 'baik') {
          await txn.rawUpdate(
            'UPDATE products SET stock = stock + ? WHERE id = ?',
            [item.baseStockQty, item.productId],
          );
        }
      }

      // Update original transaction status
      await txn.update(
        'transactions',
        {'status': 'partial_return'},
        where: 'id = ?',
        whereArgs: [ret.transactionId],
      );

      // Record cash out for return if cash refund
      if (ret.refundMethod == 'tunai') {
        await txn.insert('cash_flows', {
          'type': 'out',
          'category': 'Retur Penjualan',
          'amount': ret.totalRefund,
          'note': 'Retur Nota #${ret.invoiceNumber}',
          'date': DateTime.now().toIso8601String(),
          'cashier_name': ret.cashierName,
        });
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

  Future<int> insertCashFlow(CashFlowModel flow) async {
    final db = await database;
    return await db.insert('cash_flows', flow.toMap());
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

  // ================= ATTENDANCE (ABSENSI SELFIE) =================
  Future<int> insertAttendance(AttendanceModel att) async {
    final db = await database;
    return await db.insert('attendances', att.toMap());
  }

  Future<List<AttendanceModel>> getRecentAttendances({int limit = 100}) async {
    final db = await database;
    final res = await db.query(
      'attendances',
      orderBy: 'timestamp DESC',
      limit: limit,
    );
    return res.map((e) => AttendanceModel.fromMap(e)).toList();
  }

  // ================= AUDIT LOGS =================
  Future<int> insertAuditLog(AuditLogModel log) async {
    final db = await database;
    return await db.insert('audit_logs', log.toMap());
  }

  Future<List<AuditLogModel>> getAuditLogs({int limit = 100}) async {
    final db = await database;
    final res = await db.query(
      'audit_logs',
      orderBy: 'timestamp DESC',
      limit: limit,
    );
    return res.map((e) => AuditLogModel.fromMap(e)).toList();
  }

  // ================= CUSTOMER DEBTS (KASBON) =================
  Future<List<CustomerDebtModel>> getCustomerDebts() async {
    final db = await database;
    final res = await db.query(
      'customer_debts',
      orderBy: 'due_date ASC',
    );
    return res.map((e) => CustomerDebtModel.fromMap(e)).toList();
  }

  Future<void> payCustomerDebt(int debtId, double amountPaid) async {
    final db = await database;
    final debtRes = await db.query('customer_debts', where: 'id = ?', whereArgs: [debtId]);
    if (debtRes.isEmpty) return;

    final debt = CustomerDebtModel.fromMap(debtRes.first);
    final newPaid = debt.paidDebt + amountPaid;

    await db.update(
      'customer_debts',
      {
        'paid_debt': newPaid,
        'last_payment_date': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [debtId],
    );

    // Record cash in
    await db.insert('cash_flows', {
      'type': 'in',
      'category': 'Pelunasan Kasbon',
      'amount': amountPaid,
      'note': 'Pelunasan dari ${debt.customerName} (#${debt.invoiceNumber})',
      'date': DateTime.now().toIso8601String(),
      'cashier_name': 'Kasir',
    });
  }

  // ================= WAREHOUSE DOCS & STOCK OPNAME =================
  Future<int> insertWarehouseDoc(WarehouseDocModel doc) async {
    final db = await database;
    return await db.insert('warehouse_docs', doc.toMap());
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
      // Adjust system stock to match physical count
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
  Future<List<PromoModel>> getActivePromos() async {
    final db = await database;
    final res = await db.query('promos', where: 'is_active = 1');
    return res.map((e) => PromoModel.fromMap(e)).toList();
  }

  Future<int> insertPromo(PromoModel promo) async {
    final db = await database;
    return await db.insert('promos', promo.toMap());
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
    return {for (var item in res) item['key'] as String: item['value'] as String};
  }
}
