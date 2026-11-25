import 'package:flutter/foundation.dart';
import '../database/db_helper.dart';
import '../models/purchase.dart';

class PurchaseProvider extends ChangeNotifier {
  List<PurchaseModel> _purchases = [];
  List<SupplierDebtModel> _supplierDebts = [];
  bool _isLoading = false;

  List<PurchaseModel> get purchases => _purchases;
  List<SupplierDebtModel> get supplierDebts => _supplierDebts;
  List<SupplierDebtModel> get activeSupplierDebts =>
      _supplierDebts.where((d) => !d.isPaidOff && !d.isCancelled).toList();
  double get totalActiveSupplierDebt =>
      activeSupplierDebts.fold(0.0, (sum, d) => sum + d.remainingDebt);
  bool get isLoading => _isLoading;

  Future<void> loadPurchases() async {
    _isLoading = true;
    notifyListeners();
    _purchases = await DatabaseHelper.instance.getPurchases();
    _supplierDebts = await DatabaseHelper.instance.getSupplierDebts();
    _isLoading = false;
    notifyListeners();
  }

  Future<void> recordPurchase(
    PurchaseModel purchase, {
    int? shiftId,
    bool updateProductCost = true,
  }) async {
    await DatabaseHelper.instance.insertPurchase(
      purchase,
      shiftId: shiftId,
      updateProductCostPrice: updateProductCost,
    );
    await loadPurchases();
  }

  Future<void> voidPurchase(
    int purchaseId, {
    int? shiftId,
    String cancelledBy = 'Admin',
  }) async {
    await DatabaseHelper.instance.voidPurchase(
      purchaseId,
      shiftId: shiftId,
      cancelledBy: cancelledBy,
    );
    await loadPurchases();
  }

  Future<List<SupplierDebtPaymentModel>> getSupplierDebtPayments(int supplierDebtId) async {
    return await DatabaseHelper.instance.getSupplierDebtPayments(supplierDebtId);
  }

  Future<void> paySupplierDebt({
    required int supplierDebtId,
    required double amount,
    required String paymentSource,
    String accountName = 'Laci Kasir',
    String referenceNumber = '',
    int? shiftId,
    String paidBy = 'Admin',
    String note = '',
  }) async {
    await DatabaseHelper.instance.paySupplierDebt(
      supplierDebtId: supplierDebtId,
      amount: amount,
      paymentSource: paymentSource,
      accountName: accountName,
      referenceNumber: referenceNumber,
      shiftId: shiftId,
      paidBy: paidBy,
      note: note,
    );
    await loadPurchases();
  }
}
