import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../database/db_helper.dart';
import '../models/product.dart';
import '../models/product_unit.dart';
import '../models/promo.dart';
import '../models/receipt_config.dart';
import '../models/transaction.dart';
import '../models/transaction_item.dart';

class HeldOrder {
  final String id;
  final int? customerId;
  final String customerName;
  final String customerPhone;
  final DateTime timestamp;
  final List<TransactionItemModel> items;
  final double discountTotal;

  HeldOrder({
    required this.id,
    this.customerId,
    required this.customerName,
    this.customerPhone = '',
    required this.timestamp,
    required this.items,
    this.discountTotal = 0.0,
  });
}

class CartMutationResult {
  final bool success;
  final String? message;

  CartMutationResult({required this.success, this.message});
}

class PosProvider extends ChangeNotifier {
  List<TransactionItemModel> _cartItems = [];
  double _manualCartDiscount = 0.0;
  PromoModel? _selectedPromo;
  List<PromoModel> _activePromos = [];
  bool _applyTax = false;
  double _taxRate = 0.0;

  int? _customerId;
  String _customerName = 'Pelanggan Umum';
  String _customerPhone = '';
  String _selectedPaymentMethod = 'tunai';
  double _creditUsed = 0.0;
  double _amountPaid = 0.0;
  bool _isCheckingOut = false;
  final List<HeldOrder> _heldOrders = [];

  List<TransactionItemModel> get cartItems => _cartItems;
  double get manualCartDiscount => _manualCartDiscount;
  PromoModel? get selectedPromo => _selectedPromo;
  List<PromoModel> get activePromos => _activePromos;
  bool get applyTax => _applyTax;
  double get taxRate => _taxRate;

  int? get customerId => _customerId;
  String get customerName => _customerName;
  String get customerPhone => _customerPhone;
  String get selectedPaymentMethod => _selectedPaymentMethod;
  double get creditUsed => _creditUsed;
  double get netPayable => (grandTotal - _creditUsed).clamp(0.0, grandTotal);
  double get amountPaid => _amountPaid;
  bool get isCheckingOut => _isCheckingOut;
  List<HeldOrder> get heldOrders => _heldOrders;

  bool get isEmpty => _cartItems.isEmpty;
  int get itemCount => _cartItems.length;
  double get totalUnitsCount => _cartItems.fold(0.0, (s, e) => s + e.qty);

  double get subtotal =>
      _cartItems.fold(0.0, (sum, item) => sum + item.subtotal);

  double get promoDiscount {
    final promo = _selectedPromo;
    if (promo == null || !promo.isRunning) return 0.0;

    if (promo.promoType == 'diskon_persen') {
      if (subtotal < promo.minPurchase) return 0.0;
      return subtotal * (promo.discountValue.clamp(0.0, 100.0) / 100.0);
    } else if (promo.promoType == 'potongan_nominal') {
      if (subtotal < promo.minPurchase) return 0.0;
      return promo.discountValue.clamp(0.0, subtotal);
    } else if (promo.promoType == 'beli_x_gratis_y') {
      final buyQty = promo.buyQty ?? 0;
      final getQty = promo.getQty ?? 0;
      if (buyQty <= 0 || getQty <= 0) return 0.0;
      double freeDiscount = 0.0;
      for (final item in _cartItems) {
        if (promo.targetProductId != null && item.productId != promo.targetProductId) {
          continue;
        }
        final groupSize = buyQty + getQty;
        final eligibleGroups = (item.qty ~/ groupSize);
        if (eligibleGroups > 0) {
          freeDiscount += eligibleGroups * getQty * item.unitPrice;
        }
      }
      return freeDiscount;
    }
    return 0.0;
  }

  double get cartDiscount {
    final combined = _manualCartDiscount + promoDiscount;
    return combined > subtotal ? subtotal : combined;
  }

  double get discountedSubtotal {
    final net = subtotal - cartDiscount;
    return net > 0 ? net : 0.0;
  }

  double get taxAmount {
    if (!_applyTax || _taxRate <= 0) return 0.0;
    return discountedSubtotal * (_taxRate / 100.0);
  }

  double get grandTotal => discountedSubtotal + taxAmount;

  double get changeAmount {
    if (_amountPaid >= netPayable) {
      return _amountPaid - netPayable;
    }
    return 0.0;
  }

