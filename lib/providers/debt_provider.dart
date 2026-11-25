import 'package:flutter/foundation.dart';
import '../database/db_helper.dart';
import '../models/customer_debt.dart';

class DebtProvider extends ChangeNotifier {
  List<CustomerDebtModel> _debts = [];
  bool _isLoading = false;

  List<CustomerDebtModel> get debts => _debts;
  bool get isLoading => _isLoading;

  List<CustomerDebtModel> get overdueDebts =>
      _debts.where((d) => d.isOverdue).toList();

  List<CustomerDebtModel> get unpaidDebts =>
      _debts.where((d) => !d.isPaidOff).toList();

  int get overdueCount => overdueDebts.length;

  double get totalOutstandingDebt =>
      _debts.fold(0.0, (sum, d) => sum + d.remainingDebt);

  Future<void> loadDebts() async {
    _isLoading = true;
    notifyListeners();

    _debts = await DatabaseHelper.instance.getCustomerDebts();

    _isLoading = false;
    notifyListeners();
  }

  Future<List<CustomerDebtPaymentModel>> getDebtPayments(int debtId) async {
    return await DatabaseHelper.instance.getCustomerDebtPayments(debtId);
  }

  Future<void> payDebt(
    int debtId,
    double amountPaid, {
    String paymentMethod = 'tunai',
    int? shiftId,
    String cashierName = 'Kasir',
    String note = '',
  }) async {
    await DatabaseHelper.instance.payCustomerDebt(
      debtId,
      amountPaid,
      paymentMethod: paymentMethod,
      shiftId: shiftId,
      cashierName: cashierName,
      note: note,
    );
    await loadDebts();
  }
}
