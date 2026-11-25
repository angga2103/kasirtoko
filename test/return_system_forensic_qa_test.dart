import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:kasirtoko/database/db_helper.dart';
import 'package:kasirtoko/models/customer.dart';
import 'package:kasirtoko/models/inventory_movement.dart';
import 'package:kasirtoko/models/product.dart';
import 'package:kasirtoko/models/return_exchange_item.dart';
import 'package:kasirtoko/models/return_item.dart';
import 'package:kasirtoko/models/return_order.dart';
import 'package:kasirtoko/models/shift.dart';
import 'package:kasirtoko/models/transaction.dart';
import 'package:kasirtoko/models/transaction_item.dart';
import 'package:kasirtoko/providers/auth_provider.dart';
import 'package:kasirtoko/providers/cash_flow_provider.dart';
import 'package:kasirtoko/providers/customer_provider.dart';
import 'package:kasirtoko/providers/debt_provider.dart';
import 'package:kasirtoko/providers/pos_provider.dart';
import 'package:kasirtoko/providers/printer_provider.dart';
import 'package:kasirtoko/providers/product_provider.dart';
import 'package:kasirtoko/providers/settings_provider.dart';
import 'package:kasirtoko/screens/pos/payment_dialog.dart';
import 'package:kasirtoko/screens/returns/return_screen.dart';
import 'package:kasirtoko/utils/app_theme.dart';

Future<ProductModel> _prod(int id) async {
  final list = await DatabaseHelper.instance.getProducts();
  return list.firstWhere((p) => p.id == id);
}

class _QaAuthProvider extends AuthProvider {
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

class _QaSettingsProvider extends SettingsProvider {
  @override
  String get storeName => 'TOKO QA RETUR';
  @override
  String get storeAddress => 'Jl. Audit Pos 404';
  @override
  String get storePhone => '08123456789';
  @override
  String generateTransactionNumber() => 'INV-QA-${DateTime.now().millisecondsSinceEpoch}';
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Forensic Return System QA Suite (18+ Scenarios)', () {
    setUp(() async {
      await DatabaseHelper.instance.openTestDatabase();
    });

    tearDown(() async {
      await DatabaseHelper.instance.closeTestDatabase();
    });

    test('Scenario 1 & 2: Full & Partial Cash Return with Good Condition + Sellable Ledger', () async {
      final now = DateTime.now();
      final shiftId = await DatabaseHelper.instance.openShift(
        ShiftModel(cashierId: 1, cashierName: 'Kasir 1', startingCash: 100000, startTime: now),
      );
      final prodId = await DatabaseHelper.instance.insertProduct(
        ProductModel(code: 'BR-1', name: 'Gula Pasir 1Kg', sellingPrice: 18000, costPrice: 15000, stock: 20),
      );
      final trxId = await DatabaseHelper.instance.insertTransaction(
        TransactionModel(
          invoiceNumber: 'INV-R-01',
          date: now,
          cashierId: 1,
          cashierName: 'Kasir 1',
          shiftId: shiftId,
          subtotal: 54000,
          grandTotal: 54000,
          paymentMethod: 'tunai',
          amountPaid: 54000,
          items: [
            TransactionItemModel(
              productId: prodId,
              productCode: 'BR-1',
              productName: 'Gula Pasir 1Kg',
              unitName: 'Pcs',
              qty: 3,
              unitPrice: 18000,
              costPrice: 15000,
              subtotal: 54000,
            ),
          ],
        ),
        shiftId: shiftId,
      );
      expect((await _prod(prodId)).stock, 17);
      expect((await DatabaseHelper.instance.getCurrentOpenShift())!.expectedCash, 154000);

      // Partial return: 1 Pcs Good Condition via Tunai
      await DatabaseHelper.instance.insertReturnOrder(
        ReturnOrderModel(
          returnNumber: 'RET-R-01',
          transactionId: trxId,
          invoiceNumber: 'INV-R-01',
          date: now,
          cashierId: 1,
          cashierName: 'Kasir 1',
          totalRefund: 18000,
          refundMethod: RefundMethods.tunai,
          items: [
            ReturnItemModel(
              productId: prodId,
              productName: 'Gula Pasir 1Kg',
              unitName: 'Pcs',
              returnQty: 1,
              refundPrice: 18000,
              costPrice: 15000,
              condition: ReturnConditions.baik,
              stockTreatment: StockTreatments.restockSellable,
            ),
          ],
        ),
        shiftId: shiftId,
      );

      expect((await _prod(prodId)).stock, 18);
      expect((await DatabaseHelper.instance.getTransactionByInvoice('INV-R-01'))!.status, 'partial_return');
      expect((await DatabaseHelper.instance.getCurrentOpenShift())!.expectedCash, 136000);

      // Second return: remaining 2 Pcs -> status becomes 'returned'
      await DatabaseHelper.instance.insertReturnOrder(
        ReturnOrderModel(
          returnNumber: 'RET-R-02',
          transactionId: trxId,
          invoiceNumber: 'INV-R-01',
          date: now,
          cashierId: 1,
          cashierName: 'Kasir 1',
          totalRefund: 36000,
          refundMethod: RefundMethods.tunai,
          items: [
            ReturnItemModel(
              productId: prodId,
              productName: 'Gula Pasir 1Kg',
              unitName: 'Pcs',
              returnQty: 2,
              refundPrice: 18000,
              costPrice: 15000,
              condition: ReturnConditions.baik,
              stockTreatment: StockTreatments.restockSellable,
            ),
          ],
        ),
        shiftId: shiftId,
      );
      expect((await _prod(prodId)).stock, 20);
      expect((await DatabaseHelper.instance.getTransactionByInvoice('INV-R-01'))!.status, 'returned');
      expect((await DatabaseHelper.instance.getCurrentOpenShift())!.expectedCash, 100000);

      final report = await DatabaseHelper.instance.getBusinessAnalyticsReport(now, now);
      expect((report['sales'] as Map)['totalRevenue'], 54000);
      expect((report['sales'] as Map)['netSales'], 0);
      expect((report['profit'] as Map)['totalHpp'], 0);
      expect((report['profit'] as Map)['grossProfit'], 0);
    });

