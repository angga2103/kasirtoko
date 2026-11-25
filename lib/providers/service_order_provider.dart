import 'dart:math';
import 'package:flutter/foundation.dart';
import '../database/db_helper.dart';
import '../models/service_order.dart';

class ServiceOrderProvider extends ChangeNotifier {
  List<ServiceOrderModel> _orders = [];
  String _statusFilter = 'semua';
  String _searchQuery = '';
  bool _isLoading = false;

  List<ServiceOrderModel> get orders => _orders;
  String get statusFilter => _statusFilter;
  String get searchQuery => _searchQuery;
  bool get isLoading => _isLoading;

  int get activeCount => _orders
      .where((o) =>
          o.status != ServiceStatus.sudahDiambil &&
          o.status != ServiceStatus.dibatalkan)
      .length;

  String generateTicketNumber() {
    final now = DateTime.now();
    final dateStr =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final rand = (Random().nextInt(9000) + 1000).toString();
    return 'SRV-$dateStr-$rand';
  }

  Future<void> loadOrders({
    String? status,
    int? technicianId,
    String? query,
  }) async {
    _isLoading = true;
    notifyListeners();

    if (status != null) _statusFilter = status;
    if (query != null) _searchQuery = query;

    _orders = await DatabaseHelper.instance.getServiceOrders(
      status: _statusFilter,
      technicianId: technicianId,
      query: _searchQuery,
    );

    _isLoading = false;
    notifyListeners();
  }

  Future<ServiceOrderModel?> getOrderDetail(int id) async {
    return await DatabaseHelper.instance.getServiceOrderById(id);
  }

  Future<int> createOrder(
    ServiceOrderModel order, {
    int? shiftId,
    String cashierName = 'Kasir',
  }) async {
    final id = await DatabaseHelper.instance.insertServiceOrder(
      order,
      shiftId: shiftId,
      cashierName: cashierName,
    );
    await loadOrders();
    return id;
  }

  Future<void> updateOrder(ServiceOrderModel order) async {
    await DatabaseHelper.instance.updateServiceOrder(order);
    await loadOrders();
  }

  Future<void> addPart(int orderId, ServicePartModel part) async {
    await DatabaseHelper.instance.addServicePart(orderId, part);
    await loadOrders();
  }

  Future<void> removePart(int partId, int orderId) async {
    await DatabaseHelper.instance.removeServicePart(partId, orderId);
    await loadOrders();
  }

  Future<void> changeStatus(int orderId, String newStatus) async {
    await DatabaseHelper.instance.updateServiceStatus(orderId, newStatus);
    await loadOrders();
  }

  Future<void> payOrder({
    required int orderId,
    required double amount,
    required String paymentMethod,
    int? shiftId,
    String cashierName = 'Kasir',
  }) async {
    await DatabaseHelper.instance.recordServicePayment(
      orderId: orderId,
      amount: amount,
      paymentMethod: paymentMethod,
      shiftId: shiftId,
      cashierName: cashierName,
    );
    await loadOrders();
  }
}
