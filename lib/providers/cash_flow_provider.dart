import 'package:flutter/foundation.dart';
import '../database/db_helper.dart';
import '../models/cash_flow.dart';
import '../models/shift.dart';

class CashFlowProvider extends ChangeNotifier {
  ShiftModel? _currentShift;
  List<ShiftModel> _shiftHistory = [];
  List<CashFlowModel> _cashFlows = [];
  bool _isLoading = false;

  ShiftModel? get currentShift => _currentShift;
  List<ShiftModel> get shiftHistory => _shiftHistory;
  List<CashFlowModel> get cashFlows => _cashFlows;
  bool get isLoading => _isLoading;
  bool get isShiftOpen => _currentShift != null && _currentShift!.isOpen;

  Future<void> checkOpenShift() async {
    _isLoading = true;
    notifyListeners();

    _currentShift = await DatabaseHelper.instance.getCurrentOpenShift();
    _shiftHistory = await DatabaseHelper.instance.getShiftHistory(limit: 20);
    if (_currentShift != null) {
      _cashFlows = await DatabaseHelper.instance.getCashFlowsForShift(_currentShift!.id!);
    } else {
      _cashFlows = await DatabaseHelper.instance.getRecentCashFlows(limit: 30);
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> startShift({
    required int cashierId,
    required String cashierName,
    required double startingCash,
  }) async {
    final shift = ShiftModel(
      cashierId: cashierId,
      cashierName: cashierName,
      startTime: DateTime.now(),
      startingCash: startingCash,
      status: 'open',
    );

    final id = await DatabaseHelper.instance.openShift(shift);
    await checkOpenShift();
    _currentShift ??= ShiftModel(
      id: id,
      cashierId: cashierId,
      cashierName: cashierName,
      startTime: shift.startTime,
      startingCash: startingCash,
      status: 'open',
    );
    notifyListeners();
  }

  Future<void> recordCashFlow({
    required String type,
    required String category,
    required double amount,
    required String note,
    required String cashierName,
    String paymentMethod = 'tunai',
    String accountName = 'Laci Kasir',
    String sourceType = 'manual',
    String sourceId = '',
    bool isInternalTransfer = false,
  }) async {
    final flow = CashFlowModel(
      shiftId: (paymentMethod == 'tunai' && accountName == 'Laci Kasir') ? _currentShift?.id : null,
      type: type,
      category: category,
      amount: amount,
      paymentMethod: paymentMethod,
      accountName: accountName,
      sourceType: sourceType,
      sourceId: sourceId,
      isInternalTransfer: isInternalTransfer,
      note: note,
      date: DateTime.now(),
      cashierName: cashierName,
    );

    await DatabaseHelper.instance.insertCashFlow(flow);
    await checkOpenShift();
  }

  Future<Map<String, dynamic>> getActiveShiftStats() async {
    if (_currentShift == null) {
      return {'totalTransactions': 0, 'totalGrossProfit': 0.0};
    }
    return await DatabaseHelper.instance.getShiftStats(_currentShift!);
  }

  Future<Map<String, dynamic>?> endShift({
    required double actualCashCount,
    required String note,
  }) async {
    if (_currentShift == null) return null;

    // Reload latest shift values from DB first so calculations match all cash flows & transactions
    final latestShift = await DatabaseHelper.instance.getCurrentOpenShift() ?? _currentShift!;
    final stats = await DatabaseHelper.instance.getShiftStats(latestShift);
    final expected = latestShift.expectedCash;
    final diff = actualCashCount - expected;

    await DatabaseHelper.instance.closeShift(
      latestShift.id!,
      actualCashCount,
      diff,
      note,
    );

    final closedSnapshot = ShiftModel(
      id: latestShift.id,
      cashierId: latestShift.cashierId,
      cashierName: latestShift.cashierName,
      startTime: latestShift.startTime,
      endTime: DateTime.now(),
      startingCash: latestShift.startingCash,
      totalSalesCash: latestShift.totalSalesCash,
      totalSalesQris: latestShift.totalSalesQris,
      totalSalesTransfer: latestShift.totalSalesTransfer,
      totalSalesKasbon: latestShift.totalSalesKasbon,
      totalCashIn: latestShift.totalCashIn,
      totalCashOut: latestShift.totalCashOut,
      totalReturnCash: latestShift.totalReturnCash,
      actualCash: actualCashCount,
      difference: diff,
      status: 'closed',
      note: note,
    );

    _currentShift = null;
    _cashFlows = await DatabaseHelper.instance.getRecentCashFlows(limit: 20);
    notifyListeners();

    return {
      'shift': closedSnapshot,
      'totalTransactions': stats['totalTransactions'],
      'totalGrossProfit': stats['totalGrossProfit'],
    };
  }
}
