import 'package:flutter/foundation.dart';
import '../database/db_helper.dart';
import '../models/customer.dart';

class CustomerProvider extends ChangeNotifier {
  List<CustomerModel> _customers = [];
  bool _isLoading = false;

  List<CustomerModel> get customers => _customers;
  bool get isLoading => _isLoading;

  Future<void> loadCustomers({String? query}) async {
    _isLoading = true;
    notifyListeners();
    _customers = await DatabaseHelper.instance.getCustomers(query: query);
    _isLoading = false;
    notifyListeners();
  }

  Future<void> saveCustomer(CustomerModel customer) async {
    if (customer.id == null) {
      await DatabaseHelper.instance.insertCustomer(customer);
    } else {
      await DatabaseHelper.instance.updateCustomer(customer);
    }
    await loadCustomers();
  }

  Future<void> deleteCustomer(int id) async {
    await DatabaseHelper.instance.deleteCustomer(id);
    await loadCustomers();
  }
}