  double getCartQtyForProduct(int productId) {
    return _cartItems
        .where((i) => i.productId == productId)
        .fold(0.0, (sum, i) => sum + i.baseStockQty);
  }

  Future<void> loadPromos() async {
    final all = await DatabaseHelper.instance.getActivePromos();
    _activePromos = all.where((p) => p.isRunning).toList();
    if (_selectedPromo != null && !_activePromos.any((p) => p.id == _selectedPromo!.id)) {
      _selectedPromo = null;
    }
    notifyListeners();
  }

  void configureTax({required bool enabled, required double rate}) {
    _applyTax = enabled;
    _taxRate = rate;
    notifyListeners();
  }

  void setCustomerInfo(String name, String phone, {int? customerId}) {
    final cleanName = name.trim();
    _customerId = (cleanName.isEmpty || cleanName.toLowerCase() == 'pelanggan umum') ? null : customerId;
    _customerName = cleanName.isEmpty ? 'Pelanggan Umum' : cleanName;
    _customerPhone = phone.trim();
    notifyListeners();
  }

  void setPaymentMethod(String method) {
    _selectedPaymentMethod = method;
    notifyListeners();
  }

  void setCreditUsed(double amount) {
    _creditUsed = amount < 0 ? 0.0 : (amount > grandTotal ? grandTotal : amount);
    notifyListeners();
  }

  void setAmountPaid(double amount) {
    _amountPaid = amount;
    notifyListeners();
  }

  void setCartDiscount(double discount) {
    _manualCartDiscount = discount < 0 ? 0.0 : discount;
    notifyListeners();
  }

  void setSelectedPromo(PromoModel? promo) {
    _selectedPromo = promo;
    notifyListeners();
  }

  double getBaseCartQtyForProduct(int productId, String baseUnit) {
    for (final i in _cartItems) {
      if (i.productId == productId && i.unitName == baseUnit) {
        return i.qty;
      }
    }
    return 0.0;
  }

