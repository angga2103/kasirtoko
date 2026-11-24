class ProductUnitModel {
  final int? id;
  final int productId;
  final String unitName; // misal: 'Dus', 'Pack', 'Renceng'
  final double conversionFactor; // 1 Dus = 24 Pcs (maka factor = 24.0)
  final double sellingPrice; // Harga khusus untuk satuan ini
  final String barcode;

  ProductUnitModel({
    this.id,
    required this.productId,
    required this.unitName,
    required this.conversionFactor,
    required this.sellingPrice,
    this.barcode = '',
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'product_id': productId,
      'unit_name': unitName,
      'conversion_factor': conversionFactor,
      'selling_price': sellingPrice,
      'barcode': barcode,
    };
  }

  factory ProductUnitModel.fromMap(Map<String, dynamic> map) {
    return ProductUnitModel(
      id: map['id'],
      productId: map['product_id'],
      unitName: map['unit_name'],
      conversionFactor: (map['conversion_factor'] as num).toDouble(),
      sellingPrice: (map['selling_price'] as num).toDouble(),
      barcode: map['barcode'] ?? '',
    );
  }
}
