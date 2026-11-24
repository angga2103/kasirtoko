class TransactionItemModel {
  final int? id;
  final int? transactionId;
  final int productId;
  final String productCode;
  final String productName;
  final String unitName;
  final double conversionFactor;
  final double qty;
  final double unitPrice;
  final double discount;
  final double subtotal;
  final double costPrice;
  final bool isService;

  TransactionItemModel({
    this.id,
    this.transactionId,
    required this.productId,
    required this.productCode,
    required this.productName,
    required this.unitName,
    this.conversionFactor = 1.0,
    required this.qty,
    required this.unitPrice,
    this.discount = 0.0,
    required this.subtotal,
    this.costPrice = 0.0,
    this.isService = false,
  });

  // Calculate actual base inventory quantity to deduct (qty * conversionFactor)
  double get baseStockQty => isService ? 0.0 : (qty * conversionFactor);

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'transaction_id': transactionId,
      'product_id': productId,
      'product_code': productCode,
      'product_name': productName,
      'unit_name': unitName,
      'conversion_factor': conversionFactor,
      'qty': qty,
      'unit_price': unitPrice,
      'discount': discount,
      'subtotal': subtotal,
      'cost_price': costPrice,
      'is_service': isService ? 1 : 0,
    };
  }

  factory TransactionItemModel.fromMap(Map<String, dynamic> map) {
    return TransactionItemModel(
      id: map['id'],
      transactionId: map['transaction_id'],
      productId: map['product_id'],
      productCode: map['product_code'] ?? '',
      productName: map['product_name'] ?? '',
      unitName: map['unit_name'] ?? 'Pcs',
      conversionFactor: (map['conversion_factor'] as num?)?.toDouble() ?? 1.0,
      qty: (map['qty'] as num).toDouble(),
      unitPrice: (map['unit_price'] as num).toDouble(),
      discount: (map['discount'] as num?)?.toDouble() ?? 0.0,
      subtotal: (map['subtotal'] as num).toDouble(),
      costPrice: (map['cost_price'] as num?)?.toDouble() ?? 0.0,
      isService: (map['is_service'] ?? 0) == 1,
    );
  }
}
