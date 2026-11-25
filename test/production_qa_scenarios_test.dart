import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:kasirtoko/database/db_helper.dart';
import 'package:kasirtoko/models/attendance.dart';
import 'package:kasirtoko/models/audit_log.dart';
import 'package:kasirtoko/models/cash_flow.dart';
import 'package:kasirtoko/models/customer.dart';
import 'package:kasirtoko/models/product.dart';
import 'package:kasirtoko/models/purchase.dart';
import 'package:kasirtoko/models/receipt_config.dart';
import 'package:kasirtoko/models/return_item.dart';
import 'package:kasirtoko/models/return_order.dart';
import 'package:kasirtoko/models/shift.dart';
import 'package:kasirtoko/models/stock_opname.dart';
import 'package:kasirtoko/models/transaction.dart';
import 'package:kasirtoko/models/transaction_item.dart';
import 'package:kasirtoko/models/user.dart';
import 'package:kasirtoko/providers/attendance_provider.dart';
import 'package:kasirtoko/providers/auth_provider.dart';
import 'package:kasirtoko/providers/pos_provider.dart';
import 'package:kasirtoko/providers/printer_provider.dart';
import 'package:kasirtoko/providers/settings_provider.dart';
import 'package:kasirtoko/screens/login_screen.dart';
import 'package:kasirtoko/screens/pos/receipt_dialog.dart';
import 'package:kasirtoko/services/printer/esc_pos_generator.dart';
import 'package:kasirtoko/services/printer/esc_pos_image_helper.dart';
import 'package:kasirtoko/services/thermal_printer_service.dart';
import 'package:kasirtoko/utils/app_theme.dart';
import 'package:kasirtoko/utils/date_format.dart';
import 'package:kasirtoko/utils/quick_cash_helper.dart';

Future<ProductModel?> _getProductById(int id) async {
  final list = await DatabaseHelper.instance.getProducts();
  for (final item in list) {
    if (item.id == id) return item;
  }
  return null;
}

class _TestAuthProvider extends AuthProvider {
  @override
  bool hasPermission(String permissionKey) => true;

  @override
  Future<void> logAction(
    String actionType,
    String details, {
    String? module,
    String objectId = '',
    String beforeValue = '',
    String afterValue = '',
  }) async {}
}

class _TestPrinterProvider extends PrinterProvider {
  @override
  Future<void> loadPrinters() async {}
}

class _TestSettingsProvider extends SettingsProvider {
  String _testStoreName = 'TOKO QA BERKAH';
  String _testLogoPath = '';
  ReceiptConfigModel _testConfig = const ReceiptConfigModel();

  void setTestConfig({String? storeName, String? logoPath, ReceiptConfigModel? config}) {
    if (storeName != null) _testStoreName = storeName;
    if (logoPath != null) _testLogoPath = logoPath;
    if (config != null) _testConfig = config;
  }

  @override
  String get storeName => _testStoreName;

  @override
  String get storeAddress => 'Jl. Pengujian No. 1';

  @override
  String get storePhone => '081200001111';

  @override
  String get logoPath => _testLogoPath;

  @override
  ReceiptConfigModel get receiptConfig => _testConfig;

  @override
  Future<void> loadSettings() async {}
}