    test('Scenario 3: Damaged return goes to damaged_stock, NOT sellable stock, and loss affects profit', () async {
      final now = DateTime.now();
      final shiftId = await DatabaseHelper.instance.openShift(
        ShiftModel(cashierId: 1, cashierName: 'Kasir', startingCash: 100000, startTime: now),
      );
      final prodId = await DatabaseHelper.instance.insertProduct(
        ProductModel(code: 'DMG-1', name: 'Telur Kemasan', sellingPrice: 30000, costPrice: 22000, stock: 10),
      );
      final trxId = await DatabaseHelper.instance.insertTransaction(
        TransactionModel(
          invoiceNumber: 'INV-DMG-1',
          date: now,
          cashierId: 1,
          cashierName: 'Kasir',
          shiftId: shiftId,
          subtotal: 30000,
          grandTotal: 30000,
          paymentMethod: 'tunai',
          amountPaid: 30000,
          items: [
            TransactionItemModel(
              productId: prodId,
              productCode: 'DMG-1',
              productName: 'Telur Kemasan',
              unitName: 'Pcs',
              qty: 1,
              unitPrice: 30000,
              costPrice: 22000,
              subtotal: 30000,
            ),
          ],
        ),
        shiftId: shiftId,
      );
      expect((await _prod(prodId)).stock, 9);

      await DatabaseHelper.instance.insertReturnOrder(
        ReturnOrderModel(
          returnNumber: 'RET-DMG-1',
          transactionId: trxId,
          invoiceNumber: 'INV-DMG-1',
          date: now,
          cashierId: 1,
          cashierName: 'Kasir',
          totalRefund: 30000,
          refundMethod: RefundMethods.tunai,
          items: [
            ReturnItemModel(
              productId: prodId,
              productName: 'Telur Kemasan',
              unitName: 'Pcs',
              returnQty: 1,
              refundPrice: 30000,
              costPrice: 22000,
              condition: ReturnConditions.rusak,
              stockTreatment: StockTreatments.damaged,
            ),
          ],
        ),
        shiftId: shiftId,
      );

      final pAfter = await _prod(prodId);
      expect(pAfter.stock, 9, reason: 'Sellable stock must NOT increase for damaged return');
      expect(pAfter.damagedStock, 1);

      final report = await DatabaseHelper.instance.getBusinessAnalyticsReport(now, now);
      expect((report['sales'] as Map)['netSales'], 0);
      expect((report['profit'] as Map)['damagedLoss'], 22000);
      expect((report['profit'] as Map)['grossProfit'], -22000);
    });

