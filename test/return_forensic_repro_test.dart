import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:kasirtoko/database/db_helper.dart';
import 'package:kasirtoko/models/inventory_movement.dart';
import 'package:kasirtoko/models/product.dart';
import 'package:kasirtoko/models/return_exchange_item.dart';
import 'package:kasirtoko/models/return_item.dart';
import 'package:kasirtoko/models/return_order.dart';
import 'package:kasirtoko/models/shift.dart';
import 'package:kasirtoko/models/transaction.dart';
import 'package:kasirtoko/models/transaction_item.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  setUp(() async {
    await DatabaseHelper.instance.openTestDatabase();
  });

  tearDown(() async {
    await DatabaseHelper.instance.closeTestDatabase();
  });

  test('REGRESSION GUARD: Minyak Goreng 41 -> Sale 1 (40) -> Empty exchange blocked & Full Exchange keeps Stock 40', () async {
    final now = DateTime.now();
    final shiftId = await DatabaseHelper.instance.openShift(
      ShiftModel(cashierId: 1, cashierName: 'Kasir Audit', startingCash: 100000, startTime: now),
    );

    final productId = await DatabaseHelper.instance.insertProduct(
      ProductModel(
        code: 'MNY-01',
        name: 'Minyak Goreng 1L',
        sellingPrice: 20000,
        costPrice: 16000,
        stock: 41,
      ),
    );

    final trxId = await DatabaseHelper.instance.insertTransaction(
      TransactionModel(
        invoiceNumber: 'INV-AUDIT-FIX',
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
            productId: productId,
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

    final pAfterSale = (await DatabaseHelper.instance.getProducts()).firstWhere((p) => p.id == productId);
    expect(pAfterSale.stock, 40);

    // 1. Old buggy pattern (tukar_barang without replacement items) MUST be rejected cleanly!
    await expectLater(
      () => DatabaseHelper.instance.insertReturnOrder(
        ReturnOrderModel(
          returnNumber: 'RET-NO-EX',
          transactionId: trxId,
          invoiceNumber: 'INV-AUDIT-FIX',
          date: now,
          cashierId: 1,
          cashierName: 'Kasir Audit',
          totalRefund: 20000,
          refundMethod: RefundMethods.tukarBarang,
          items: [
            ReturnItemModel(
              productId: productId,
              productName: 'Minyak Goreng 1L',
              unitName: 'Pcs',
              returnQty: 1,
              refundPrice: 20000,
              condition: ReturnConditions.baik,
            ),
          ],
        ),
        shiftId: shiftId,
      ),
      throwsStateError,
    );
    expect((await DatabaseHelper.instance.getProducts()).firstWhere((p) => p.id == productId).stock, 40);

    // 2. Proper exchange (return_in +1 & exchange_out -1) yields net 40!
    await DatabaseHelper.instance.insertReturnOrder(
      ReturnOrderModel(
        returnNumber: 'RET-AUDIT-FIX',
        transactionId: trxId,
        invoiceNumber: 'INV-AUDIT-FIX',
        date: now,
        cashierId: 1,
        cashierName: 'Kasir Audit',
        totalRefund: 20000,
        refundMethod: RefundMethods.tukarBarang,
        items: [
          ReturnItemModel(
            productId: productId,
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
            productId: productId,
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

    final pAfterReturn = (await DatabaseHelper.instance.getProducts()).firstWhere((p) => p.id == productId);
    expect(pAfterReturn.stock, 40);

    final movs = await DatabaseHelper.instance.getInventoryMovements(productId: productId);
    expect(movs.any((m) => m.movementType == MovementTypes.returnIn && m.qtyDelta == 1), isTrue);
    expect(movs.any((m) => m.movementType == MovementTypes.exchangeOut && m.qtyDelta == -1), isTrue);
  });
}