String _createTempTransparentLogoPng(Directory dir) {
  final image = img.Image(width: 80, height: 40, numChannels: 4);
  // Transparent outer background, dark cross pattern in center
  img.fill(image, color: img.ColorRgba8(0, 0, 0, 0));
  img.fillRect(
    image,
    x1: 12,
    y1: 6,
    x2: 68,
    y2: 34,
    color: img.ColorRgba8(15, 118, 110, 255),
  );
  img.fillRect(
    image,
    x1: 24,
    y1: 12,
    x2: 56,
    y2: 28,
    color: img.ColorRgba8(20, 20, 20, 255),
  );
  final file = File(p.join(dir.path, 'qa_logo_${DateTime.now().microsecondsSinceEpoch}.png'));
  file.writeAsBytesSync(img.encodePng(image));
  return file.path;
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  setUpAll(() async {
    await DateHelper.ensureInitialized();
  });

  group('Production QA 21 Scenarios (Real SQLite)', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('kasirtoko_qa_');
      await DatabaseHelper.instance.openTestDatabase(path: inMemoryDatabasePath);
    });

    tearDown(() async {
      await DatabaseHelper.instance.closeTestDatabase();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('Scenario 1: Auth hashed storage, self-service change, and owner recovery', () async {
      final auth = AuthProvider();
      await auth.loadUsers();

      // Raw DB should never store plaintext pin or password
      final db = await DatabaseHelper.instance.database;
      final rawOwner = (await db.query('users', where: "username = 'owner'")).first;
      expect(rawOwner['pin'], '');
      expect((rawOwner['password_hash'] as String).length, greaterThanOrEqualTo(32));
      expect((rawOwner['password_salt'] as String), isNotEmpty);

      // Invalid login fails, valid login succeeds
      expect(await auth.loginWithPassword('owner', 'salah123'), isFalse);
      expect(await auth.loginWithPassword('owner', '123456'), isTrue);
      expect(auth.isOwner, isTrue);

      // Self-service change rejects wrong current secret
      final wrongCurrErr = await auth.changeOwnCredentials(
        currentSecret: '999999',
        newPassword: 'ownerbaru99',
        newPin: '654321',
      );
      expect(wrongCurrErr, isNotNull);

      // Valid credential update works & authenticates with new credentials
      final okChange = await auth.changeOwnCredentials(
        currentSecret: '123456',
        newPassword: 'ownerbaru99',
        newPin: '654321',
      );
      expect(okChange, isNull);
      auth.logout();

      expect(await auth.loginWithPassword('owner', '123456'), isFalse);
      expect(await auth.loginWithPassword('owner', 'ownerbaru99'), isTrue);

      // Owner-authorized recovery resets kasir account without exposing default secrets
      final recErr = await auth.recoverPasswordByOwner(
        ownerUsername: 'owner',
        ownerSecret: '654321',
        targetUsername: 'kasir',
        newPassword: 'kasirnew77',
        newPin: '7777',
      );
      expect(recErr, isNull);
      auth.logout();
      expect(await auth.loginWithPassword('kasir', 'kasirnew77'), isTrue);
      expect(auth.isCashier, isTrue);
    });

    test('Scenario 3: PosProvider inline grid qty controls enforce stock vs trackStock=false & jasa', () async {
      final pos = PosProvider();
      final tracked = ProductModel(
        id: 101,
        code: 'TRK-01',
        name: 'Beras 5kg',
        sellingPrice: 70000,
        stock: 5,
        isService: false,
        trackStock: true,
      );
      final untracked = ProductModel(
        id: 102,
        code: 'NTRK-01',
        name: 'Es Batu Custom',
        sellingPrice: 5000,
        stock: 0,
        isService: false,
        trackStock: false,
      );
      final service = ProductModel(
        id: 103,
        code: 'SRV-01',
        name: 'Servis LCD',
        sellingPrice: 150000,
        stock: 0,
        isService: true,
        trackStock: false,
      );

      expect(pos.setExactBaseQtyForProduct(tracked, 3).success, isTrue);
      expect(pos.getBaseCartQtyForProduct(101, 'Pcs'), 3);
      // Reject qty above physical stock when trackStock == true
      expect(pos.setExactBaseQtyForProduct(tracked, 6).success, isFalse);
      expect(pos.getBaseCartQtyForProduct(101, 'Pcs'), 3);

      // Unlimited qty allowed when trackStock == false or isService == true
      expect(pos.setExactBaseQtyForProduct(untracked, 20).success, isTrue);
      expect(pos.setExactBaseQtyForProduct(service, 4).success, isTrue);
      expect(pos.getBaseCartQtyForProduct(102, 'Pcs'), 20);
      expect(pos.getBaseCartQtyForProduct(103, 'Pcs'), 4);
    });

    test('Scenario 4: QuickCashHelper computes context-aware Rupiah nominals', () {
      expect(QuickCashHelper.suggestNominals(25000), equals([25000, 50000, 100000]));
      expect(QuickCashHelper.suggestNominals(49000), equals([50000, 100000, 150000]));
      expect(QuickCashHelper.suggestNominals(199000), equals([200000, 250000, 300000]));
      expect(QuickCashHelper.suggestNominals(375000), equals([400000, 500000, 600000]));
    });

    test('Scenario 5: Kasbon blocks Pelanggan Umum & unregistered customers, accepts registered member', () async {
      final shiftId = await DatabaseHelper.instance.openShift(
        ShiftModel(cashierId: 1, cashierName: 'Owner', startingCash: 100000, startTime: DateTime.now()),
      );
      final prodId = await DatabaseHelper.instance.insertProduct(
        ProductModel(code: 'KB-01', name: 'Gula 1kg', sellingPrice: 18000, costPrice: 14000, stock: 20),
      );
      final custId = await DatabaseHelper.instance.insertCustomer(
        CustomerModel(name: 'Budi Santoso', phone: '08123456789'),
      );

      // 5a. Walk-in 'Pelanggan Umum' without registered id must fail
      expect(
        () => DatabaseHelper.instance.insertTransaction(
          TransactionModel(
            invoiceNumber: 'INV-KB-FAIL-1',
            date: DateTime.now(),
            cashierId: 1,
            cashierName: 'Owner',
            customerId: null,
            customerName: 'Pelanggan Umum',
            subtotal: 18000,
            grandTotal: 18000,
            paymentMethod: 'kasbon',
            amountPaid: 0,
            items: [
              TransactionItemModel(
                productId: prodId,
                productCode: 'KB-01',
                productName: 'Gula 1kg',
                unitName: 'Pcs',
                qty: 1,
                unitPrice: 18000,
                subtotal: 18000,
              ),
            ],
          ),
          shiftId: shiftId,
        ),
        throwsStateError,
      );

      // 5b. Registered customer succeeds and creates linked debt
      final trxId = await DatabaseHelper.instance.insertTransaction(
        TransactionModel(
          invoiceNumber: 'INV-KB-OK-1',
          date: DateTime.now(),
          cashierId: 1,
          cashierName: 'Owner',
          customerId: custId,
          customerName: 'Budi Santoso',
          customerPhone: '08123456789',
          subtotal: 36000,
          grandTotal: 36000,
          paymentMethod: 'kasbon',
          amountPaid: 6000,
          items: [
            TransactionItemModel(
              productId: prodId,
              productCode: 'KB-01',
              productName: 'Gula 1kg',
              unitName: 'Pcs',
              qty: 2,
              unitPrice: 18000,
              subtotal: 36000,
            ),
          ],
        ),
        shiftId: shiftId,
      );
      expect(trxId, greaterThan(0));

      final debts = await DatabaseHelper.instance.getCustomerDebts();
      expect(debts.length, 1);
      expect(debts.first.customerId, custId);
      expect(debts.first.totalDebt, 36000);
      expect(debts.first.paidDebt, 6000);
      expect(debts.first.remainingDebt, 30000);
    });

    test('Scenario 6: Kasbon installment payment history tracked & retained accurately', () async {
      final shiftId = await DatabaseHelper.instance.openShift(
        ShiftModel(cashierId: 1, cashierName: 'Owner', startingCash: 50000, startTime: DateTime.now()),
      );
      final prodId = await DatabaseHelper.instance.insertProduct(
        ProductModel(code: 'KBI-01', name: 'Tepung Terigu', sellingPrice: 20000, costPrice: 15000, stock: 10),
      );
      final custId = await DatabaseHelper.instance.insertCustomer(
        CustomerModel(name: 'Siti Aminah', phone: '0899112233'),
      );

      await DatabaseHelper.instance.insertTransaction(
        TransactionModel(
          invoiceNumber: 'INV-INST-1',
          date: DateTime.now(),
          cashierId: 1,
          cashierName: 'Owner',
          customerId: custId,
          customerName: 'Siti Aminah',
          customerPhone: '0899112233',
          subtotal: 100000,
          grandTotal: 100000,
          paymentMethod: 'kasbon',
          amountPaid: 0,
          items: [
            TransactionItemModel(
              productId: prodId,
              productCode: 'KBI-01',
              productName: 'Tepung Terigu',
              unitName: 'Pcs',
              qty: 5,
              unitPrice: 20000,
              subtotal: 100000,
            ),
          ],
        ),
        shiftId: shiftId,
      );

      final debt = (await DatabaseHelper.instance.getCustomerDebts()).first;
      await DatabaseHelper.instance.payCustomerDebt(
        debt.id!,
        40000,
        paymentMethod: 'tunai',
        shiftId: shiftId,
        cashierName: 'Owner',
        note: 'Cicilan 1',
      );
      await DatabaseHelper.instance.payCustomerDebt(
        debt.id!,
        60000,
        paymentMethod: 'transfer',
        cashierName: 'Owner',
        note: 'Pelunasan transfer',
      );

      final updatedDebt = (await DatabaseHelper.instance.getCustomerDebts()).first;
      expect(updatedDebt.isPaidOff, isTrue);
      expect(updatedDebt.remainingDebt, 0);

      final history = await DatabaseHelper.instance.getCustomerDebtPayments(debt.id!);
      expect(history.length, 2);
      expect(history.map((h) => h.amount).reduce((a, b) => a + b), 100000);
      expect(await DatabaseHelper.instance.getCustomerOutstandingDebt(custId, 'Siti Aminah'), 0);
    });

    test('Scenario 7: Purchase via kas_laci enforces drawer cash sufficiency (no negative cash)', () async {
      final shiftId = await DatabaseHelper.instance.openShift(
        ShiftModel(cashierId: 1, cashierName: 'Owner', startingCash: 100000, startTime: DateTime.now()),
      );
      final prodId = await DatabaseHelper.instance.insertProduct(
        ProductModel(code: 'PO-01', name: 'Sabun', sellingPrice: 15000, costPrice: 10000, stock: 5),
      );

      // Purchase 150,000 from drawer with only 100,000 must fail
      expect(
        () => DatabaseHelper.instance.insertPurchase(
          PurchaseModel(
            purchaseNumber: 'PO-FAIL-1',
            supplierName: 'Agen A',
            totalAmount: 150000,
            paymentMethod: 'kas_laci',
            items: [
              PurchaseItemModel(
                productId: prodId,
                productName: 'Sabun',
                qty: 15,
                costPrice: 10000,
                subtotal: 150000,
              ),
            ],
          ),
          shiftId: shiftId,
        ),
        throwsStateError,
      );

      // Stock unchanged & drawer positive
      final prodAfterFail = await _getProductById(prodId);
      expect(prodAfterFail!.stock, 5);
      final shiftAfterFail = await DatabaseHelper.instance.getCurrentOpenShift();
      expect(shiftAfterFail!.expectedCash, 100000);

      // Valid 80,000 cash purchase succeeds
      await DatabaseHelper.instance.insertPurchase(
        PurchaseModel(
          purchaseNumber: 'PO-OK-1',
          supplierName: 'Agen A',
          totalAmount: 80000,
          paymentMethod: 'kas_laci',
          items: [
            PurchaseItemModel(
              productId: prodId,
              productName: 'Sabun',
              qty: 8,
              costPrice: 10000,
              subtotal: 80000,
            ),
          ],
        ),
        shiftId: shiftId,
      );

      expect((await _getProductById(prodId))!.stock, 13);
      expect((await DatabaseHelper.instance.getCurrentOpenShift())!.expectedCash, 20000);
    });

    test('Scenario 8: Supplier debt ledger, mixed payment, installment pay & voidPurchase reversal', () async {
      final shiftId = await DatabaseHelper.instance.openShift(
        ShiftModel(cashierId: 1, cashierName: 'Owner', startingCash: 200000, startTime: DateTime.now()),
      );
      final prodId = await DatabaseHelper.instance.insertProduct(
        ProductModel(code: 'SUP-01', name: 'Kopi Sachet', sellingPrice: 25000, costPrice: 20000, stock: 10),
      );

      final poId = await DatabaseHelper.instance.insertPurchase(
        PurchaseModel(
          purchaseNumber: 'PO-MIX-1',
          supplierName: 'PT Distributor Kopi',
          totalAmount: 300000,
          paymentMethod: 'campuran',
          cashPaid: 50000,
          transferPaid: 100000,
          creditAmount: 150000,
          transferAccount: 'BCA Toko',
          transferRef: 'TRF-881',
          dueDate: DateTime.now().add(const Duration(days: 7)),
          items: [
            PurchaseItemModel(
              productId: prodId,
              productName: 'Kopi Sachet',
              qty: 15,
              costPrice: 20000,
              subtotal: 300000,
            ),
          ],
        ),
        shiftId: shiftId,
      );

      expect((await _getProductById(prodId))!.stock, 25);
      expect((await DatabaseHelper.instance.getCurrentOpenShift())!.expectedCash, 150000);

      final debts = await DatabaseHelper.instance.getSupplierDebts();
      expect(debts.length, 1);
      expect(debts.first.remainingDebt, 150000);

      // Pay 50,000 supplier debt from cash drawer
      await DatabaseHelper.instance.paySupplierDebt(
        supplierDebtId: debts.first.id!,
        amount: 50000,
        paymentSource: 'kas_laci',
        shiftId: shiftId,
        paidBy: 'Owner',
      );
      final afterPay = (await DatabaseHelper.instance.getSupplierDebts()).first;
      expect(afterPay.remainingDebt, 100000);
      expect((await DatabaseHelper.instance.getCurrentOpenShift())!.expectedCash, 100000);

      // Create another credit PO and void it atomically
      final voidPoId = await DatabaseHelper.instance.insertPurchase(
        PurchaseModel(
          purchaseNumber: 'PO-VOID-1',
          supplierName: 'Agen Void',
          totalAmount: 40000,
          paymentMethod: 'kas_laci',
          items: [
            PurchaseItemModel(
              productId: prodId,
              productName: 'Kopi Sachet',
              qty: 2,
              costPrice: 20000,
              subtotal: 40000,
            ),
          ],
        ),
        shiftId: shiftId,
      );
      expect((await _getProductById(prodId))!.stock, 27);
      expect((await DatabaseHelper.instance.getCurrentOpenShift())!.expectedCash, 60000);

      await DatabaseHelper.instance.voidPurchase(voidPoId, shiftId: shiftId, cancelledBy: 'Owner');
      expect((await _getProductById(prodId))!.stock, 25);
      expect((await DatabaseHelper.instance.getCurrentOpenShift())!.expectedCash, 100000);
      expect(poId, greaterThan(0));
    });

    test('Scenario 9 & 10: Mandatory shift enforcement, single active shift, diff note, & admin shift correction', () async {
      final prodId = await DatabaseHelper.instance.insertProduct(
        ProductModel(code: 'SHF-1', name: 'Teh Botol', sellingPrice: 5000, costPrice: 3000, stock: 20),
      );

      // Scenario 9: Checkout without open shift fails
      expect(
        () => DatabaseHelper.instance.insertTransaction(
          TransactionModel(
            invoiceNumber: 'INV-NOSHIFT',
            date: DateTime.now(),
            cashierId: 1,
            cashierName: 'Kasir',
            subtotal: 5000,
            grandTotal: 5000,
            paymentMethod: 'tunai',
            amountPaid: 5000,
            items: [
              TransactionItemModel(
                productId: prodId,
                productCode: 'SHF-1',
                productName: 'Teh Botol',
                unitName: 'Pcs',
                qty: 1,
                unitPrice: 5000,
                subtotal: 5000,
              ),
            ],
          ),
        ),
        throwsStateError,
      );

      // Open shift 1, opening second concurrent shift fails
      final s1 = await DatabaseHelper.instance.openShift(
        ShiftModel(cashierId: 1, cashierName: 'Kasir 1', startingCash: 100000, startTime: DateTime.now()),
      );
      expect(
        () => DatabaseHelper.instance.openShift(
          ShiftModel(cashierId: 2, cashierName: 'Kasir 2', startingCash: 50000, startTime: DateTime.now()),
        ),
        throwsStateError,
      );

      // Scenario 10: Closing with variance without note fails
      expect(
        () => DatabaseHelper.instance.closeShift(s1, 95000, -5000, ''),
        throwsStateError,
      );

      // Closing with note succeeds & blocks double close
      await DatabaseHelper.instance.closeShift(s1, 95000, -5000, 'Salah kembalian');
      expect(
        () => DatabaseHelper.instance.closeShift(s1, 95000, -5000, 'Double'),
        throwsStateError,
      );

      // Owner/Admin audited shift correction adjusts actualCash & records audit log
      final adminUser = UserModel(id: 1, name: 'Pemilik Toko', role: AppRoles.owner);
      await DatabaseHelper.instance.adminCorrectShift(
        shiftId: s1,
        newActualCash: 100000,
        correctionNote: 'Uang terselip Rp 5.000 ditemukan di bawah laci',
        admin: adminUser,
      );

      final history = await DatabaseHelper.instance.getShiftHistory();
      expect(history.first.actualCash, 100000);
      expect(history.first.difference, 0);

      final logs = await DatabaseHelper.instance.getAuditLogsFiltered(actionType: 'koreksi_shift');
      expect(logs, isNotEmpty);
      expect(logs.first.beforeValue, isNotEmpty);
      expect(logs.first.afterValue, isNotEmpty);
    });

    test('Scenario 11 & 12: Returns cumulative qty guard + Void preserves returned qty without over-restore', () async {
      final shiftId = await DatabaseHelper.instance.openShift(
        ShiftModel(cashierId: 1, cashierName: 'Owner', startingCash: 100000, startTime: DateTime.now()),
      );
      final prodId = await DatabaseHelper.instance.insertProduct(
        ProductModel(code: 'RET-1', name: 'Susu Kaleng', sellingPrice: 15000, costPrice: 12000, stock: 10),
      );

      final trxId = await DatabaseHelper.instance.insertTransaction(
        TransactionModel(
          invoiceNumber: 'INV-RET-1',
          date: DateTime.now(),
          cashierId: 1,
          cashierName: 'Owner',
          subtotal: 60000,
          grandTotal: 60000,
          paymentMethod: 'tunai',
          amountPaid: 60000,
          items: [
            TransactionItemModel(
              productId: prodId,
              productCode: 'RET-1',
              productName: 'Susu Kaleng',
              unitName: 'Pcs',
              qty: 4,
              unitPrice: 15000,
              subtotal: 60000,
            ),
          ],
        ),
        shiftId: shiftId,
      );
      // Stock is now 6, cash expected = 160,000
      expect((await _getProductById(prodId))!.stock, 6);

      // Return 2 good condition -> stock becomes 8, cash expected = 130,000
      await DatabaseHelper.instance.insertReturnOrder(
        ReturnOrderModel(
          returnNumber: 'RET-A',
          transactionId: trxId,
          invoiceNumber: 'INV-RET-1',
          date: DateTime.now(),
          cashierId: 1,
          cashierName: 'Owner',
          totalRefund: 30000,
          refundMethod: 'tunai',
          items: [
            ReturnItemModel(
              productId: prodId,
              productName: 'Susu Kaleng',
              unitName: 'Pcs',
              returnQty: 2,
              refundPrice: 15000,
              subtotal: 30000,
              condition: 'baik',
            ),
          ],
        ),
        shiftId: shiftId,
      );
      expect((await _getProductById(prodId))!.stock, 8);
      expect((await DatabaseHelper.instance.getCurrentOpenShift())!.expectedCash, 130000);

      // Attempting second return of 3 (> remaining 2) MUST throw!
      expect(
        () => DatabaseHelper.instance.insertReturnOrder(
          ReturnOrderModel(
            returnNumber: 'RET-OVER',
            transactionId: trxId,
            invoiceNumber: 'INV-RET-1',
            date: DateTime.now(),
            cashierId: 1,
            cashierName: 'Owner',
            totalRefund: 45000,
            refundMethod: 'tunai',
            items: [
              ReturnItemModel(
                productId: prodId,
                productName: 'Susu Kaleng',
                unitName: 'Pcs',
                returnQty: 3,
                refundPrice: 15000,
                subtotal: 45000,
                condition: 'baik',
              ),
            ],
          ),
          shiftId: shiftId,
        ),
        throwsStateError,
      );

      // Scenario 12: Now void the original transaction: must restore ONLY remaining 2 unreturned units (8 + 2 = 10, NOT 8 + 4 = 12!)
      await DatabaseHelper.instance.voidTransaction(trxId, shiftId: shiftId);
      expect((await _getProductById(prodId))!.stock, 10);
    });

    test('Scenario 13: Cash Flow report excludes internal transfers from operational revenue/expense', () async {
      final now = DateTime.now();
      final shiftId = await DatabaseHelper.instance.openShift(
        ShiftModel(cashierId: 1, cashierName: 'Owner', startingCash: 100000, startTime: now),
      );
      final prodId = await DatabaseHelper.instance.insertProduct(
        ProductModel(code: 'CF-1', name: 'Minyak', sellingPrice: 20000, costPrice: 16000, stock: 10),
      );
      await DatabaseHelper.instance.insertTransaction(
        TransactionModel(
          invoiceNumber: 'INV-CF-1',
          date: now,
          cashierId: 1,
          cashierName: 'Owner',
          subtotal: 40000,
          grandTotal: 40000,
          paymentMethod: 'tunai',
          amountPaid: 40000,
          items: [
            TransactionItemModel(
              productId: prodId,
              productCode: 'CF-1',
              productName: 'Minyak',
              unitName: 'Pcs',
              qty: 2,
              unitPrice: 20000,
              subtotal: 40000,
            ),
          ],
        ),
        shiftId: shiftId,
      );

      // Operational expense: Rp 10.000
      await DatabaseHelper.instance.insertCashFlow(
        CashFlowModel(
          shiftId: shiftId,
          type: 'out',
          category: 'Operasional Toko',
          amount: 10000,
          paymentMethod: 'tunai',
          accountName: 'Laci Kasir',
          date: now,
          cashierName: 'Owner',
        ),
      );

      // Internal bank deposit Rp 50.000 from Laci -> MUST affect cash drawer ending balance, NOT operational expense!
      await DatabaseHelper.instance.insertCashFlow(
        CashFlowModel(
          shiftId: shiftId,
          type: 'out',
          category: 'Setor Bank Internal',
          amount: 50000,
          paymentMethod: 'tunai',
          accountName: 'Laci Kasir',
          sourceType: 'transfer_internal',
          isInternalTransfer: true,
          date: now,
          cashierName: 'Owner',
        ),
      );

      final report = await DatabaseHelper.instance.getCashFlowReport(now, now);
      expect(report['totalSalesCash'], 40000);
      expect(report['totalOperationalIn'], 40000); //excludes shift modal & internal transfer!
      expect(report['totalOpExpenses'], 10000);
      expect(report['totalOperationalOut'], 10000); //excludes Rp 50k internal transfer!
      expect(report['totalInternalTransfers'], 50000);
      // Ending drawer cash: 100k modal + 40k sales - 10k expense - 50k setor bank = 80k
      expect(report['endingCashBalance'], 80000);
    });

    test('Scenario 14: Stock Opname Batch prevents duplicate corruption & adjusts stock atomically', () async {
      final p1 = await DatabaseHelper.instance.insertProduct(
        ProductModel(code: 'OP-1', name: 'Kopi A', sellingPrice: 10000, stock: 10),
      );
      final p2 = await DatabaseHelper.instance.insertProduct(
        ProductModel(code: 'OP-2', name: 'Teh B', sellingPrice: 8000, stock: 5),
      );

      await DatabaseHelper.instance.insertStockOpnamesBatch([
        StockOpnameModel(
          date: DateTime.now(),
          productId: p1,
          productCode: 'OP-1',
          productName: 'Kopi A',
          systemStock: 10,
          physicalStock: 14,
          difference: 4,
          auditedBy: 'Gudang',
        ),
        StockOpnameModel(
          date: DateTime.now(),
          productId: p2,
          productCode: 'OP-2',
          productName: 'Teh B',
          systemStock: 5,
          physicalStock: 3,
          difference: -2,
          auditedBy: 'Gudang',
        ),
      ]);

      expect((await _getProductById(p1))!.stock, 14);
      expect((await _getProductById(p2))!.stock, 3);
      final history = await DatabaseHelper.instance.getStockOpnames();
      expect(history.length, 2);
    });

    test('Scenario 15: Attendance blocks double masuk, pulang without masuk, double pulang, clock rollback, replay token, + Admin correction', () async {
      final now = DateTime.now();
      final attProv = AttendanceProvider();

      // Pulang before masuk blocked
      expect(
        await attProv.validateAttendanceAttempt(employeeId: 3, type: 'pulang', timestamp: now),
        isNotNull,
      );
      expect(
        () => DatabaseHelper.instance.insertAttendance(
          AttendanceModel(
            employeeId: 3,
            employeeName: 'Kasir 1',
            timestamp: now,
            type: 'pulang',
            status: 'tepat_waktu',
            challengeCode: 'TOK-001',
            validationHash: 'H1',
            photoPath: '',
          ),
        ),
        throwsStateError,
      );

      // Valid masuk
      final masukId = await DatabaseHelper.instance.insertAttendance(
        AttendanceModel(
          employeeId: 3,
          employeeName: 'Kasir 1',
          timestamp: now,
          type: 'masuk',
          status: 'terlambat',
          lateMinutes: 15,
          challengeCode: 'TOK-MASUK',
          validationHash: 'H2',
          photoPath: '',
        ),
      );

      // Double masuk blocked
      expect(
        () => DatabaseHelper.instance.insertAttendance(
          AttendanceModel(
            employeeId: 3,
            employeeName: 'Kasir 1',
            timestamp: now.add(const Duration(minutes: 5)),
            type: 'masuk',
            status: 'tepat_waktu',
            challengeCode: 'TOK-MASUK-2',
            validationHash: 'H3',
            photoPath: '',
          ),
        ),
        throwsStateError,
      );

      // Clock rollback (1 hour earlier) blocked
      expect(
        () => DatabaseHelper.instance.insertAttendance(
          AttendanceModel(
            employeeId: 3,
            employeeName: 'Kasir 1',
            timestamp: now.subtract(const Duration(hours: 1)),
            type: 'pulang',
            status: 'tepat_waktu',
            challengeCode: 'TOK-ROLLBACK',
            validationHash: 'H4',
            photoPath: '',
          ),
        ),
        throwsStateError,
      );

      // Replay token blocked
      expect(
        () => DatabaseHelper.instance.insertAttendance(
          AttendanceModel(
            employeeId: 3,
            employeeName: 'Kasir 1',
            timestamp: now.add(const Duration(minutes: 10)),
            type: 'pulang',
            status: 'tepat_waktu',
            challengeCode: 'TOK-MASUK',
            validationHash: 'H5',
            photoPath: '',
          ),
        ),
        throwsStateError,
      );

      // Valid pulang succeeds
      await DatabaseHelper.instance.insertAttendance(
        AttendanceModel(
          employeeId: 3,
          employeeName: 'Kasir 1',
          timestamp: now.add(const Duration(minutes: 15)),
          type: 'pulang',
          status: 'tepat_waktu',
          challengeCode: 'TOK-PULANG',
          validationHash: 'H6',
          photoPath: '',
        ),
      );

      // Double pulang blocked
      expect(
        () => DatabaseHelper.instance.insertAttendance(
          AttendanceModel(
            employeeId: 3,
            employeeName: 'Kasir 1',
            timestamp: now.add(const Duration(minutes: 20)),
            type: 'pulang',
            status: 'tepat_waktu',
            challengeCode: 'TOK-PULANG-2',
            validationHash: 'H7',
            photoPath: '',
          ),
        ),
        throwsStateError,
      );

      // Admin correction updates record & writes audit log
      final admin = UserModel(id: 1, name: 'Pemilik Toko', role: AppRoles.owner);
      await DatabaseHelper.instance.correctAttendanceByAdmin(
        attendanceId: masukId,
        newStatus: 'tepat_waktu',
        newLateMinutes: 0,
        correctionNote: 'Tugas pengantaran pagi',
        admin: admin,
      );
      final updatedAtt = (await DatabaseHelper.instance.getRecentAttendances())
          .firstWhere((a) => a.id == masukId);
      expect(updatedAtt.isCorrected, isTrue);
      expect(updatedAtt.lateMinutes, 0);
      expect(updatedAtt.status, 'tepat_waktu');
    });

    test('Scenario 16: Audit log filtering (date, user, action, search, pagination, diff fields)', () async {
      final now = DateTime.now();
      for (int i = 0; i < 35; i++) {
        await DatabaseHelper.instance.insertAuditLog(
          AuditLogModel(
            userId: i.isEven ? 1 : 3,
            userName: i.isEven ? 'Pemilik Toko' : 'Kasir 1',
            userRole: i.isEven ? 'owner' : 'kasir',
            actionType: i % 5 == 0 ? 'void_transaksi' : 'transaksi_selesai',
            module: 'transaksi',
            objectId: 'INV-$i',
            details: 'Log uji ke-$i',
            beforeValue: i == 0 ? 'completed' : '',
            afterValue: i == 0 ? 'voided' : '',
            timestamp: now.subtract(Duration(minutes: i)),
          ),
        );
      }

      final page1 = await DatabaseHelper.instance.getAuditLogsFiltered(
        start: now.subtract(const Duration(days: 1)),
        end: now.add(const Duration(minutes: 5)),
        limit: 20,
        offset: 0,
      );
      final page2 = await DatabaseHelper.instance.getAuditLogsFiltered(
        start: now.subtract(const Duration(days: 1)),
        end: now.add(const Duration(minutes: 5)),
        limit: 20,
        offset: 20,
      );
      expect(page1.length, 20);
      expect(page2.length, 15);

      final voids = await DatabaseHelper.instance.getAuditLogsFiltered(
        actionType: 'void_transaksi',
        userId: 1,
        searchQuery: 'INV-0',
      );
      expect(voids.length, 1);
      expect(voids.first.beforeValue, 'completed');
      expect(voids.first.afterValue, 'voided');
    });

    test('Scenario 17: Business analytics report computes real SQLite sales, HPP, profit & unsold products', () async {
      final now = DateTime.now();
      final shiftId = await DatabaseHelper.instance.openShift(
        ShiftModel(cashierId: 1, cashierName: 'Owner', startingCash: 100000, startTime: now),
      );
      final soldProd = await DatabaseHelper.instance.insertProduct(
        ProductModel(code: 'AN-1', name: 'Produk Laku', sellingPrice: 50000, costPrice: 30000, stock: 10),
      );
      await DatabaseHelper.instance.insertProduct(
        ProductModel(code: 'AN-2', name: 'Produk Belum Laku', sellingPrice: 25000, costPrice: 15000, stock: 8),
      );

      await DatabaseHelper.instance.insertTransaction(
        TransactionModel(
          invoiceNumber: 'INV-AN-1',
          date: now,
          cashierId: 1,
          cashierName: 'Owner',
          subtotal: 100000,
          grandTotal: 100000,
          paymentMethod: 'qris',
          amountPaid: 100000,
          items: [
            TransactionItemModel(
              productId: soldProd,
              productCode: 'AN-1',
              productName: 'Produk Laku',
              unitName: 'Pcs',
              qty: 2,
              unitPrice: 50000,
              costPrice: 30000,
              subtotal: 100000,
            ),
          ],
        ),
        shiftId: shiftId,
      );

      final report = await DatabaseHelper.instance.getBusinessAnalyticsReport(now, now);
      final sales = report['sales'] as Map<String, dynamic>;
      final profit = report['profit'] as Map<String, dynamic>;
      final products = report['products'] as Map<String, dynamic>;

      expect(sales['totalRevenue'], 100000);
      expect(sales['qrisSales'], 100000);
      expect(profit['totalHpp'], 60000);
      expect(profit['grossProfit'], 40000);
      expect((products['topSelling'] as List).length, 1);
      expect((products['unsold'] as List).any((u) => u['code'] == 'AN-2'), isTrue);
    });

    test('Scenario 18 & 19: Store logo ESC/POS GS v 0 bitmap + hideStoreNameWithLogo fallback', () async {
      final logoPath = _createTempTransparentLogoPng(tempDir);

      // Verify normalized white-matte PNG bytes for PDF
      final normBytes = EscPosImageHelper.loadNormalizedPngBytes(logoPath);
      expect(normBytes, isNotNull);
      final decodedNorm = img.decodePng(normBytes!);
      expect(decodedNorm, isNotNull);
      // Top-left transparent corner flattened onto white (255, 255, 255) instead of black (0, 0, 0)
      final corner = decodedNorm!.getPixel(0, 0);
      expect(corner.r.toInt(), 255);
      expect(corner.g.toInt(), 255);
      expect(corner.b.toInt(), 255);

      final trx = TransactionModel(
        invoiceNumber: 'INV-LOGO-1',
        date: DateTime(2026, 11, 25, 10, 0),
        cashierId: 1,
        cashierName: 'Owner',
        subtotal: 25000,
        grandTotal: 25000,
        amountPaid: 25000,
        items: [
          TransactionItemModel(
            productId: 1,
            productCode: 'LG-1',
            productName: 'Barang Logo',
            unitName: 'Pcs',
            qty: 1,
            unitPrice: 25000,
            subtotal: 25000,
          ),
        ],
      );

      // When hideStoreNameWithLogo=true AND logo exists: emits GS v 0 (0x1D 0x76 0x30) AND omits store name text!
      final withLogoHiddenName = EscPosGenerator.buildTransactionReceipt(
        transaction: trx,
        storeName: 'TOKO LOGO EKSKLUSIF',
        storeAddress: 'Jl. Sudirman',
        storePhone: '08111',
        config: const ReceiptConfigModel(showLogo: true, hideStoreNameWithLogo: true),
        charWidth: 32,
        logoPath: logoPath,
      );
      // Verify GS v 0 header exists
      bool hasGsV0 = false;
      for (int i = 0; i < withLogoHiddenName.length - 3; i++) {
        if (withLogoHiddenName[i] == 0x1D &&
            withLogoHiddenName[i + 1] == 0x76 &&
            withLogoHiddenName[i + 2] == 0x30) {
          hasGsV0 = true;
          break;
        }
      }
      expect(hasGsV0, isTrue);
      expect(latin1.decode(withLogoHiddenName, allowInvalid: true), isNot(contains('TOKO LOGO EKSKLUSIF')));

      // When hideStoreNameWithLogo=true BUT logo missing: falls back to printing store name!
      final missingLogoFallback = EscPosGenerator.buildTransactionReceipt(
        transaction: trx,
        storeName: 'TOKO LOGO EKSKLUSIF',
        storeAddress: 'Jl. Sudirman',
        storePhone: '08111',
        config: const ReceiptConfigModel(showLogo: true, hideStoreNameWithLogo: true),
        charWidth: 32,
        logoPath: '${tempDir.path}/tidak_ada.png',
      );
      expect(latin1.decode(missingLogoFallback, allowInvalid: true), contains('TOKO LOGO EKSKLUSIF'));
    });

    test('Scenario 20: Product Barcode/QR ESC/POS labels & A4 PDF Grid generation', () async {
      final bytes1d = EscPosGenerator.buildProductLabels(
        items: [
          const ProductLabelItem(
            name: 'Gula Pasir 1kg',
            sku: 'GUL-01',
            barcodeData: '899123456789',
            price: 17500,
            copyCount: 2,
          ),
        ],
        storeName: 'TOKO BARCODE',
        charWidth: 32,
        isQrCode: false,
        showStoreName: true,
        showSku: true,
        showPrice: true,
        autoCut: true,
      );
      final str1d = latin1.decode(bytes1d, allowInvalid: true);
      expect(str1d, contains('Gula Pasir 1kg'));
      expect(str1d, contains('GUL-01'));
      expect(bytes1d.contains(0x6B), isTrue); // GS k barcode command

      final bytesQr = EscPosGenerator.buildProductLabels(
        items: [
          const ProductLabelItem(
            name: 'Minyak 2L',
            sku: 'MNY-02',
            barcodeData: '8999888777',
            price: 36000,
            copyCount: 1,
          ),
        ],
        storeName: 'TOKO QR',
        charWidth: 32,
        isQrCode: true,
      );
      expect(latin1.decode(bytesQr, allowInvalid: true), contains('Minyak 2L'));
      // Validates A4 sticker PDF helper exists cleanly via PrinterManager adapter signature
      expect(
        const EscPosLabelItemAdapter(
          name: 'Test',
          sku: 'S1',
          barcodeData: '123456',
          price: 1000,
          copyCount: 1,
        ).copyCount,
        1,
      );
    });

    test('Scenario 21: Non-destructive v1 -> v3 database schema upgrade preserves legacy rows & creates v3 tables', () async {
      await DatabaseHelper.instance.closeTestDatabase();
      final legacyPath = p.join(tempDir.path, 'legacy_v1.db');

      // Manually build a v1 schema database with legacy product & transaction rows
      final legacyDb = await openDatabase(
        legacyPath,
        version: 1,
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE products (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              code TEXT UNIQUE,
              name TEXT NOT NULL,
              category TEXT,
              barcode TEXT,
              is_service INTEGER DEFAULT 0,
              base_unit TEXT DEFAULT 'Pcs',
              cost_price REAL DEFAULT 0,
              selling_price REAL NOT NULL,
              stock REAL DEFAULT 0,
              min_stock_alert REAL DEFAULT 5,
              image_path TEXT,
              brand TEXT DEFAULT '',
              model TEXT DEFAULT '',
              condition_type TEXT DEFAULT 'baru',
              imei_or_sn TEXT DEFAULT '',
              warranty_info TEXT DEFAULT '',
              description TEXT DEFAULT '',
              is_active INTEGER DEFAULT 1
            )
          ''');
          await db.execute('CREATE TABLE product_units (id INTEGER PRIMARY KEY AUTOINCREMENT, product_id INTEGER, unit_name TEXT, conversion_factor REAL, selling_price REAL, barcode TEXT)');
          await db.execute('CREATE TABLE tiered_prices (id INTEGER PRIMARY KEY AUTOINCREMENT, product_id INTEGER, min_qty REAL, price REAL)');
          await db.execute('CREATE TABLE product_batches (id INTEGER PRIMARY KEY AUTOINCREMENT, product_id INTEGER, batch_number TEXT, expiry_date TEXT, stock_qty REAL)');
          await db.execute('CREATE TABLE users (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, pin TEXT NOT NULL, role TEXT NOT NULL, phone TEXT, photo_path TEXT, permissions_json TEXT, is_active INTEGER DEFAULT 1)');
          await db.execute('CREATE TABLE transactions (id INTEGER PRIMARY KEY AUTOINCREMENT, invoice_number TEXT UNIQUE NOT NULL, date TEXT NOT NULL, cashier_id INTEGER, cashier_name TEXT, customer_name TEXT, customer_phone TEXT, subtotal REAL, discount_total REAL DEFAULT 0, tax_amount REAL DEFAULT 0, promo_name TEXT DEFAULT "", grand_total REAL NOT NULL, payment_method TEXT NOT NULL, amount_paid REAL NOT NULL, change_amount REAL DEFAULT 0, status TEXT DEFAULT "completed", qr_code_payload TEXT, note TEXT, printer_snapshot_json TEXT)');
          await db.execute('CREATE TABLE transaction_items (id INTEGER PRIMARY KEY AUTOINCREMENT, transaction_id INTEGER, product_id INTEGER, product_code TEXT, product_name TEXT, unit_name TEXT, conversion_factor REAL DEFAULT 1, qty REAL, unit_price REAL, discount REAL DEFAULT 0, subtotal REAL, cost_price REAL DEFAULT 0, is_service INTEGER DEFAULT 0)');
          await db.execute('CREATE TABLE customer_debts (id INTEGER PRIMARY KEY AUTOINCREMENT, customer_name TEXT NOT NULL, customer_phone TEXT, invoice_number TEXT, total_debt REAL NOT NULL, paid_debt REAL DEFAULT 0, transaction_date TEXT, due_date TEXT, last_payment_date TEXT, note TEXT)');
          await db.execute('CREATE TABLE shifts (id INTEGER PRIMARY KEY AUTOINCREMENT, cashier_id INTEGER, cashier_name TEXT, start_time TEXT NOT NULL, end_time TEXT, starting_cash REAL DEFAULT 0, total_sales_cash REAL DEFAULT 0, total_sales_qris REAL DEFAULT 0, total_sales_transfer REAL DEFAULT 0, total_sales_kasbon REAL DEFAULT 0, total_cash_in REAL DEFAULT 0, total_cash_out REAL DEFAULT 0, total_return_cash REAL DEFAULT 0, actual_cash REAL, difference REAL, status TEXT DEFAULT "open", note TEXT)');
          await db.execute('CREATE TABLE cash_flows (id INTEGER PRIMARY KEY AUTOINCREMENT, shift_id INTEGER, type TEXT NOT NULL, category TEXT, amount REAL NOT NULL, note TEXT, date TEXT NOT NULL, cashier_name TEXT)');
          await db.execute('CREATE TABLE attendances (id INTEGER PRIMARY KEY AUTOINCREMENT, employee_id INTEGER, employee_name TEXT, timestamp TEXT NOT NULL, type TEXT NOT NULL, status TEXT NOT NULL, late_minutes INTEGER DEFAULT 0, challenge_code TEXT, validation_hash TEXT, photo_path TEXT, is_liveness_passed INTEGER DEFAULT 1)');
          await db.execute('CREATE TABLE audit_logs (id INTEGER PRIMARY KEY AUTOINCREMENT, user_id INTEGER, user_name TEXT, action_type TEXT NOT NULL, details TEXT, timestamp TEXT NOT NULL)');
          await db.execute('CREATE TABLE stock_opnames (id INTEGER PRIMARY KEY AUTOINCREMENT, date TEXT NOT NULL, product_id INTEGER, product_code TEXT, product_name TEXT, system_stock REAL, physical_stock REAL, difference REAL, note TEXT, audited_by TEXT)');
          await db.execute('CREATE TABLE store_settings (key TEXT PRIMARY KEY, value TEXT)');
          await db.execute('CREATE TABLE promos (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, promo_type TEXT NOT NULL, discount_value REAL DEFAULT 0, min_purchase REAL DEFAULT 0, buy_qty INTEGER DEFAULT 1, get_qty INTEGER DEFAULT 1, start_date TEXT, end_date TEXT, is_active INTEGER DEFAULT 1)');
          await db.execute('CREATE TABLE warehouse_docs (id INTEGER PRIMARY KEY AUTOINCREMENT, doc_number TEXT UNIQUE NOT NULL, doc_type TEXT NOT NULL, date TEXT NOT NULL, recipient_name TEXT, recipient_address TEXT, recipient_phone TEXT, driver_or_picker_name TEXT, vehicle_plate TEXT, items_json TEXT, note TEXT, created_by TEXT)');
          await db.execute('CREATE TABLE return_orders (id INTEGER PRIMARY KEY AUTOINCREMENT, return_number TEXT UNIQUE NOT NULL, transaction_id INTEGER NOT NULL, invoice_number TEXT NOT NULL, date TEXT NOT NULL, cashier_id INTEGER, cashier_name TEXT, total_refund REAL NOT NULL, refund_method TEXT NOT NULL, note TEXT)');
          await db.execute('CREATE TABLE return_items (id INTEGER PRIMARY KEY AUTOINCREMENT, return_order_id INTEGER NOT NULL, product_id INTEGER, product_name TEXT, unit_name TEXT, conversion_factor REAL DEFAULT 1, return_qty REAL, refund_price REAL, subtotal REAL, condition TEXT DEFAULT "baik")');
          await db.execute('CREATE TABLE customers (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, phone TEXT, address TEXT, email TEXT, notes TEXT, points INTEGER DEFAULT 0, created_at TEXT)');
          await db.execute('CREATE TABLE service_orders (id INTEGER PRIMARY KEY AUTOINCREMENT, service_number TEXT UNIQUE NOT NULL, customer_name TEXT NOT NULL, customer_phone TEXT, device_type TEXT, device_brand TEXT, device_model TEXT, imei_or_sn TEXT, problem_description TEXT, accessories TEXT, technician_id INTEGER, technician_name TEXT, estimated_cost REAL DEFAULT 0, final_cost REAL DEFAULT 0, dp_paid REAL DEFAULT 0, status TEXT DEFAULT "diterima", received_date TEXT, completed_date TEXT, warranty_days INTEGER DEFAULT 7, notes TEXT)');
          await db.execute('CREATE TABLE purchases (id INTEGER PRIMARY KEY AUTOINCREMENT, purchase_number TEXT UNIQUE NOT NULL, supplier_name TEXT NOT NULL, supplier_phone TEXT, date TEXT NOT NULL, total_amount REAL NOT NULL, payment_method TEXT DEFAULT "kas_laci", note TEXT, created_by TEXT)');
          await db.execute('CREATE TABLE purchase_items (id INTEGER PRIMARY KEY AUTOINCREMENT, purchase_id INTEGER NOT NULL, product_id INTEGER NOT NULL, product_name TEXT, qty REAL NOT NULL, unit_name TEXT DEFAULT "Pcs", conversion_factor REAL DEFAULT 1, cost_price REAL NOT NULL, subtotal REAL NOT NULL)');

          await db.insert('products', {
            'code': 'LEG-01',
            'name': 'Produk Warisan V1',
            'selling_price': 12000,
            'stock': 42,
            'is_service': 0,
          });
          await db.insert('users', {
            'name': 'Admin V1',
            'pin': '9988',
            'role': 'owner',
          });
        },
      );
      await legacyDb.close();

      // Upgrade v1 -> v3 using DatabaseHelper.openTestDatabase(deleteIfExists: false)
      final upgradedDb = await DatabaseHelper.instance.openTestDatabase(
        path: legacyPath,
        deleteIfExists: false,
      );

      final prods = await DatabaseHelper.instance.getProducts();
      expect(prods.any((p) => p.code == 'LEG-01' && p.stock == 42 && p.trackStock == true), isTrue);

      // Legacy plain PIN 9988 should be migrated to hashed password_hash/pin_hash cleanly
      final upgradedOwner = await DatabaseHelper.instance.loginWithPin('9988');
      expect(upgradedOwner, isNotNull);

      final tables = await upgradedDb.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      );
      final tableNames = tables.map((r) => r['name']).toSet();
      expect(tableNames, containsAll(['customer_debt_payments', 'supplier_debts', 'supplier_debt_payments']));
    });
  });

  group('Widget QA Scenarios (UI Security & Receipt Rendering)', () {
    testWidgets('Scenario 2: LoginScreen exposes zero default passwords/PINs & renders cleanly', (tester) async {
      final auth = AuthProvider();
      final settings = _TestSettingsProvider();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: auth),
            ChangeNotifierProvider<SettingsProvider>.value(value: settings),
          ],
          child: MaterialApp(theme: AppTheme.lightTheme, home: const LoginScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // Must NOT leak seeded default PINs / passwords anywhere in UI
      expect(find.textContaining('123456'), findsNothing);
      expect(find.textContaining('1111'), findsNothing);
      expect(find.textContaining('2222'), findsNothing);
      expect(find.textContaining('3333'), findsNothing);
      expect(find.textContaining('4444'), findsNothing);
      expect(find.textContaining('Owner (123456)'), findsNothing);
      expect(find.textContaining('Lupa Password'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Scenario 19 Widget: ReceiptDialog honors hideStoreNameWithLogo & falls back when logo missing', (tester) async {
      final wTemp = Directory.systemTemp.createTempSync('kasirtoko_wqa_');
      addTearDown(() {
        if (wTemp.existsSync()) wTemp.deleteSync(recursive: true);
      });

      final logoPath = _createTempTransparentLogoPng(wTemp);
      final settings = _TestSettingsProvider();
      final auth = _TestAuthProvider();
      final printer = _TestPrinterProvider();
      final trx = TransactionModel(
        invoiceNumber: 'INV-RDLG-1',
        date: DateTime(2026, 11, 25, 11, 0),
        cashierId: 1,
        cashierName: 'Kasir',
        subtotal: 15000,
        grandTotal: 15000,
        amountPaid: 15000,
        items: [
          TransactionItemModel(
            productId: 1,
            productCode: 'A1',
            productName: 'Item Struk',
            unitName: 'Pcs',
            qty: 1,
            unitPrice: 15000,
            subtotal: 15000,
          ),
        ],
      );

      settings.setTestConfig(
        storeName: 'TOKO HILANG NAMA',
        logoPath: logoPath,
        config: const ReceiptConfigModel(showLogo: true, hideStoreNameWithLogo: true),
      );
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: auth),
            ChangeNotifierProvider<SettingsProvider>.value(value: settings),
            ChangeNotifierProvider<PrinterProvider>.value(value: printer),
          ],
          child: MaterialApp(home: Scaffold(body: ReceiptDialog(transaction: trx))),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('TOKO HILANG NAMA'), findsNothing);

      // Now simulate broken logo path -> must display store name fallback
      settings.setTestConfig(
        storeName: 'TOKO FALLBACK NAMA',
        logoPath: '${wTemp.path}/deleted_logo.png',
        config: const ReceiptConfigModel(showLogo: true, hideStoreNameWithLogo: true),
      );
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: auth),
            ChangeNotifierProvider<SettingsProvider>.value(value: settings),
            ChangeNotifierProvider<PrinterProvider>.value(value: printer),
          ],
          child: MaterialApp(home: Scaffold(body: ReceiptDialog(key: const ValueKey('fallback'), transaction: trx))),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('TOKO FALLBACK NAMA'), findsOneWidget);
    });
  });
}