    test('Scenario 4: Quarantine bucket & releaseQuarantineStock to sellable and damaged', () async {
      final now = DateTime.now();
      final shiftId = await DatabaseHelper.instance.openShift(
        ShiftModel(cashierId: 1, cashierName: 'Kasir', startingCash: 200000, startTime: now),
      );
      final prodId = await DatabaseHelper.instance.insertProduct(
        ProductModel(code: 'QR-1', name: 'Headset BT', sellingPrice: 50000, costPrice: 30000, stock: 10),
      );
      final trxId = await DatabaseHelper.instance.insertTransaction(
        TransactionModel(
          invoiceNumber: 'INV-QR-1',
          date: now,
          cashierId: 1,
          cashierName: 'Kasir',
          shiftId: shiftId,
          subtotal: 100000,
          grandTotal: 100000,
          paymentMethod: 'tunai',
          amountPaid: 100000,
          items: [
            TransactionItemModel(
              productId: prodId,
              productCode: 'QR-1',
              productName: 'Headset BT',
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

      await DatabaseHelper.instance.insertReturnOrder(
        ReturnOrderModel(
          returnNumber: 'RET-QR-1',
          transactionId: trxId,
          invoiceNumber: 'INV-QR-1',
          date: now,
          cashierId: 1,
          cashierName: 'Kasir',
          totalRefund: 100000,
          refundMethod: RefundMethods.tunai,
          items: [
            ReturnItemModel(
              productId: prodId,
              productName: 'Headset BT',
              unitName: 'Pcs',
              returnQty: 2,
              refundPrice: 50000,
              costPrice: 30000,
              condition: ReturnConditions.perluPeriksa,
              stockTreatment: StockTreatments.quarantine,
            ),
          ],
        ),
        shiftId: shiftId,
      );

      var p = await _prod(prodId);
      expect(p.stock, 8);
      expect(p.quarantineStock, 2);

      // Release 1 to sellable, 1 to damaged
      await DatabaseHelper.instance.releaseQuarantineStock(
        productId: prodId,
        qty: 1,
        destination: 'sellable',
        userId: 1,
        userName: 'Gudang',
        note: 'Unit 1 normal',
      );
      await DatabaseHelper.instance.releaseQuarantineStock(
        productId: prodId,
        qty: 1,
        destination: 'damaged',
        userId: 1,
        userName: 'Gudang',
        note: 'Unit 2 mati total',
      );

      p = await _prod(prodId);
      expect(p.quarantineStock, 0);
      expect(p.stock, 9);
      expect(p.damagedStock, 1);

      final report = await DatabaseHelper.instance.getBusinessAnalyticsReport(now, now);
      expect((report['profit'] as Map)['hppRecovered'], 30000);
      expect((report['profit'] as Map)['damagedLoss'], 30000);
      expect((report['profit'] as Map)['grossProfit'], -30000);
    });

    test('Scenario 5 (EXACT REPORTED CASE): Minyak Goreng 41 -> Sale 1 (40) -> Tukar Barang Sama Kondisi Baik = 40', () async {
      final now = DateTime.now();
      final shiftId = await DatabaseHelper.instance.openShift(
        ShiftModel(cashierId: 1, cashierName: 'Kasir Audit', startingCash: 100000, startTime: now),
      );
      final prodId = await DatabaseHelper.instance.insertProduct(
        ProductModel(code: 'MNY-01', name: 'Minyak Goreng 1L', sellingPrice: 20000, costPrice: 16000, stock: 41),
      );
      expect((await _prod(prodId)).stock, 41);

      final trxId = await DatabaseHelper.instance.insertTransaction(
        TransactionModel(
          invoiceNumber: 'INV-MNY-01',
          date: now,
          cashierId: 1,
          cashierName: 'Kasir Audit',
          shiftId: shiftId,
          subtotal: 20000,
          grandTotal: 20000,
          paymentMethod: 'tunai',
          amountPaid: 20000,
          items: [
            TransactionItemModel(
              productId: prodId,
              productCode: 'MNY-01',
              productName: 'Minyak Goreng 1L',
              unitName: 'Pcs',
              qty: 1,
              unitPrice: 20000,
              costPrice: 16000,
              subtotal: 20000,
            ),
          ],
        ),
        shiftId: shiftId,
      );
      expect((await _prod(prodId)).stock, 40);

      await DatabaseHelper.instance.insertReturnOrder(
        ReturnOrderModel(
          returnNumber: 'RET-MNY-01',
          transactionId: trxId,
          invoiceNumber: 'INV-MNY-01',
          date: now,
          cashierId: 1,
          cashierName: 'Kasir Audit',
          totalRefund: 20000,
          refundMethod: RefundMethods.tukarBarang,
          exchangeTotal: 20000,
          differenceAmount: 0,
          items: [
            ReturnItemModel(
              productId: prodId,
              sku: 'MNY-01',
              productName: 'Minyak Goreng 1L',
              unitName: 'Pcs',
              returnQty: 1,
              refundPrice: 20000,
              costPrice: 16000,
              condition: ReturnConditions.baik,
              stockTreatment: StockTreatments.restockSellable,
            ),
          ],
          exchangeItems: [
            ReturnExchangeItemModel(
              productId: prodId,
              sku: 'MNY-01',
              productName: 'Minyak Goreng 1L',
              unitName: 'Pcs',
              qty: 1,
              unitPrice: 20000,
              costPrice: 16000,
            ),
          ],
        ),
        shiftId: shiftId,
      );

      final finalProd = await _prod(prodId);
      expect(finalProd.stock, 40, reason: '40 + 1 (return_in) - 1 (exchange_out) MUST equal 40!');
      expect((await DatabaseHelper.instance.getCurrentOpenShift())!.expectedCash, 120000);

      final movements = await DatabaseHelper.instance.getInventoryMovements(productId: prodId);
      final types = movements.map((m) => m.movementType).toList();
      expect(types, containsAll([MovementTypes.saleOut, MovementTypes.returnIn, MovementTypes.exchangeOut]));

      final returnMovs = movements.where((m) => m.referenceNumber == 'RET-MNY-01').toList();
      expect(returnMovs.length, 2);
      expect(returnMovs.any((m) => m.movementType == MovementTypes.returnIn && m.qtyDelta == 1 && m.stockAfter == 41), isTrue);
      expect(returnMovs.any((m) => m.movementType == MovementTypes.exchangeOut && m.qtyDelta == -1 && m.stockAfter == 40), isTrue);
    });

    test('Scenario 6: Exchange Same SKU with DAMAGED returned item -> sellable drops to 39, damaged becomes 1', () async {
      final now = DateTime.now();
      final shiftId = await DatabaseHelper.instance.openShift(
        ShiftModel(cashierId: 1, cashierName: 'Kasir', startingCash: 100000, startTime: now),
      );
      final prodId = await DatabaseHelper.instance.insertProduct(
        ProductModel(code: 'MNY-02', name: 'Minyak Segel Bocor', sellingPrice: 20000, costPrice: 16000, stock: 41),
      );
      final trxId = await DatabaseHelper.instance.insertTransaction(
        TransactionModel(
          invoiceNumber: 'INV-MNY-02',
          date: now,
          cashierId: 1,
          cashierName: 'Kasir',
          shiftId: shiftId,
          subtotal: 20000,
          grandTotal: 20000,
          paymentMethod: 'tunai',
          amountPaid: 20000,
          items: [
            TransactionItemModel(
              productId: prodId,
              productCode: 'MNY-02',
              productName: 'Minyak Segel Bocor',
              unitName: 'Pcs',
              qty: 1,
              unitPrice: 20000,
              costPrice: 16000,
              subtotal: 20000,
            ),
          ],
        ),
        shiftId: shiftId,
      );

      await DatabaseHelper.instance.insertReturnOrder(
        ReturnOrderModel(
          returnNumber: 'RET-MNY-02',
          transactionId: trxId,
          invoiceNumber: 'INV-MNY-02',
          date: now,
          cashierId: 1,
          cashierName: 'Kasir',
          totalRefund: 20000,
          refundMethod: RefundMethods.tukarBarang,
          items: [
            ReturnItemModel(
              productId: prodId,
              productName: 'Minyak Segel Bocor',
              unitName: 'Pcs',
              returnQty: 1,
              refundPrice: 20000,
              costPrice: 16000,
              condition: ReturnConditions.rusak,
              stockTreatment: StockTreatments.damaged,
            ),
          ],
          exchangeItems: [
            ReturnExchangeItemModel(
              productId: prodId,
              productName: 'Minyak Segel Bocor',
              unitName: 'Pcs',
              qty: 1,
              unitPrice: 20000,
              costPrice: 16000,
            ),
          ],
        ),
        shiftId: shiftId,
      );

      final p = await _prod(prodId);
      expect(p.stock, 39);
      expect(p.damagedStock, 1);

      final report = await DatabaseHelper.instance.getBusinessAnalyticsReport(now, now);
      expect((report['sales'] as Map)['netSales'], 20000);
      expect((report['profit'] as Map)['grossProfit'], -12000); // +4k sale margin - 16k damaged replacement cost
    });

    test('Scenario 7, 8 & 9: Cross-SKU Exchange (Upgrade cash/diff, Downgrade credit/cash, Out-of-stock block & rollback)', () async {
      final now = DateTime.now();
      final shiftId = await DatabaseHelper.instance.openShift(
        ShiftModel(cashierId: 1, cashierName: 'Kasir', startingCash: 100000, startTime: now),
      );
      final custId = await DatabaseHelper.instance.insertCustomer(
        CustomerModel(name: 'Siti Aminah', phone: '0811111222'),
      );
      final prodA = await DatabaseHelper.instance.insertProduct(
        ProductModel(code: 'SKU-A', name: 'Produk A 20K', sellingPrice: 20000, costPrice: 15000, stock: 10),
      );
      final prodB = await DatabaseHelper.instance.insertProduct(
        ProductModel(code: 'SKU-B', name: 'Produk B 27K', sellingPrice: 27000, costPrice: 20000, stock: 5),
      );
      final prodC = await DatabaseHelper.instance.insertProduct(
        ProductModel(code: 'SKU-C', name: 'Produk C 15K', sellingPrice: 15000, costPrice: 11000, stock: 8),
      );
      final prodEmpty = await DatabaseHelper.instance.insertProduct(
        ProductModel(code: 'SKU-0', name: 'Produk Kosong', sellingPrice: 20000, costPrice: 15000, stock: 0),
      );

      final trx1 = await DatabaseHelper.instance.insertTransaction(
        TransactionModel(
          invoiceNumber: 'INV-X-1',
          date: now,
          cashierId: 1,
          cashierName: 'Kasir',
          customerId: custId,
          customerName: 'Siti Aminah',
          shiftId: shiftId,
          subtotal: 40000,
          grandTotal: 40000,
          paymentMethod: 'tunai',
          amountPaid: 40000,
          items: [
            TransactionItemModel(
              productId: prodA,
              productCode: 'SKU-A',
              productName: 'Produk A 20K',
              unitName: 'Pcs',
              qty: 2,
              unitPrice: 20000,
              costPrice: 15000,
              subtotal: 40000,
            ),
          ],
        ),
        shiftId: shiftId,
      );

      // Scenario 9: Out of stock replacement MUST throw & roll back
      await expectLater(
        () => DatabaseHelper.instance.insertReturnOrder(
          ReturnOrderModel(
            returnNumber: 'RET-FAIL-0',
            transactionId: trx1,
            invoiceNumber: 'INV-X-1',
            date: now,
            cashierId: 1,
            cashierName: 'Kasir',
            customerId: custId,
            customerName: 'Siti Aminah',
            totalRefund: 20000,
            refundMethod: RefundMethods.tukarBarang,
            items: [
              ReturnItemModel(productId: prodA, productName: 'Produk A 20K', returnQty: 1, refundPrice: 20000, condition: ReturnConditions.baik),
            ],
            exchangeItems: [
              ReturnExchangeItemModel(productId: prodEmpty, productName: 'Produk Kosong', qty: 1, unitPrice: 20000),
            ],
          ),
          shiftId: shiftId,
        ),
        throwsStateError,
      );
      expect((await _prod(prodA)).stock, 8, reason: 'Atomic rollback must leave A at 8');

      // Scenario 7: Upgrade A (20k) -> B (27k), Siti pays +7k tunai
      await DatabaseHelper.instance.insertReturnOrder(
        ReturnOrderModel(
          returnNumber: 'RET-UPG-1',
          transactionId: trx1,
          invoiceNumber: 'INV-X-1',
          date: now,
          cashierId: 1,
          cashierName: 'Kasir',
          customerId: custId,
          customerName: 'Siti Aminah',
          totalRefund: 20000,
          refundMethod: RefundMethods.tukarBarang,
          differencePaymentMethod: RefundMethods.tunai,
          items: [
            ReturnItemModel(productId: prodA, productName: 'Produk A 20K', returnQty: 1, refundPrice: 20000, condition: ReturnConditions.baik),
          ],
          exchangeItems: [
            ReturnExchangeItemModel(productId: prodB, productName: 'Produk B 27K', qty: 1, unitPrice: 27000, costPrice: 20000),
          ],
        ),
        shiftId: shiftId,
      );
      expect((await _prod(prodA)).stock, 9);
      expect((await _prod(prodB)).stock, 4);
      expect((await DatabaseHelper.instance.getCurrentOpenShift())!.expectedCash, 147000);

      // Scenario 8: Downgrade A (20k) -> C (15k), 5k diff goes to saldo_kredit
      await DatabaseHelper.instance.insertReturnOrder(
        ReturnOrderModel(
          returnNumber: 'RET-DWN-1',
          transactionId: trx1,
          invoiceNumber: 'INV-X-1',
          date: now,
          cashierId: 1,
          cashierName: 'Kasir',
          customerId: custId,
          customerName: 'Siti Aminah',
          totalRefund: 20000,
          refundMethod: RefundMethods.tukarBarang,
          differencePaymentMethod: RefundMethods.saldoKredit,
          items: [
            ReturnItemModel(productId: prodA, productName: 'Produk A 20K', returnQty: 1, refundPrice: 20000, condition: ReturnConditions.baik),
          ],
          exchangeItems: [
            ReturnExchangeItemModel(productId: prodC, productName: 'Produk C 15K', qty: 1, unitPrice: 15000, costPrice: 11000),
          ],
        ),
        shiftId: shiftId,
      );
      expect((await _prod(prodA)).stock, 10);
      expect((await _prod(prodC)).stock, 7);
      expect(await DatabaseHelper.instance.getCustomerCreditBalance(custId), 5000);
      expect((await DatabaseHelper.instance.getCurrentOpenShift())!.expectedCash, 147000);
    });

    test('Scenario 10 & 11: Customer Credit issuance + POS partial credit redemption & Transfer/QRIS refund vs cash drawer', () async {
      final now = DateTime.now();
      final shiftId = await DatabaseHelper.instance.openShift(
        ShiftModel(cashierId: 1, cashierName: 'Kasir', startingCash: 100000, startTime: now),
      );
      final custId = await DatabaseHelper.instance.insertCustomer(
        CustomerModel(name: 'Budi Santoso', phone: '0819998887'),
      );
      final prodId = await DatabaseHelper.instance.insertProduct(
        ProductModel(code: 'KR-1', name: 'Kopi Sachet', sellingPrice: 25000, costPrice: 20000, stock: 20),
      );

      final trx1 = await DatabaseHelper.instance.insertTransaction(
        TransactionModel(
          invoiceNumber: 'INV-KR-1',
          date: now,
          cashierId: 1,
          cashierName: 'Kasir',
          customerId: custId,
          customerName: 'Budi Santoso',
          shiftId: shiftId,
          subtotal: 50000,
          grandTotal: 50000,
          paymentMethod: 'tunai',
          amountPaid: 50000,
          items: [
            TransactionItemModel(
              productId: prodId,
              productCode: 'KR-1',
              productName: 'Kopi Sachet',
              unitName: 'Pcs',
              qty: 2,
              unitPrice: 25000,
              costPrice: 20000,
              subtotal: 50000,
            ),
          ],
        ),
        shiftId: shiftId,
      );

      // Pelanggan Umum blocked from saldo_kredit
      final anonTrx = await DatabaseHelper.instance.insertTransaction(
        TransactionModel(
          invoiceNumber: 'INV-ANON',
          date: now,
          cashierId: 1,
          cashierName: 'Kasir',
          customerName: 'Pelanggan Umum',
          shiftId: shiftId,
          subtotal: 25000,
          grandTotal: 25000,
          paymentMethod: 'tunai',
          amountPaid: 25000,
          items: [
            TransactionItemModel(
              productId: prodId,
              productCode: 'KR-1',
              productName: 'Kopi Sachet',
              unitName: 'Pcs',
              qty: 1,
              unitPrice: 25000,
              costPrice: 20000,
              subtotal: 25000,
            ),
          ],
        ),
        shiftId: shiftId,
      );
      await expectLater(
        () => DatabaseHelper.instance.insertReturnOrder(
          ReturnOrderModel(
            returnNumber: 'RET-ANON-CR',
            transactionId: anonTrx,
            invoiceNumber: 'INV-ANON',
            date: now,
            cashierId: 1,
            cashierName: 'Kasir',
            totalRefund: 25000,
            refundMethod: RefundMethods.saldoKredit,
            items: [ReturnItemModel(productId: prodId, productName: 'Kopi Sachet', returnQty: 1, refundPrice: 25000)],
          ),
          shiftId: shiftId,
        ),
        throwsStateError,
      );

      // Issue 25,000 credit to Budi (drawer stays 175,000)
      await DatabaseHelper.instance.insertReturnOrder(
        ReturnOrderModel(
          returnNumber: 'RET-CR-1',
          transactionId: trx1,
          invoiceNumber: 'INV-KR-1',
          date: now,
          cashierId: 1,
          cashierName: 'Kasir',
          customerId: custId,
          customerName: 'Budi Santoso',
          totalRefund: 25000,
          refundMethod: RefundMethods.saldoKredit,
          items: [ReturnItemModel(productId: prodId, productName: 'Kopi Sachet', returnQty: 1, refundPrice: 25000)],
        ),
        shiftId: shiftId,
      );
      expect(await DatabaseHelper.instance.getCustomerCreditBalance(custId), 25000);
      expect((await DatabaseHelper.instance.getCurrentOpenShift())!.expectedCash, 175000);

      // Return remaining 1 Pcs via TRANSFER -> cash drawer STILL untouched at 175,000
      await DatabaseHelper.instance.insertReturnOrder(
        ReturnOrderModel(
          returnNumber: 'RET-TRF-1',
          transactionId: trx1,
          invoiceNumber: 'INV-KR-1',
          date: now,
          cashierId: 1,
          cashierName: 'Kasir',
          customerId: custId,
          customerName: 'Budi Santoso',
          totalRefund: 25000,
          refundMethod: RefundMethods.transfer,
          transferAccount: 'BCA',
          transferReference: 'TRF-888',
          items: [ReturnItemModel(productId: prodId, productName: 'Kopi Sachet', returnQty: 1, refundPrice: 25000)],
        ),
        shiftId: shiftId,
      );
      expect((await DatabaseHelper.instance.getCurrentOpenShift())!.expectedCash, 175000);

      // Voiding RET-CR-1 MUST succeed BEFORE credit is spent, OR let's first capture retCreditId & verify spent-credit void block below
      final retCreditRows = await DatabaseHelper.instance.getReturnOrders();
      final retCreditOrder = retCreditRows.firstWhere((r) => r.returnNumber == 'RET-CR-1');

      // Budi makes a new purchase 50,000 using 25,000 credit + 25,000 tunai
      await DatabaseHelper.instance.insertTransaction(
        TransactionModel(
          invoiceNumber: 'INV-USE-CR',
          date: now,
          cashierId: 1,
          cashierName: 'Kasir',
          customerId: custId,
          customerName: 'Budi Santoso',
          shiftId: shiftId,
          subtotal: 50000,
          grandTotal: 50000,
          paymentMethod: 'tunai',
          creditUsed: 25000,
          amountPaid: 25000,
          items: [
            TransactionItemModel(
              productId: prodId,
              productCode: 'KR-1',
              productName: 'Kopi Sachet',
              unitName: 'Pcs',
              qty: 2,
              unitPrice: 25000,
              costPrice: 20000,
              subtotal: 50000,
            ),
          ],
        ),
        shiftId: shiftId,
      );
      expect(await DatabaseHelper.instance.getCustomerCreditBalance(custId), 0);
      // Expected drawer cash = 175,000 + 25,000 (cash portion only, NOT 50,000!) = 200,000
      expect((await DatabaseHelper.instance.getCurrentOpenShift())!.expectedCash, 200000);
      expect((await DatabaseHelper.instance.getCurrentOpenShift())!.totalSalesCredit, 25000);

      final cf = await DatabaseHelper.instance.getCashFlowReport(now, now);
      expect(cf['endingCashBalance'], 200000);

      // Trying to void RET-CR-1 AFTER credit was redeemed MUST throw StateError!
      await expectLater(
        () => DatabaseHelper.instance.voidReturnOrder(
          returnOrderId: retCreditOrder.id!,
          userId: 1,
          userName: 'Owner',
          reason: 'Coba void setelah kredit terpakai',
          shiftId: shiftId,
        ),
        throwsStateError,
      );
    });

    test('Scenario 12 (Kasbon Over-Return Excess), 13 (Insufficient Cash & Service Item), 14 (Idempotency)', () async {
      final now = DateTime.now();
      final shiftId = await DatabaseHelper.instance.openShift(
        ShiftModel(cashierId: 1, cashierName: 'Kasir', startingCash: 10000, startTime: now),
      );
      final custId = await DatabaseHelper.instance.insertCustomer(
        CustomerModel(name: 'Rudi Kasbon', phone: '0817777666'),
      );
      final prodId = await DatabaseHelper.instance.insertProduct(
        ProductModel(code: 'KB-1', name: 'Roti Kaleng', sellingPrice: 25000, costPrice: 20000, stock: 10),
      );
      final svcId = await DatabaseHelper.instance.insertProduct(
        ProductModel(code: 'SV-1', name: 'Ongkos Pasang', sellingPrice: 15000, isService: true, trackStock: false, stock: 0),
      );

      // Transaction with DP 30,000 on 50,000 total (remaining kasbon = 20,000)
      final kasbonTrx = await DatabaseHelper.instance.insertTransaction(
        TransactionModel(
          invoiceNumber: 'INV-KB-EXC',
          date: now,
          cashierId: 1,
          cashierName: 'Kasir',
          customerId: custId,
          customerName: 'Rudi Kasbon',
          shiftId: shiftId,
          subtotal: 50000,
          grandTotal: 50000,
          paymentMethod: 'kasbon',
          amountPaid: 30000, // Drawer now 10k + 30k = 40k; remaining debt = 20k
          items: [
            TransactionItemModel(
              productId: prodId,
              productCode: 'KB-1',
              productName: 'Roti Kaleng',
              unitName: 'Pcs',
              qty: 2,
              unitPrice: 25000,
              costPrice: 20000,
              subtotal: 50000,
            ),
          ],
        ),
        shiftId: shiftId,
      );
      expect(await DatabaseHelper.instance.getCustomerOutstandingDebt(custId, 'Rudi Kasbon'), 20000);

      // Return 2 Pcs (50,000) with potong_piutang -> 20,000 closes debt (NEVER negative!) & 30,000 excess goes to saldo_kredit!
      final retId1 = await DatabaseHelper.instance.insertReturnOrder(
        ReturnOrderModel(
          returnNumber: 'RET-KB-1',
          transactionId: kasbonTrx,
          invoiceNumber: 'INV-KB-EXC',
          date: now,
          cashierId: 1,
          cashierName: 'Kasir',
          customerId: custId,
          customerName: 'Rudi Kasbon',
          totalRefund: 50000,
          refundMethod: RefundMethods.potongPiutang,
          differencePaymentMethod: RefundMethods.saldoKredit,
          idempotencyKey: 'idem-kb-001',
          items: [
            ReturnItemModel(productId: prodId, productName: 'Roti Kaleng', returnQty: 2, refundPrice: 25000, condition: ReturnConditions.baik),
          ],
        ),
        shiftId: shiftId,
      );
      expect(await DatabaseHelper.instance.getCustomerOutstandingDebt(custId, 'Rudi Kasbon'), 0);
      expect(await DatabaseHelper.instance.getCustomerCreditBalance(custId), 30000);

      // Scenario 14: Same idempotencyKey MUST return same retId1 without mutating anything!
      final retIdDup = await DatabaseHelper.instance.insertReturnOrder(
        ReturnOrderModel(
          returnNumber: 'RET-KB-DUP',
          transactionId: kasbonTrx,
          invoiceNumber: 'INV-KB-EXC',
          date: now,
          cashierId: 1,
          cashierName: 'Kasir',
          customerId: custId,
          customerName: 'Rudi Kasbon',
          totalRefund: 50000,
          refundMethod: RefundMethods.potongPiutang,
          idempotencyKey: 'idem-kb-001',
          items: [
            ReturnItemModel(productId: prodId, productName: 'Roti Kaleng', returnQty: 2, refundPrice: 25000, condition: ReturnConditions.baik),
          ],
        ),
        shiftId: shiftId,
      );
      expect(retIdDup, retId1);
      expect(await DatabaseHelper.instance.getCustomerCreditBalance(custId), 30000);
      expect((await _prod(prodId)).stock, 10);

      // Scenario 13: Service item refund & cash drawer check (drawer has 40k; refund 50k cash throws StateError, refund 15k service succeeds with 0 stock change!)
      final svcTrx = await DatabaseHelper.instance.insertTransaction(
        TransactionModel(
          invoiceNumber: 'INV-SVC-1',
          date: now,
          cashierId: 1,
          cashierName: 'Kasir',
          shiftId: shiftId,
          subtotal: 15000,
          grandTotal: 15000,
          paymentMethod: 'qris',
          amountPaid: 15000,
          items: [
            TransactionItemModel(
              productId: svcId,
              productCode: 'SV-1',
              productName: 'Ongkos Pasang',
              unitName: 'Jasa',
              qty: 1,
              unitPrice: 15000,
              subtotal: 15000,
              isService: true,
            ),
          ],
        ),
        shiftId: shiftId,
      );

      // Attempt cash refund 50k > 40k expected cash -> blocked
      await expectLater(
        () => DatabaseHelper.instance.insertReturnOrder(
          ReturnOrderModel(
            returnNumber: 'RET-CASH-ERR',
            transactionId: svcTrx,
            invoiceNumber: 'INV-SVC-1',
            date: now,
            cashierId: 1,
            cashierName: 'Kasir',
            totalRefund: 50000,
            refundMethod: RefundMethods.tunai,
            items: [
              ReturnItemModel(productId: svcId, productName: 'Ongkos Pasang', unitName: 'Jasa', returnQty: 1, refundPrice: 50000),
            ],
          ),
          shiftId: shiftId,
        ),
        throwsStateError,
      );

      // Valid service return 15k cash -> stock stays 0, ledger records no_stock_change
      await DatabaseHelper.instance.insertReturnOrder(
        ReturnOrderModel(
          returnNumber: 'RET-SVC-OK',
          transactionId: svcTrx,
          invoiceNumber: 'INV-SVC-1',
          date: now,
          cashierId: 1,
          cashierName: 'Kasir',
          totalRefund: 15000,
          refundMethod: RefundMethods.tunai,
          items: [
            ReturnItemModel(
              productId: svcId,
              productName: 'Ongkos Pasang',
              unitName: 'Jasa',
              returnQty: 1,
              refundPrice: 15000,
              condition: ReturnConditions.baik,
              stockTreatment: StockTreatments.noStockChange,
            ),
          ],
        ),
        shiftId: shiftId,
      );
      expect((await _prod(svcId)).stock, 0);
      final svcMovs = await DatabaseHelper.instance.getInventoryMovements(productId: svcId);
      expect(svcMovs.any((m) => m.movementType == MovementTypes.noStockChange && m.qtyDelta == 0), isTrue);
    });

    test('Scenario 15: Historical price retention when discounts/tax apply and catalog price increases later', () async {
      final now = DateTime.now();
      final shiftId = await DatabaseHelper.instance.openShift(
        ShiftModel(cashierId: 1, cashierName: 'Kasir', startingCash: 100000, startTime: now),
      );
      final prodId = await DatabaseHelper.instance.insertProduct(
        ProductModel(code: 'PRC-1', name: 'Minyak Sawit', sellingPrice: 50000, costPrice: 35000, stock: 10),
      );
      // Bought 2 pcs @ 50,000 = 100,000 subtotal, minus 10,000 cart discount -> 90,000 + 9,000 tax (10%) = 99,000 grandTotal
      final trxId = await DatabaseHelper.instance.insertTransaction(
        TransactionModel(
          invoiceNumber: 'INV-DISC-1',
          date: now,
          cashierId: 1,
          cashierName: 'Kasir',
          shiftId: shiftId,
          subtotal: 100000,
          discountTotal: 10000,
          taxAmount: 9000,
          grandTotal: 99000,
          paymentMethod: 'tunai',
          amountPaid: 100000,
          changeAmount: 1000,
          items: [
            TransactionItemModel(
              productId: prodId,
              productCode: 'PRC-1',
              productName: 'Minyak Sawit',
              unitName: 'Pcs',
              qty: 2,
              unitPrice: 50000,
              costPrice: 35000,
              subtotal: 100000,
            ),
          ],
        ),
        shiftId: shiftId,
      );

      // Update catalog price to 65,000 AFTER sale!
      final updatedProd = (await _prod(prodId)).copyWith(sellingPrice: 65000);
      await DatabaseHelper.instance.updateProduct(updatedProd);

      final savedTrx = await DatabaseHelper.instance.getTransactionByInvoice('INV-DISC-1');
      final effPrice = DatabaseHelper.effectiveUnitPriceForReturn(savedTrx!, savedTrx.items.first);
      expect(effPrice, 49500, reason: 'Must return proportional paid amount (99,000 / 2 = 49,500), NOT new 65,000!');
      expect(savedTrx.id, trxId);
    });

    test('Scenario 16 & 17: Void Return Order atomic reversal (stock, exchange, cash, credit, status) & post-void safety', () async {
      final now = DateTime.now();
      final shiftId = await DatabaseHelper.instance.openShift(
        ShiftModel(cashierId: 1, cashierName: 'Kasir', startingCash: 100000, startTime: now),
      );
      final custId = await DatabaseHelper.instance.insertCustomer(
        CustomerModel(name: 'Dewi Void', phone: '081333444'),
      );
      final prodA = await DatabaseHelper.instance.insertProduct(
        ProductModel(code: 'VD-A', name: 'Sabun Cair', sellingPrice: 20000, costPrice: 14000, stock: 10),
      );
      final prodB = await DatabaseHelper.instance.insertProduct(
        ProductModel(code: 'VD-B', name: 'Shampo Botol', sellingPrice: 25000, costPrice: 18000, stock: 10),
      );

      final trxId = await DatabaseHelper.instance.insertTransaction(
        TransactionModel(
          invoiceNumber: 'INV-VD-1',
          date: now,
          cashierId: 1,
          cashierName: 'Kasir',
          customerId: custId,
          customerName: 'Dewi Void',
          shiftId: shiftId,
          subtotal: 20000,
          grandTotal: 20000,
          paymentMethod: 'tunai',
          amountPaid: 20000,
          items: [
            TransactionItemModel(
              productId: prodA,
              productCode: 'VD-A',
              productName: 'Sabun Cair',
              unitName: 'Pcs',
              qty: 1,
              unitPrice: 20000,
              costPrice: 14000,
              subtotal: 20000,
            ),
          ],
        ),
        shiftId: shiftId,
      );

      // Exchange 1 Sabun (20k) -> 1 Shampo (25k), +5k tunai paid
      final retId = await DatabaseHelper.instance.insertReturnOrder(
        ReturnOrderModel(
          returnNumber: 'RET-VD-1',
          transactionId: trxId,
          invoiceNumber: 'INV-VD-1',
          date: now,
          cashierId: 1,
          cashierName: 'Kasir',
          customerId: custId,
          customerName: 'Dewi Void',
          totalRefund: 20000,
          refundMethod: RefundMethods.tukarBarang,
          differencePaymentMethod: RefundMethods.tunai,
          items: [
            ReturnItemModel(productId: prodA, productName: 'Sabun Cair', returnQty: 1, refundPrice: 20000, condition: ReturnConditions.baik),
          ],
          exchangeItems: [
            ReturnExchangeItemModel(productId: prodB, productName: 'Shampo Botol', qty: 1, unitPrice: 25000),
          ],
        ),
        shiftId: shiftId,
      );
      expect((await _prod(prodA)).stock, 10); // 10 - 1 + 1 = 10
      expect((await _prod(prodB)).stock, 9);
      expect((await DatabaseHelper.instance.getCurrentOpenShift())!.expectedCash, 125000);
      expect((await DatabaseHelper.instance.getTransactionByInvoice('INV-VD-1'))!.status, 'returned');

      // Void that return order -> A becomes 9, B returns to 10, cash drops to 120,000, tx becomes 'completed'!
      await DatabaseHelper.instance.voidReturnOrder(
        returnOrderId: retId,
        userId: 1,
        userName: 'Owner',
        reason: 'Salah nota yang diretur',
        shiftId: shiftId,
      );

      expect((await _prod(prodA)).stock, 9);
      expect((await _prod(prodB)).stock, 10);
      expect((await DatabaseHelper.instance.getCurrentOpenShift())!.expectedCash, 120000);
      expect((await DatabaseHelper.instance.getTransactionByInvoice('INV-VD-1'))!.status, 'completed');
      expect((await DatabaseHelper.instance.getReturnOrderById(retId))!.isVoided, isTrue);

      // Double void must be blocked!
      await expectLater(
        () => DatabaseHelper.instance.voidReturnOrder(
          returnOrderId: retId,
          userId: 1,
          userName: 'Owner',
          reason: 'Coba void dua kali',
          shiftId: shiftId,
        ),
        throwsStateError,
      );

      // Now voidTransaction on original trx MUST restore that 1 Sabun Cair back to 10 (since return was voided)!
      await DatabaseHelper.instance.voidTransaction(trxId, shiftId: shiftId);
      expect((await _prod(prodA)).stock, 10);
    });

    test('Scenario 18: Legacy v3 -> v4 Migration safety & Legacy Return Reconciliation audit check', () async {
      await DatabaseHelper.instance.closeTestDatabase();
      final dbDir = await databaseFactoryFfi.getDatabasesPath();
      final legacyPath = '$dbDir/legacy_v3_return_audit.db';
      final f = File(legacyPath);
      if (await f.exists()) await f.delete();

      // Create pure v3 schema containing problematic legacy 'tukar_barang' return (no exchange items)
      final legacyDb = await openDatabase(
        legacyPath,
        version: 3,
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE products (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              code TEXT UNIQUE NOT NULL,
              name TEXT NOT NULL,
              category TEXT DEFAULT 'Umum',
              barcode TEXT,
              is_service INTEGER DEFAULT 0,
              track_stock INTEGER DEFAULT 1,
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
          await db.execute('CREATE TABLE customers (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, phone TEXT, address TEXT, email TEXT, notes TEXT, points INTEGER DEFAULT 0, created_at TEXT)');
          await db.execute('CREATE TABLE transactions (id INTEGER PRIMARY KEY AUTOINCREMENT, invoice_number TEXT UNIQUE NOT NULL, date TEXT NOT NULL, cashier_id INTEGER, cashier_name TEXT, customer_id INTEGER, shift_id INTEGER, customer_name TEXT, customer_phone TEXT, subtotal REAL, discount_total REAL DEFAULT 0, tax_amount REAL DEFAULT 0, promo_name TEXT DEFAULT "", grand_total REAL NOT NULL, payment_method TEXT NOT NULL, amount_paid REAL NOT NULL, change_amount REAL DEFAULT 0, status TEXT DEFAULT "returned", qr_code_payload TEXT, note TEXT, printer_snapshot_json TEXT)');
          await db.execute('CREATE TABLE transaction_items (id INTEGER PRIMARY KEY AUTOINCREMENT, transaction_id INTEGER, product_id INTEGER, product_code TEXT, product_name TEXT, unit_name TEXT, conversion_factor REAL DEFAULT 1, qty REAL, unit_price REAL, discount REAL DEFAULT 0, subtotal REAL, cost_price REAL DEFAULT 0, is_service INTEGER DEFAULT 0)');
          await db.execute('CREATE TABLE shifts (id INTEGER PRIMARY KEY AUTOINCREMENT, cashier_id INTEGER, cashier_name TEXT, start_time TEXT NOT NULL, end_time TEXT, starting_cash REAL DEFAULT 0, total_sales_cash REAL DEFAULT 0, total_sales_qris REAL DEFAULT 0, total_sales_transfer REAL DEFAULT 0, total_sales_kasbon REAL DEFAULT 0, total_cash_in REAL DEFAULT 0, total_cash_out REAL DEFAULT 0, total_return_cash REAL DEFAULT 0, actual_cash REAL, difference REAL, status TEXT DEFAULT "open", note TEXT)');
          await db.execute('CREATE TABLE return_orders (id INTEGER PRIMARY KEY AUTOINCREMENT, return_number TEXT UNIQUE NOT NULL, transaction_id INTEGER NOT NULL, invoice_number TEXT NOT NULL, date TEXT NOT NULL, cashier_id INTEGER, cashier_name TEXT, total_refund REAL NOT NULL, refund_method TEXT NOT NULL, note TEXT)');
          await db.execute('CREATE TABLE return_items (id INTEGER PRIMARY KEY AUTOINCREMENT, return_order_id INTEGER NOT NULL, product_id INTEGER, product_name TEXT, unit_name TEXT, conversion_factor REAL DEFAULT 1, return_qty REAL, refund_price REAL, subtotal REAL, condition TEXT DEFAULT "baik")');

          final pid = await db.insert('products', {'code': 'LEG-MNY', 'name': 'Minyak V3', 'selling_price': 20000, 'stock': 41});
          final tid = await db.insert('transactions', {
            'invoice_number': 'INV-LEG-1',
            'date': '2026-11-24T10:00:00',
            'cashier_id': 1,
            'cashier_name': 'Kasir V3',
            'customer_name': 'Pelanggan Umum',
            'subtotal': 20000,
            'grand_total': 20000,
            'payment_method': 'tunai',
            'amount_paid': 20000,
            'status': 'returned',
          });
          final rid = await db.insert('return_orders', {
            'return_number': 'RET-LEG-1',
            'transaction_id': tid,
            'invoice_number': 'INV-LEG-1',
            'date': '2026-11-24T11:00:00',
            'cashier_id': 1,
            'cashier_name': 'Kasir V3',
            'total_refund': 20000,
            'refund_method': 'tukar_barang',
            'note': 'Tukar barang V3',
          });
          await db.insert('return_items', {
            'return_order_id': rid,
            'product_id': pid,
            'product_name': 'Minyak V3',
            'unit_name': 'Pcs',
            'return_qty': 1,
            'refund_price': 20000,
            'subtotal': 20000,
            'condition': 'baik',
          });
        },
      );
      await legacyDb.close();

      await DatabaseHelper.instance.openTestDatabase(path: legacyPath, deleteIfExists: false);

      // Verify historical stock untouched (non-destructive) & legacy tukar anomaly surfaced cleanly
      final prods = await DatabaseHelper.instance.getProducts();
      expect(prods.firstWhere((p) => p.code == 'LEG-MNY').stock, 41);

      final findings = await DatabaseHelper.instance.getLegacyReturnReconciliationReport();
      expect(findings.length, 1);
      expect(findings.first['returnNumber'], 'RET-LEG-1');
      expect(findings.first['severity'], 'HIGH');
      expect(findings.first['issueType'], 'legacy_tukar_tanpa_keluar');
    });
  });

  group('UI Widget & Responsive Tests (ReturnScreen & PaymentDialog)', () {
    setUp(() async {
      await DatabaseHelper.instance.openTestDatabase();
    });

    tearDown(() async {
      await DatabaseHelper.instance.closeTestDatabase();
    });

    testWidgets('ReturnScreen renders cleanly with zero overflow across phone (360x640) & tablet (1280x800)', (tester) async {
      final authProv = _QaAuthProvider();
      final cashFlowProv = CashFlowProvider();
      final customerProv = CustomerProvider();
      final debtProv = DebtProvider();
      final productProv = ProductProvider();
      final settingsProv = _QaSettingsProvider();

      await tester.runAsync(() async {
        await cashFlowProv.checkOpenShift();
        await customerProv.loadCustomers();
        await productProv.loadProducts();
      });

      for (final size in const [Size(360, 640), Size(1280, 800)]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<AuthProvider>.value(value: authProv),
              ChangeNotifierProvider<CashFlowProvider>.value(value: cashFlowProv),
              ChangeNotifierProvider<CustomerProvider>.value(value: customerProv),
              ChangeNotifierProvider<DebtProvider>.value(value: debtProv),
              ChangeNotifierProvider<ProductProvider>.value(value: productProv),
              ChangeNotifierProvider<SettingsProvider>.value(value: settingsProv),
            ],
            child: MaterialApp(
              theme: AppTheme.lightTheme,
              home: const ReturnScreen(),
            ),
          ),
        );
        await tester.pump();
        await tester.runAsync(() async {
          await Future.delayed(const Duration(milliseconds: 400));
        });
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(find.text('Retur & Tukar Barang'), findsOneWidget);
        expect(find.textContaining('Proses Retur'), findsOneWidget);
        expect(find.textContaining('Riwayat Retur'), findsOneWidget);
        expect(find.textContaining('Karantina & Mutasi'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 100)));
      addTearDown(() => tester.view.resetPhysicalSize());
    });

    testWidgets('PaymentDialog loads & allows toggling registered customer saldo_kredit without overflow', (tester) async {
      late int custId;
      await tester.runAsync(() async {
        final now = DateTime.now();
        final shiftId = await DatabaseHelper.instance.openShift(
          ShiftModel(cashierId: 1, cashierName: 'Kasir', startingCash: 100000, startTime: now),
        );
        custId = await DatabaseHelper.instance.insertCustomer(
          CustomerModel(name: 'Pelanggan Kredit UI', phone: '081234000'),
        );
        final prodId = await DatabaseHelper.instance.insertProduct(
          ProductModel(code: 'UI-P1', name: 'Teh Botol', sellingPrice: 25000, costPrice: 18000, stock: 10),
        );
        final trxId = await DatabaseHelper.instance.insertTransaction(
          TransactionModel(
            invoiceNumber: 'INV-UI-CR',
            date: now,
            cashierId: 1,
            cashierName: 'Kasir',
            customerId: custId,
            customerName: 'Pelanggan Kredit UI',
            shiftId: shiftId,
            subtotal: 25000,
            grandTotal: 25000,
            paymentMethod: 'tunai',
            amountPaid: 25000,
            items: [
              TransactionItemModel(
                productId: prodId,
                productCode: 'UI-P1',
                productName: 'Teh Botol',
                unitName: 'Pcs',
                qty: 1,
                unitPrice: 25000,
                costPrice: 18000,
                subtotal: 25000,
              ),
            ],
          ),
          shiftId: shiftId,
        );
        await DatabaseHelper.instance.insertReturnOrder(
          ReturnOrderModel(
            returnNumber: 'RET-UI-CR',
            transactionId: trxId,
            invoiceNumber: 'INV-UI-CR',
            date: now,
            cashierId: 1,
            cashierName: 'Kasir',
            customerId: custId,
            customerName: 'Pelanggan Kredit UI',
            totalRefund: 25000,
            refundMethod: RefundMethods.saldoKredit,
            items: [
              ReturnItemModel(productId: prodId, productName: 'Teh Botol', returnQty: 1, refundPrice: 25000),
            ],
          ),
          shiftId: shiftId,
        );
      });

      final pos = PosProvider();
      pos.addProduct(ProductModel(id: 1, code: 'UI-P1', name: 'Teh Botol', sellingPrice: 50000, stock: 10));
      pos.setCustomerInfo('Pelanggan Kredit UI', '081234000', customerId: custId);
      final cashFlow = CashFlowProvider();
      final custProv = CustomerProvider();
      final debtProv = DebtProvider();
      final prodProv = ProductProvider();
      final printerProv = PrinterProvider();
      await tester.runAsync(() async {
        await cashFlow.checkOpenShift();
        await custProv.loadCustomers();
      });

      tester.view.physicalSize = const Size(400, 720);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: _QaAuthProvider()),
            ChangeNotifierProvider<PosProvider>.value(value: pos),
            ChangeNotifierProvider<CashFlowProvider>.value(value: cashFlow),
            ChangeNotifierProvider<CustomerProvider>.value(value: custProv),
            ChangeNotifierProvider<DebtProvider>.value(value: debtProv),
            ChangeNotifierProvider<ProductProvider>.value(value: prodProv),
            ChangeNotifierProvider<SettingsProvider>.value(value: _QaSettingsProvider()),
            ChangeNotifierProvider<PrinterProvider>.value(value: printerProv),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const Scaffold(body: PaymentDialog()),
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 400)));
      await tester.pumpAndSettle();

      expect(find.text('Gunakan Saldo Kredit Retur Pelanggan'), findsOneWidget);
      await tester.tap(find.text('Gunakan Saldo Kredit Retur Pelanggan'));
      await tester.pumpAndSettle();
      expect(find.text('Potong Saldo Kredit Retur:'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 100)));
      addTearDown(() => tester.view.resetPhysicalSize());
    });
  });
}
