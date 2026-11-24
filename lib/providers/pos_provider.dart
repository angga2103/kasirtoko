import 'dart:math';
import 'package:flutter/foundation.dart';
import '../models/product.dart';
import '../models/product_unit.dart';
import '../models/transaction.dart';
import '../models/transaction_item.dart';
import '../database/db_helper.dart';

class HeldOrder {
  final String id;
  final String customerName;
  final DateTime timestamp;
  final List<TransactionItemModel> items;
  final double discountTotal;

  HeldOrder({
    required this.id,
    required this.customerName,
    required this.timestamp,
    required this.items,
    this.discountTotal = 0.0,
  });
}

class PosProvider extends ChangeNotifier {
  List<TransactionItemModel> _cartItems = [];
  double _cartDiscount = 0.0;
  String _customerName = 'Pelanggan Umum';
  String _customerPhone = '';
  String _selectedPaymentMethod = 'tunai';
  double _amountPaid = 0.0;
  final List<HeldOrder> _heldOrders = [];

  List<TransactionItemModel> get cartItems => _cartItems;
  double get cartDiscount => _cartDiscount;
  String get customerName => _customerName;
  String get customerPhone => _customerPhone;
  String get selectedPaymentMethod => _selectedPaymentMethod;
  double get amountPaid => _amountPaid;
  List<HeldOrder> get heldOrders => _heldOrders;

  bool get isEmpty => _cartItems.isEmpty;
  int get itemCount => _cartItems.length;

  double get subtotal =>
      _cartItems.fold(0.0, (sum, item) => sum + item.subtotal);

  double get grandTotal {
    final total = subtotal - _cartDiscount;
    return total > 0 ? total : 0.0;
  }

  double get changeAmount {
    if (_amountPaid >= grandTotal) {
      return _amountPaid - grandTotal;
    }
    return 0.0;
  }

  void setCustomerInfo(String name, String phone) {
    _customerName = name.trim().isEmpty ? 'Pelanggan Umum' : name.trim();
    _customerPhone = phone.trim();
    notifyListeners();
  }

  void setPaymentMethod(String method) {
    _selectedPaymentMethod = method;
    notifyListeners();
  }

  void setAmountPaid(double amount) {
    _amountPaid = amount;
    notifyListeners();
  }

  void setCartDiscount(double discount) {
    _cartDiscount = discount;
    notifyListeners();
  }

  // Add Product to Cart
  void addProduct(ProductModel product, {ProductUnitModel? selectedUnit}) {
    final unitName = selectedUnit != null ? selectedUnit.unitName : product.baseUnit;
    final conversion = selectedUnit != null ? selectedUnit.conversionFactor : 1.0;
    
    // Determine price: unit-specific selling price or base selling price
    double initialPrice = selectedUnit != null ? selectedUnit.sellingPrice : product.sellingPrice;

    // Check if item already exists with the same unit
    final existingIndex = _cartItems.indexWhere(
      (item) => item.productId == product.id && item.unitName == unitName,
    );

    if (existingIndex != -1) {
      final existing = _cartItems[existingIndex];
      final newQty = existing.qty + 1.0;

      // Apply tiered pricing if using base unit
      double updatedPrice = existing.unitPrice;
      if (selectedUnit == null && product.tieredPrices.isNotEmpty) {
        updatedPrice = product.getPriceForQty(newQty);
      }

      final newSubtotal = (newQty * updatedPrice) - existing.discount;

      _cartItems[existingIndex] = TransactionItemModel(
        id: existing.id,
        productId: product.id!,
        productCode: product.code,
        productName: product.name,
        unitName: unitName,
        conversionFactor: conversion,
        qty: newQty,
        unitPrice: updatedPrice,
        discount: existing.discount,
        subtotal: newSubtotal,
        costPrice: product.costPrice,
        isService: product.isService,
      );
    } else {
      // Check tiered price for initial qty = 1
      if (selectedUnit == null && product.tieredPrices.isNotEmpty) {
        initialPrice = product.getPriceForQty(1.0);
      }

      _cartItems.add(
        TransactionItemModel(
          productId: product.id!,
          productCode: product.code,
          productName: product.name,
          unitName: unitName,
          conversionFactor: conversion,
          qty: 1.0,
          unitPrice: initialPrice,
          discount: 0.0,
          subtotal: initialPrice,
          costPrice: product.costPrice,
          isService: product.isService,
        ),
      );
    }

    notifyListeners();
  }

