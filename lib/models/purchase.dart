class PurchaseItemModel {
  final int? id;
  final int? purchaseId;
  final int productId;
  final String productName;
  final double qty;
  final String unitName;
  final double conversionFactor;
  final double costPrice; // Cost per chosen unit
  final double subtotal;

  PurchaseItemModel({
    this.id,
    this.purchaseId,
    required this.productId,
    required this.productName,
    required this.qty,
    this.unitName = 'Pcs',
    this.conversionFactor = 1.0,
    required this.costPrice,
    required this.subtotal,
  });

  double get baseStockQty => qty * conversionFactor;

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'purchase_id': purchaseId,
        'product_id': productId,
        'product_name': productName,
        'qty': qty,
        'unit_name': unitName,
        'conversion_factor': conversionFactor,
        'cost_price': costPrice,
        'subtotal': subtotal,
      };

  factory PurchaseItemModel.fromMap(Map<String, dynamic> map) {
    return PurchaseItemModel(
      id: map['id'] as int?,
      purchaseId: map['purchase_id'] as int?,
      productId: map['product_id'] as int,
      productName: (map['product_name'] ?? '').toString(),
      qty: (map['qty'] as num).toDouble(),
      unitName: (map['unit_name'] ?? 'Pcs').toString(),
      conversionFactor: (map['conversion_factor'] as num?)?.toDouble() ?? 1.0,
      costPrice: (map['cost_price'] as num).toDouble(),
      subtotal: (map['subtotal'] as num).toDouble(),
    );
  }
}

class PurchaseModel {
  final int? id;
  final String purchaseNumber;
  final String supplierName;
  final String supplierPhone;
  final DateTime date;
  final double totalAmount;
  final String paymentMethod; // 'kas_laci' | 'transfer' | 'hutang'
  final String note;
  final String createdBy;
  final List<PurchaseItemModel> items;

  PurchaseModel({
    this.id,
    required this.purchaseNumber,
    required this.supplierName,
    this.supplierPhone = '',
    DateTime? date,
    required this.totalAmount,
    this.paymentMethod = 'kas_laci',
    this.note = '',
    this.createdBy = 'Admin',
    List<PurchaseItemModel>? items,
  })  : date = date ?? DateTime.now(),
        items = items ?? [];

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'purchase_number': purchaseNumber,
        'supplier_name': supplierName,
        'supplier_phone': supplierPhone,
        'date': date.toIso8601String(),
        'total_amount': totalAmount,
        'payment_method': paymentMethod,
        'note': note,
        'created_by': createdBy,
      };

  factory PurchaseModel.fromMap(Map<String, dynamic> map) {
    return PurchaseModel(
      id: map['id'] as int?,
      purchaseNumber: (map['purchase_number'] ?? '').toString(),
      supplierName: (map['supplier_name'] ?? '').toString(),
      supplierPhone: (map['supplier_phone'] ?? '').toString(),
      date: DateTime.parse(map['date']),
      totalAmount: (map['total_amount'] as num).toDouble(),
      paymentMethod: (map['payment_method'] ?? 'kas_laci').toString(),
      note: (map['note'] ?? '').toString(),
      createdBy: (map['created_by'] ?? 'Admin').toString(),
    );
  }
}