  CartMutationResult addProduct(ProductModel product, {ProductUnitModel? selectedUnit}) {
    final unitName = selectedUnit != null ? selectedUnit.unitName : product.baseUnit;
    final conversion = selectedUnit != null ? selectedUnit.conversionFactor : 1.0;

    // Validate physical stock before mutating cart
    if (product.managesStock) {
      final usedBaseQty = getCartQtyForProduct(product.id ?? -1);
      if (usedBaseQty + conversion > product.stock + 0.0001) {
        return CartMutationResult(
          success: false,
          message:
              'Stok "${product.name}" tidak mencukupi (tersedia ${product.stock.toStringAsFixed(product.stock.truncateToDouble() == product.stock ? 0 : 1)} ${product.baseUnit}).',
        );
      }
    }

    double initialPrice = selectedUnit != null ? selectedUnit.sellingPrice : product.sellingPrice;

    final existingIndex = _cartItems.indexWhere(
      (item) => item.productId == product.id && item.unitName == unitName,
    );

    if (existingIndex != -1) {
      final existing = _cartItems[existingIndex];
      final newQty = existing.qty + 1.0;

      double updatedPrice = existing.unitPrice;
      if (selectedUnit == null && product.tieredPrices.isNotEmpty) {
        updatedPrice = product.getPriceForQty(newQty);
      }

      final newSubtotal = ((newQty * updatedPrice) - existing.discount).clamp(0.0, double.infinity);

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
    return CartMutationResult(success: true);
  }

  CartMutationResult setExactBaseQtyForProduct(ProductModel product, double newQty) {
    if (newQty < 0) {
      return CartMutationResult(success: false, message: 'Jumlah tidak boleh negatif.');
    }
    final existingIdx = _cartItems.indexWhere(
      (i) => i.productId == product.id && i.unitName == product.baseUnit,
    );
    if (newQty <= 0) {
      if (existingIdx != -1) {
        removeItem(existingIdx);
      }
      return CartMutationResult(success: true);
    }

    if (existingIdx == -1) {
      if (product.managesStock) {
        final otherUnits = getCartQtyForProduct(product.id ?? -1);
        if (otherUnits + newQty > product.stock + 0.0001) {
          final maxAvail = (product.stock - otherUnits).clamp(0.0, double.infinity);
          return CartMutationResult(
            success: false,
            message:
                'Stok "${product.name}" hanya tersisa ${maxAvail.toStringAsFixed(maxAvail.truncateToDouble() == maxAvail ? 0 : 1)} ${product.baseUnit}.',
          );
        }
      }
      final unitPrice = product.tieredPrices.isNotEmpty
          ? product.getPriceForQty(newQty)
          : product.sellingPrice;
      _cartItems.add(
        TransactionItemModel(
          productId: product.id!,
          productCode: product.code,
          productName: product.name,
          unitName: product.baseUnit,
          conversionFactor: 1.0,
          qty: newQty,
          unitPrice: unitPrice,
          discount: 0.0,
          subtotal: newQty * unitPrice,
          costPrice: product.costPrice,
          isService: product.isService,
        ),
      );
      notifyListeners();
      return CartMutationResult(success: true);
    }
    return updateItemQty(existingIdx, newQty, product);
  }

  CartMutationResult updateItemQty(int index, double newQty, ProductModel product) {
    if (index < 0 || index >= _cartItems.length) {
      return CartMutationResult(success: false, message: 'Item tidak ditemukan.');
    }
    if (newQty <= 0) {
      removeItem(index);
      return CartMutationResult(success: true);
    }

    final item = _cartItems[index];

    if (product.managesStock) {
      double otherUnitsBaseQty = 0.0;
      for (int i = 0; i < _cartItems.length; i++) {
        if (i != index && _cartItems[i].productId == item.productId) {
          otherUnitsBaseQty += _cartItems[i].baseStockQty;
        }
      }
      final requestedBaseQty = newQty * item.conversionFactor;
      if (otherUnitsBaseQty + requestedBaseQty > product.stock + 0.0001) {
        final maxAvailableForLine =
            ((product.stock - otherUnitsBaseQty) / item.conversionFactor).clamp(0.0, double.infinity);
        return CartMutationResult(
          success: false,
          message:
              'Stok "${product.name}" hanya cukup untuk maksimal ${maxAvailableForLine.toStringAsFixed(maxAvailableForLine.truncateToDouble() == maxAvailableForLine ? 0 : 1)} ${item.unitName}.',
        );
      }
    }

    double unitPrice = item.unitPrice;
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
    return CartMutationResult(success: true);
  }

  void setItemDiscount(int index, double discount) {
    if (index < 0 || index >= _cartItems.length) return;
    final item = _cartItems[index];
    final safeDiscount = discount < 0 ? 0.0 : discount;
    final newSubtotal = (item.qty * item.unitPrice) - safeDiscount;

    _cartItems[index] = TransactionItemModel(
      productId: item.productId,
      productCode: item.productCode,
      productName: item.productName,
      unitName: item.unitName,
      conversionFactor: item.conversionFactor,
      qty: item.qty,
      unitPrice: item.unitPrice,
      discount: safeDiscount,
      subtotal: newSubtotal > 0 ? newSubtotal : 0.0,
      costPrice: item.costPrice,
      isService: item.isService,
    );

    notifyListeners();
  }

  void removeItem(int index) {
    if (index < 0 || index >= _cartItems.length) return;
    _cartItems.removeAt(index);
    if (_cartItems.isEmpty) {
      _manualCartDiscount = 0.0;
      _selectedPromo = null;
    }
    notifyListeners();
  }

  void clearCart() {
    _cartItems = [];
    _manualCartDiscount = 0.0;
    _selectedPromo = null;
    _creditUsed = 0.0;
    _amountPaid = 0.0;
    _customerId = null;
    _customerName = 'Pelanggan Umum';
    _customerPhone = '';
    _selectedPaymentMethod = 'tunai';
    notifyListeners();
  }

  void holdCurrentOrder() {
    if (_cartItems.isEmpty) return;

    final holdId = 'HOLD-${Random().nextInt(9000) + 1000}';
    _heldOrders.add(
      HeldOrder(
        id: holdId,
        customerId: _customerId,
        customerName: _customerName,
        customerPhone: _customerPhone,
        timestamp: DateTime.now(),
        items: List.from(_cartItems),
        discountTotal: _manualCartDiscount,
      ),
    );

    clearCart();
  }

  void resumeHeldOrder(HeldOrder order) {
    _cartItems = List.from(order.items);
    _manualCartDiscount = order.discountTotal;
    _customerId = order.customerId;
    _customerName = order.customerName;
    _customerPhone = order.customerPhone;
    _heldOrders.removeWhere((h) => h.id == order.id);
    notifyListeners();
  }

  void removeHeldOrder(String holdId) {
    _heldOrders.removeWhere((h) => h.id == holdId);
    notifyListeners();
  }

  String generateInvoiceNumber() {
    final now = DateTime.now();
    final dateStr =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final randomDigits = (Random().nextInt(9000) + 1000).toString();
    return 'INV-$dateStr-$randomDigits';
  }

  /// Atomically completes checkout once, prevents double transaction, creates historical receipt snapshot.
  Future<TransactionModel?> checkout({
    required int cashierId,
    required String cashierName,
    String? customInvoiceNumber,
    int? activeShiftId,
    String terminalId = 'ADMIN',
    int? cashRegisterId,
    String? idempotencyKey,
    String note = '',
    String storeName = '',
    String storeAddress = '',
    String storePhone = '',
    ReceiptConfigModel? receiptConfig,
  }) async {
    if (_isCheckingOut || _cartItems.isEmpty) return null;
    _isCheckingOut = true;
    notifyListeners();

    try {
      final invoice = (customInvoiceNumber != null && customInvoiceNumber.isNotEmpty)
          ? customInvoiceNumber
          : generateInvoiceNumber();
      final now = DateTime.now();
      final total = grandTotal;
      final usedCredit = _creditUsed.clamp(0.0, total);
      final netDue = (total - usedCredit).clamp(0.0, total);
      final effectiveMethod = netDue <= 0.01 && usedCredit > 0 ? 'saldo_kredit' : _selectedPaymentMethod;
      final paid = (effectiveMethod == 'tunai' || effectiveMethod == 'kasbon')
          ? _amountPaid
          : netDue;
      final change = effectiveMethod == 'tunai' ? changeAmount : 0.0;
      final qrPayload = 'TRX|$invoice|${total.toInt()}';

      final snapshot = {
        'store_name': storeName,
        'store_address': storeAddress,
        'store_phone': storePhone,
        'receipt_config': (receiptConfig ?? const ReceiptConfigModel()).toMap(),
        'printed_at': now.toIso8601String(),
      };

      final transaction = TransactionModel(
        invoiceNumber: invoice,
        date: now,
        cashierId: cashierId,
        cashierName: cashierName,
        terminalId: terminalId,
        cashRegisterId: cashRegisterId ?? 1,
        idempotencyKey: idempotencyKey,
        customerId: _customerId,
        shiftId: activeShiftId,
        customerName: _customerName,
        customerPhone: _customerPhone,
        subtotal: subtotal,
        discountTotal: cartDiscount,
        taxAmount: taxAmount,
        promoName: _selectedPromo?.name ?? '',
        grandTotal: total,
        paymentMethod: effectiveMethod,
        creditUsed: usedCredit,
        amountPaid: paid,
        changeAmount: change,
        status: 'completed',
        qrCodePayload: qrPayload,
        note: note,
        printerSnapshotJson: jsonEncode(snapshot),
        items: List.from(_cartItems),
      );

      final insertedId = await DatabaseHelper.instance.insertTransaction(
        transaction,
        shiftId: activeShiftId,
        terminalId: terminalId,
        cashRegisterId: cashRegisterId,
      );

      final savedTrx = TransactionModel(
        id: insertedId,
        invoiceNumber: transaction.invoiceNumber,
        date: transaction.date,
        cashierId: transaction.cashierId,
        cashierName: transaction.cashierName,
        terminalId: transaction.terminalId,
        cashRegisterId: transaction.cashRegisterId,
        idempotencyKey: transaction.idempotencyKey,
        customerId: transaction.customerId,
        shiftId: transaction.shiftId,
        customerName: transaction.customerName,
        customerPhone: transaction.customerPhone,
        subtotal: transaction.subtotal,
        discountTotal: transaction.discountTotal,
        taxAmount: transaction.taxAmount,
        promoName: transaction.promoName,
        grandTotal: transaction.grandTotal,
        paymentMethod: transaction.paymentMethod,
        creditUsed: transaction.creditUsed,
        amountPaid: transaction.amountPaid,
        changeAmount: transaction.changeAmount,
        status: transaction.status,
        qrCodePayload: transaction.qrCodePayload,
        note: transaction.note,
        printerSnapshotJson: transaction.printerSnapshotJson,
        items: transaction.items,
      );

      clearCart();
      return savedTrx;
    } finally {
      _isCheckingOut = false;
      notifyListeners();
    }
  }
}