  // Update item quantity
  void updateItemQty(int index, double newQty, ProductModel product) {
    if (newQty <= 0) {
      removeItem(index);
      return;
    }

    final item = _cartItems[index];
    double unitPrice = item.unitPrice;

    // Recalculate tiered price if using base unit
    if (item.unitName == product.baseUnit && product.tieredPrices.isNotEmpty) {
      unitPrice = product.getPriceForQty(newQty);
    }

    final newSubtotal = (newQty * unitPrice) - item.discount;

    _cartItems[index] = TransactionItemModel(
      productId: item.productId,
      productCode: item.productCode,
      productName: item.productName,
      unitName: item.unitName,
      conversionFactor: item.conversionFactor,
      qty: newQty,
      unitPrice: unitPrice,
      discount: item.discount,
      subtotal: newSubtotal > 0 ? newSubtotal : 0.0,
      costPrice: item.costPrice,
      isService: item.isService,
    );

    notifyListeners();
  }

  // Update item discount
  void setItemDiscount(int index, double discount) {
    final item = _cartItems[index];
    final newSubtotal = (item.qty * item.unitPrice) - discount;

    _cartItems[index] = TransactionItemModel(
      productId: item.productId,
      productCode: item.productCode,
      productName: item.productName,
      unitName: item.unitName,
      conversionFactor: item.conversionFactor,
      qty: item.qty,
      unitPrice: item.unitPrice,
      discount: discount,
      subtotal: newSubtotal > 0 ? newSubtotal : 0.0,
      costPrice: item.costPrice,
      isService: item.isService,
    );

    notifyListeners();
  }

  void removeItem(int index) {
    _cartItems.removeAt(index);
    notifyListeners();
  }

  void clearCart() {
    _cartItems = [];
    _cartDiscount = 0.0;
    _amountPaid = 0.0;
    _customerName = 'Pelanggan Umum';
    _customerPhone = '';
    _selectedPaymentMethod = 'tunai';
    notifyListeners();
  }

  // Hold / Pending Order (Tahan transaksi sementara)
  void holdCurrentOrder() {
    if (_cartItems.isEmpty) return;

    final holdId = 'HOLD-${Random().nextInt(9000) + 1000}';
    _heldOrders.add(
      HeldOrder(
        id: holdId,
        customerName: _customerName,
        timestamp: DateTime.now(),
        items: List.from(_cartItems),
        discountTotal: _cartDiscount,
      ),
    );

    clearCart();
  }

  // Resume a held order
  void resumeHeldOrder(HeldOrder order) {
    _cartItems = List.from(order.items);
    _cartDiscount = order.discountTotal;
    _customerName = order.customerName;
    _heldOrders.removeWhere((h) => h.id == order.id);
    notifyListeners();
  }

  void removeHeldOrder(String holdId) {
    _heldOrders.removeWhere((h) => h.id == holdId);
    notifyListeners();
  }

  // Generate unique invoice number
  String generateInvoiceNumber() {
    final now = DateTime.now();
    final dateStr =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final randomDigits = (Random().nextInt(9000) + 1000).toString();
    return 'INV-$dateStr-$randomDigits';
  }

  // Checkout and complete transaction
  Future<TransactionModel> checkout({
    required int cashierId,
    required String cashierName,
    String note = '',
  }) async {
    final invoice = generateInvoiceNumber();
    final now = DateTime.now();
    final total = grandTotal;
    final paid = _selectedPaymentMethod == 'tunai' ? _amountPaid : total;
    final change = _selectedPaymentMethod == 'tunai' ? changeAmount : 0.0;
    final qrPayload = 'TRX|$invoice|${total.toInt()}';

    final transaction = TransactionModel(
      invoiceNumber: invoice,
      date: now,
      cashierId: cashierId,
      cashierName: cashierName,
      customerName: _customerName,
      customerPhone: _customerPhone,
      subtotal: subtotal,
      discountTotal: _cartDiscount,
      grandTotal: total,
      paymentMethod: _selectedPaymentMethod,
      amountPaid: paid,
      changeAmount: change,
      status: 'completed',
      qrCodePayload: qrPayload,
      note: note,
      items: List.from(_cartItems),
    );

    await DatabaseHelper.instance.insertTransaction(transaction);

    // Reset state after successful checkout
    clearCart();

    return transaction;
  }
}
