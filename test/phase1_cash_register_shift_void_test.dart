import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:kasirtoko/database/db_helper.dart';
import 'package:kasirtoko/models/cash_register.dart';
import 'package:kasirtoko/models/product.dart';
import 'package:kasirtoko/models/shift.dart';
import 'package:kasirtoko/models/transaction.dart';
import 'package:kasirtoko/models/transaction_item.dart';
import 'package:kasirtoko/models/transaction_void.dart';
import 'package:kasirtoko/utils/date_format.dart';
import 'package:kasirtoko/utils/security_helper.dart';

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await DateHelper.ensureInitialized();
  });

  setUp(() async {
    final dbDir = await databaseFactoryFfi.getDatabasesPath();
    SecurityHelper.configureForTesting(
      pepperProvider: InMemoryPepperProvider(Uint8List.fromList(List.filled(32, 13))),
      iterations: 50000,
    );
    await DatabaseHelper.instance.openTestDatabase(path: '$dbDir/phase1_shift_void_test.db');
  });

  tearDown(() async {
    SecurityHelper.resetTestConfiguration();
    await DatabaseHelper.instance.closeTestDatabase();
  });

  group('Phase 1 — Cash Register Assignments, Shared/Individual Shifts, Idempotency & Closed-Shift Void', () {
    test('SHARED_DRAWER: multi-cashier transactions share single register shift without losing identity or stats on close', () async {
      final db = await DatabaseHelper.instance.database;
      expect(await DatabaseHelper.instance.getDrawerMode(), DrawerMode.sharedDrawer);

      final users = await DatabaseHelper.instance.getUsers();
      final owner = users.firstWhere((u) => u.username == 'owner');
      final kasir = users.firstWhere((u) => u.username == 'kasir');
      final supervisor = users.firstWhere((u) => u.username == 'supervisor');

      final prodId = await DatabaseHelper.instance.insertProduct(
        ProductModel(code: 'SH-1', name: 'Kabel Data', sellingPrice: 25000, costPrice: 15000, stock: 20),
      );

      final now = DateTime.now();
      final sharedShiftId = await DatabaseHelper.instance.openShift(
        ShiftModel(
          cashierId: owner.id!,
          cashierName: owner.name,
          terminalId: 'ADMIN',
          cashRegisterId: 1,
          startTime: now,
          startingCash: 100000,
        ),
      );

      // Opening a second concurrent shift on REG-MAIN must be rejected
      await expectLater(
        () => DatabaseHelper.instance.openShift(
          ShiftModel(
            cashierId: kasir.id!,
            cashierName: kasir.name,
            terminalId: 'STAFF-01',
            cashRegisterId: 1,
            startTime: now,
            startingCash: 50000,
          ),
        ),
        throwsStateError,
      );

      // Multiple cashiers/terminals transact into the SAME shared store shift
      final tx1 = await DatabaseHelper.instance.insertTransaction(
        TransactionModel(
          invoiceNumber: 'INV-SH-1',
          date: now,
          cashierId: kasir.id!,
          cashierName: kasir.name,
          terminalId: 'STAFF-01',
          cashRegisterId: 1,
          idempotencyKey: 'STAFF-01-REQ-1',
          subtotal: 25000,
          grandTotal: 25000,
          paymentMethod: 'tunai',
          amountPaid: 25000,
          items: [
            TransactionItemModel(
              productId: prodId,
              productCode: 'SH-1',
              productName: 'Kabel Data',
              unitName: 'Pcs',
              qty: 1,
              unitPrice: 25000,
              costPrice: 15000,
              subtotal: 25000,
            ),
          ],
        ),
        shiftId: sharedShiftId,
      );
      final tx2 = await DatabaseHelper.instance.insertTransaction(
        TransactionModel(
          invoiceNumber: 'INV-SH-2',
          date: now,
          cashierId: supervisor.id!,
          cashierName: supervisor.name,
          terminalId: 'STAFF-02',
          cashRegisterId: 1,
          idempotencyKey: 'STAFF-02-REQ-1',
          subtotal: 50000,
          grandTotal: 50000,
          paymentMethod: 'qris',
          amountPaid: 50000,
          items: [
            TransactionItemModel(
              productId: prodId,
              productCode: 'SH-1',
              productName: 'Kabel Data',
              unitName: 'Pcs',
              qty: 2,
              unitPrice: 25000,
              costPrice: 15000,
              subtotal: 50000,
            ),
          ],
        ),
        shiftId: sharedShiftId,
      );
      expect(tx2, greaterThan(tx1));

      // Retried checkout with SAME idempotency_key returns existing ID without double-charging!
      final retriedTx1 = await DatabaseHelper.instance.insertTransaction(
        TransactionModel(
          invoiceNumber: 'INV-SH-1-RETRY',
          date: now,
          cashierId: kasir.id!,
          cashierName: kasir.name,
          terminalId: 'STAFF-01',
          cashRegisterId: 1,
          idempotencyKey: 'STAFF-01-REQ-1',
          subtotal: 25000,
          grandTotal: 25000,
          paymentMethod: 'tunai',
          amountPaid: 25000,
          items: [
            TransactionItemModel(
              productId: prodId,
              productCode: 'SH-1',
              productName: 'Kabel Data',
              unitName: 'Pcs',
              qty: 1,
              unitPrice: 25000,
              costPrice: 15000,
              subtotal: 25000,
            ),
          ],
        ),
        shiftId: sharedShiftId,
      );
      expect(retriedTx1, tx1);

      // Stock deducted only 3 total (1 + 2), NOT 4
      final prodRows = await db.query('products', where: 'id = ?', whereArgs: [prodId]);
      expect((prodRows.first['stock'] as num).toDouble(), 17.0);

      // Close shared shift and confirm per-cashier attribution preserved
      await DatabaseHelper.instance.closeShift(sharedShiftId, 125000, 0, '');
      final closedRows = await db.query('shifts', where: 'id = ?', whereArgs: [sharedShiftId]);
      final closedShift = ShiftModel.fromMap(closedRows.first);
      expect(closedShift.status, 'closed');
      expect(closedShift.expectedCash, 125000);
      expect(closedShift.totalSalesQris, 50000);

      final savedTx1 = await DatabaseHelper.instance.getTransactionByInvoice('INV-SH-1');
      final savedTx2 = await DatabaseHelper.instance.getTransactionByInvoice('INV-SH-2');
      expect(savedTx1!.cashierId, kasir.id);
      expect(savedTx1.terminalId, 'STAFF-01');
      expect(savedTx1.shiftId, sharedShiftId);
      expect(savedTx2!.cashierId, supervisor.id);
      expect(savedTx2.terminalId, 'STAFF-02');
      expect(savedTx2.shiftId, sharedShiftId);

      final stats = await DatabaseHelper.instance.getShiftStats(closedShift);
      expect(stats['totalTransactions'], 2);
      expect(stats['totalGrossProfit'], 30000.0); // 3 * (25k - 15k)
    });

    test('INDIVIDUAL_DRAWER & Assignments: deterministic precedence, conflict rejection, parallel shifts & stat isolation', () async {
      final db = await DatabaseHelper.instance.database;
      final users = await DatabaseHelper.instance.getUsers();
      final owner = users.firstWhere((u) => u.username == 'owner');
      final kasir = users.firstWhere((u) => u.username == 'kasir');
      final supervisor = users.firstWhere((u) => u.username == 'supervisor');

      final reg2Id = await DatabaseHelper.instance.insertCashRegister(
        CashRegisterModel(registerCode: 'REG-02', name: 'Laci Staff Kasir'),
      );
      final reg3Id = await DatabaseHelper.instance.insertCashRegister(
        CashRegisterModel(registerCode: 'REG-03', name: 'Laci Supervisor'),
      );

      // Precedence test: terminal+cashier > cashier > terminal
      await DatabaseHelper.instance.saveCashRegisterAssignment(
        CashRegisterAssignmentModel(
          cashRegisterId: 1,
          terminalId: 'STAFF-01',
          priority: 100, // Even high priority terminal-only rule must yield to higher specificity cashier rule!
        ),
      );
      await DatabaseHelper.instance.saveCashRegisterAssignment(
        CashRegisterAssignmentModel(
          cashRegisterId: reg2Id,
          cashierId: kasir.id,
          priority: 1,
        ),
      );
      final resolvedByCashier = await DatabaseHelper.instance.resolveAuthorizedCashRegister(
        cashierId: kasir.id!,
        terminalId: 'STAFF-01',
      );
      expect(resolvedByCashier.id, reg2Id);

      // Exact (terminal_id + cashier_id) overrides cashier-only rule!
      final exactAssignId = await DatabaseHelper.instance.saveCashRegisterAssignment(
        CashRegisterAssignmentModel(
          cashRegisterId: reg3Id,
          terminalId: 'STAFF-02',
          cashierId: kasir.id,
          priority: 1,
        ),
      );
      final resolvedByCombo = await DatabaseHelper.instance.resolveAuthorizedCashRegister(
        cashierId: kasir.id!,
        terminalId: 'STAFF-02',
      );
      expect(resolvedByCombo.id, reg3Id);
      await DatabaseHelper.instance.deleteCashRegisterAssignment(exactAssignId);

      // Conflicting equal-specificity + equal-priority assignments MUST be rejected rather than guessing!
      final conflictId = await DatabaseHelper.instance.saveCashRegisterAssignment(
        CashRegisterAssignmentModel(
          cashRegisterId: reg3Id,
          cashierId: kasir.id,
          priority: 1,
        ),
      );
      await expectLater(
        () => DatabaseHelper.instance.resolveAuthorizedCashRegister(
          cashierId: kasir.id!,
          terminalId: 'STAFF-01',
        ),
        throwsStateError,
      );
      await DatabaseHelper.instance.deleteCashRegisterAssignment(conflictId);

      // Assign supervisor -> REG-03 on STAFF-02
      await DatabaseHelper.instance.saveCashRegisterAssignment(
        CashRegisterAssignmentModel(
          cashRegisterId: reg3Id,
          terminalId: 'STAFF-02',
          cashierId: supervisor.id,
          priority: 10,
        ),
      );

      await DatabaseHelper.instance.setDrawerMode(DrawerMode.individualDrawer, actor: owner);

      final prodId = await DatabaseHelper.instance.insertProduct(
        ProductModel(code: 'IND-1', name: 'Powerbank', sellingPrice: 100000, costPrice: 70000, stock: 20),
      );
      final now = DateTime.now();

      // Orphan pre-existing null-shift transaction inside same timestamp range MUST NOT leak into INDIVIDUAL_DRAWER stats!
      await db.insert('transactions', {
        'invoice_number': 'INV-ORPHAN-IND',
        'date': now.toIso8601String(),
        'cashier_id': owner.id,
        'cashier_name': owner.name,
        'terminal_id': 'ADMIN',
        'cash_register_id': 1,
        'customer_name': 'Umum',
        'subtotal': 50000,
        'discount_total': 0,
        'grand_total': 50000,
        'payment_method': 'tunai',
        'amount_paid': 50000,
        'change_amount': 0,
        'status': 'completed',
        'qr_code_payload': 'ORPHAN',
      });

      // Open two independent parallel shifts in INDIVIDUAL_DRAWER
      final shiftKasirId = await DatabaseHelper.instance.openShift(
        ShiftModel(
          cashierId: kasir.id!,
          cashierName: kasir.name,
          terminalId: 'STAFF-01',
          cashRegisterId: reg2Id,
          startTime: now.subtract(const Duration(minutes: 5)),
          startingCash: 50000,
        ),
      );
      final shiftSupId = await DatabaseHelper.instance.openShift(
        ShiftModel(
          cashierId: supervisor.id!,
          cashierName: supervisor.name,
          terminalId: 'STAFF-02',
          cashRegisterId: reg3Id,
          startTime: now.subtract(const Duration(minutes: 5)),
          startingCash: 75000,
        ),
      );
      expect((await DatabaseHelper.instance.getOpenShifts()).length, 2);

      // Unauthorized register/cashier attempt MUST fail
      await expectLater(
        () => DatabaseHelper.instance.insertTransaction(
          TransactionModel(
            invoiceNumber: 'INV-UNAUTH-1',
            date: now,
            cashierId: kasir.id!,
            cashierName: kasir.name,
            terminalId: 'STAFF-01',
            cashRegisterId: reg3Id, // Unauthorized for kasir!
            subtotal: 100000,
            grandTotal: 100000,
            paymentMethod: 'tunai',
            amountPaid: 100000,
            items: [
              TransactionItemModel(
                productId: prodId,
                productCode: 'IND-1',
                productName: 'Powerbank',
                unitName: 'Pcs',
                qty: 1,
                unitPrice: 100000,
                costPrice: 70000,
                subtotal: 100000,
              ),
            ],
          ),
          shiftId: shiftKasirId,
        ),
        throwsStateError,
      );

      // Unassigned cashier cannot open shift in INDIVIDUAL_DRAWER
      await expectLater(
        () => DatabaseHelper.instance.openShift(
          ShiftModel(
            cashierId: owner.id!,
            cashierName: owner.name,
            terminalId: 'ADMIN',
            cashRegisterId: 1,
            startTime: now,
            startingCash: 100000,
          ),
        ),
        throwsStateError,
      );

      // Switching back to SHARED_DRAWER fails while 2 open shifts exist
      await expectLater(
        () => DatabaseHelper.instance.setDrawerMode(DrawerMode.sharedDrawer, actor: owner),
        throwsStateError,
      );

      // Authorized transaction for kasir on REG-02 succeeds cleanly
      await DatabaseHelper.instance.insertTransaction(
        TransactionModel(
          invoiceNumber: 'INV-IND-K1',
          date: now,
          cashierId: kasir.id!,
          cashierName: kasir.name,
          terminalId: 'STAFF-01',
          cashRegisterId: reg2Id,
          subtotal: 100000,
          grandTotal: 100000,
          paymentMethod: 'tunai',
          amountPaid: 100000,
          items: [
            TransactionItemModel(
              productId: prodId,
              productCode: 'IND-1',
              productName: 'Powerbank',
              unitName: 'Pcs',
              qty: 1,
              unitPrice: 100000,
              costPrice: 70000,
              subtotal: 100000,
            ),
          ],
        ),
        shiftId: shiftKasirId,
      );

      // Close kasir's shift -> must NOT close supervisor's parallel shift!
      await DatabaseHelper.instance.closeShift(shiftKasirId, 150000, 0, '');
      final openAfterCloseOne = await DatabaseHelper.instance.getOpenShifts();
      expect(openAfterCloseOne.length, 1);
      expect(openAfterCloseOne.first.id, shiftSupId);

      // Stats on supervisor shift = 0 (strictly isolated from kasir AND orphan null-shift tx)
      final supStats = await DatabaseHelper.instance.getShiftStats(openAfterCloseOne.first);
      expect(supStats['totalTransactions'], 0);
      expect(supStats['totalGrossProfit'], 0.0);
    });

    test('Closed-Shift Void: never mutates closed shift, settles cash refund on active open shift or holds if none, distinguishes void vs reversal', () async {
      final db = await DatabaseHelper.instance.database;
      final users = await DatabaseHelper.instance.getUsers();
      final owner = users.firstWhere((u) => u.username == 'owner');
      final kasir = users.firstWhere((u) => u.username == 'kasir');

      final prodId = await DatabaseHelper.instance.insertProduct(
        ProductModel(code: 'CV-1', name: 'Earphone Bass', sellingPrice: 40000, costPrice: 25000, stock: 10),
      );
      final now = DateTime.now();

      // 1. Shift 1 executes 2 transactions (1 paid tunai, 1 pre-payment pending void case) and CLOSES
      final shift1Id = await DatabaseHelper.instance.openShift(
        ShiftModel(
          cashierId: kasir.id!,
          cashierName: kasir.name,
          terminalId: 'ADMIN',
          cashRegisterId: 1,
          startTime: now.subtract(const Duration(hours: 2)),
          startingCash: 100000,
        ),
      );

      final paidTrxId = await DatabaseHelper.instance.insertTransaction(
        TransactionModel(
          invoiceNumber: 'INV-CLOSED-CASH',
          date: now.subtract(const Duration(hours: 1)),
          cashierId: kasir.id!,
          cashierName: kasir.name,
          terminalId: 'ADMIN',
          cashRegisterId: 1,
          subtotal: 80000,
          grandTotal: 80000,
          paymentMethod: 'tunai',
          amountPaid: 80000,
          items: [
            TransactionItemModel(
              productId: prodId,
              productCode: 'CV-1',
              productName: 'Earphone Bass',
              unitName: 'Pcs',
              qty: 2,
              unitPrice: 40000,
              costPrice: 25000,
              subtotal: 80000,
            ),
          ],
        ),
        shiftId: shift1Id,
      );

      final prePayTrxId = await DatabaseHelper.instance.insertTransaction(
        TransactionModel(
          invoiceNumber: 'INV-PREPAY',
          date: now.subtract(const Duration(minutes: 50)),
          cashierId: kasir.id!,
          cashierName: kasir.name,
          terminalId: 'ADMIN',
          cashRegisterId: 1,
          subtotal: 40000,
          grandTotal: 40000,
          paymentMethod: 'tunai',
          amountPaid: 40000,
          items: [
            TransactionItemModel(
              productId: prodId,
              productCode: 'CV-1',
              productName: 'Earphone Bass',
              unitName: 'Pcs',
              qty: 1,
              unitPrice: 40000,
              costPrice: 25000,
              subtotal: 40000,
            ),
          ],
        ),
        shiftId: shift1Id,
      );

      // Stock: 10 - 3 = 7; Shift 1 expectedCash = 100k + 80k + 40k = 220k
      await DatabaseHelper.instance.closeShift(shift1Id, 220000, 0, '');
      final closedSnapshotBefore = ShiftModel.fromMap(
        (await db.query('shifts', where: 'id = ?', whereArgs: [shift1Id])).first,
      );

      // 2. Attempting post_payment_reversal tunai void when NO open shift exists MUST be held!
      await expectLater(
        () => DatabaseHelper.instance.voidTransaction(
          paidTrxId,
          voidedBy: owner.id,
          voidedByName: owner.name,
          reason: 'Pelanggan batalkan pesanan',
          voidType: VoidTypes.postPaymentReversal,
        ),
        throwsStateError,
      );
      expect((await DatabaseHelper.instance.getTransactionByInvoice('INV-CLOSED-CASH'))!.status, 'completed');
      expect(((await db.query('products', where: 'id = ?', whereArgs: [prodId])).first['stock'] as num).toDouble(), 7.0);

      // pre_payment_void works without cash drawer settlement when explicitly marked pre_payment_void
      final preVoidId = await DatabaseHelper.instance.voidTransaction(
        prePayTrxId,
        voidedBy: owner.id,
        voidedByName: owner.name,
        reason: 'Void sebelum pembayaran selesai',
        voidType: VoidTypes.prePaymentVoid,
      );
      final preVoidRecord = (await DatabaseHelper.instance.getTransactionVoids(originalTransactionId: prePayTrxId)).single;
      expect(preVoidRecord.id, preVoidId);
      expect(preVoidRecord.voidType, VoidTypes.prePaymentVoid);
      expect(preVoidRecord.refundMethod, 'none');
      expect(preVoidRecord.refundAmount, 0.0);
      expect(preVoidRecord.settlementShiftId, isNull);
      // Stock becomes 8 (7 + 1)
      expect(((await db.query('products', where: 'id = ?', whereArgs: [prodId])).first['stock'] as num).toDouble(), 8.0);

      // 3. Open Shift 2 (with Rp 150,000 cash float) -> perform closed-shift cash reversal void
      final shift2Id = await DatabaseHelper.instance.openShift(
        ShiftModel(
          cashierId: owner.id!,
          cashierName: owner.name,
          terminalId: 'ADMIN',
          cashRegisterId: 1,
          startTime: now,
          startingCash: 150000,
        ),
      );

      final reversalId = await DatabaseHelper.instance.voidTransaction(
        paidTrxId,
        shiftId: shift2Id,
        voidedBy: owner.id,
        voidedByName: owner.name,
        reason: 'Reversal barang cacat setelah tutup kasir kemarin',
        voidType: VoidTypes.postPaymentReversal,
      );
      expect(reversalId, greaterThan(0));

      // Verify closed Shift 1 was NEVER modified retroactively!
      final closedSnapshotAfter = ShiftModel.fromMap(
        (await db.query('shifts', where: 'id = ?', whereArgs: [shift1Id])).first,
      );
      expect(closedSnapshotAfter.status, 'closed');
      expect(closedSnapshotAfter.totalSalesCash, closedSnapshotBefore.totalSalesCash);
      expect(closedSnapshotAfter.expectedCash, closedSnapshotBefore.expectedCash);
      expect(closedSnapshotAfter.actualCash, closedSnapshotBefore.actualCash);
      expect(closedSnapshotAfter.difference, closedSnapshotBefore.difference);

      // Verify original transaction stays bound to Shift 1 & register 1
      final voidedOrigTx = await DatabaseHelper.instance.getTransactionByInvoice('INV-CLOSED-CASH');
      expect(voidedOrigTx!.status, 'voided');
      expect(voidedOrigTx.shiftId, shift1Id);
      expect(voidedOrigTx.cashRegisterId, 1);

      // Verify Shift 2 recorded cash refund outflow (150k - 80k = 70k expectedCash)
      final shift2After = ShiftModel.fromMap(
        (await db.query('shifts', where: 'id = ?', whereArgs: [shift2Id])).first,
      );
      expect(shift2After.totalReturnCash, 80000.0);
      expect(shift2After.expectedCash, 70000.0);

      // Verify immutable `transaction_voids` event record & stock restore
      final reversal = (await DatabaseHelper.instance.getTransactionVoids(originalTransactionId: paidTrxId)).single;
      expect(reversal.originalTransactionId, paidTrxId);
      expect(reversal.originalShiftId, shift1Id);
      expect(reversal.voidType, VoidTypes.postPaymentReversal);
      expect(reversal.refundMethod, 'tunai');
      expect(reversal.refundAmount, 80000.0);
      expect(reversal.voidedBy, owner.id);
      expect(reversal.voidReason, 'Reversal barang cacat setelah tutup kasir kemarin');
      expect(reversal.settlementShiftId, shift2Id);
      expect(reversal.settlementCashRegisterId, 1);
      expect(reversal.cashFlowId, isNotNull);

      expect(((await db.query('products', where: 'id = ?', whereArgs: [prodId])).first['stock'] as num).toDouble(), 10.0);
    });
  });
}
