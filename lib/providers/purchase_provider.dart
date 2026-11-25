import 'package:flutter/foundation.dart';
import '../database/db_helper.dart';
import '../models/purchase.dart';

class PurchaseProvider extends ChangeNotifier {
  List<PurchaseModel> _purchases = [];
  bool _isLoading = false;

  List<PurchaseModel> get purchases => _purchases;
  bool get isLoading => _isLoading;

  Future<void> loadPurchases() async {
    _isLoading = true;
    notifyListeners();
    _purchases = await DatabaseHelper.instance.getPurchases();
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
}
