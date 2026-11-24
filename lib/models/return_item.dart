class ReturnItemModel {
  final int? id;
  final int? returnOrderId;
  final int productId;
  final String productName;
  final String unitName;
  final double conversionFactor;
  final double returnQty;
  final double refundPrice;
  final double subtotal;
  final String condition; // 'baik' (kembali ke stok aktif), 'rusak' (masuk gudang rusak/afkir)

  ReturnItemModel({
    this.id,
    this.returnOrderId,
    required this.productId,
    required this.productName,
    required this.unitName,
    this.conversionFactor = 1.0,
    required this.returnQty,
    required this.refundPrice,
    required this.subtotal,
    this.condition = 'baik',
  });

  double get baseStockQty => returnQty * conversionFactor;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'return_order_id': returnOrderId,
      'product_id': productId,
      'product_name': productName,
      'unit_name': unitName,
      'conversion_factor': conversionFactor,
      'return_qty': returnQty,
      'refund_price': refundPrice,
      'subtotal': subtotal,
      'condition': condition,
    };
  }

  factory ReturnItemModel.fromMap(Map<String, dynamic> map) {
    return ReturnItemModel(
      id: map['id'],
      returnOrderId: map['return_order_id'],
      productId: map['product_id'],
      productName: map['product_name'] ?? '',
      unitName: map['unit_name'] ?? 'Pcs',
      conversionFactor: (map['conversion_factor'] as num?)?.toDouble() ?? 1.0,
      returnQty: (map['return_qty'] as num).toDouble(),
      refundPrice: (map['refund_price'] as num).toDouble(),
      subtotal: (map['subtotal'] as num).toDouble(),
      condition: map['condition'] ?? 'baik',
    );
  }
}
