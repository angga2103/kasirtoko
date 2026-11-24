import 'package:flutter/foundation.dart';
import '../models/shift.dart';
import '../models/cash_flow.dart';
import '../database/db_helper.dart';

class CashFlowProvider extends ChangeNotifier {
  ShiftModel? _currentShift;
  List<CashFlowModel> _cashFlows = [];
  bool _isLoading = false;

  ShiftModel? get currentShift => _currentShift;
  List<CashFlowModel> get cashFlows => _cashFlows;
  bool get isLoading => _isLoading;
  bool get isShiftOpen => _currentShift != null && _currentShift!.isOpen;

  Future<void> checkOpenShift() async {
    _isLoading = true;
    notifyListeners();

    _currentShift = await DatabaseHelper.instance.getCurrentOpenShift();
    if (_currentShift != null) {
      _cashFlows = await DatabaseHelper.instance.getCashFlowsForShift(_currentShift!.id!);
    } else {
      _cashFlows = [];
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
    _currentShift = ShiftModel(
      id: id,
      cashierId: cashierId,
      cashierName: cashierName,
      startTime: shift.startTime,
      startingCash: startingCash,
      status: 'open',
    );
    _cashFlows = [];
    notifyListeners();
  }

  Future<void> recordCashFlow({
    required String type,
    required String category,
    required double amount,
    required String note,
    required String cashierName,
  }) async {
    final flow = CashFlowModel(
      shiftId: _currentShift?.id,
      type: type,
      category: category,
      amount: amount,
      note: note,
      date: DateTime.now(),
      cashierName: cashierName,
    );

    await DatabaseHelper.instance.insertCashFlow(flow);
    if (_currentShift != null) {
      _cashFlows = await DatabaseHelper.instance.getCashFlowsForShift(_currentShift!.id!);
    }
    notifyListeners();
  }

  Future<void> endShift({
    required double actualCashCount,
    required String note,
  }) async {
    if (_currentShift == null) return;

    final expected = _currentShift!.expectedCash;
    final diff = actualCashCount - expected;

    await DatabaseHelper.instance.closeShift(
      _currentShift!.id!,
      actualCashCount,
      diff,
      note,
    );

    _currentShift = null;
    _cashFlows = [];
    notifyListeners();
  }
}
