class ReturnExchangeItemModel {
  final int? id;
  final int? returnOrderId;
  final int productId;
  final String sku;
  final String productName;
  final String unitName;
  final double conversionFactor;
  final double qty;
  final double unitPrice;
  final double costPrice;
  final double subtotal;

  ReturnExchangeItemModel({
    this.id,
    this.returnOrderId,
    required this.productId,
    this.sku = '',
    required this.productName,
    this.unitName = 'Pcs',
    this.conversionFactor = 1.0,
    required this.qty,
    required this.unitPrice,
    this.costPrice = 0.0,
    double? subtotal,
  }) : subtotal = subtotal ?? (qty * unitPrice);

  double get baseStockQty => qty * conversionFactor;

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      if (returnOrderId != null) 'return_order_id': returnOrderId,
      'product_id': productId,
      'sku': sku,
      'product_name': productName,
      'unit_name': unitName,
      'conversion_factor': conversionFactor,
      'qty': qty,
      'unit_price': unitPrice,
      'cost_price': costPrice,
      'subtotal': subtotal,
    };
  }

  factory ReturnExchangeItemModel.fromMap(Map<String, dynamic> map) {
    return ReturnExchangeItemModel(
      id: map['id'] as int?,
      returnOrderId: map['return_order_id'] as int?,
      productId: map['product_id'] as int,
      sku: (map['sku'] ?? '').toString(),
      productName: (map['product_name'] ?? '').toString(),
      unitName: (map['unit_name'] ?? 'Pcs').toString(),
      conversionFactor: (map['conversion_factor'] as num?)?.toDouble() ?? 1.0,
      qty: (map['qty'] as num).toDouble(),
      unitPrice: (map['unit_price'] as num).toDouble(),
      costPrice: (map['cost_price'] as num?)?.toDouble() ?? 0.0,
      subtotal: (map['subtotal'] as num).toDouble(),
    );
  }
}
