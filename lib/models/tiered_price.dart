class TieredPriceModel {
  final int? id;
  final int productId;
  final double minQty; // Beli minimal berapa pcs
  final double price; // Harga per pcs untuk tingkatan ini

  TieredPriceModel({
    this.id,
    required this.productId,
    required this.minQty,
    required this.price,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'product_id': productId,
      'min_qty': minQty,
      'price': price,
    };
  }

  factory TieredPriceModel.fromMap(Map<String, dynamic> map) {
    return TieredPriceModel(
      id: map['id'],
      productId: map['product_id'],
      minQty: (map['min_qty'] as num).toDouble(),
      price: (map['price'] as num).toDouble(),
    );
  }
}
