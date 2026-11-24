class ProductBatchModel {
  final int? id;
  final int productId;
  final String batchNumber;
  final DateTime expiryDate;
  final double stockQty;

  ProductBatchModel({
    this.id,
    required this.productId,
    required this.batchNumber,
    required this.expiryDate,
    required this.stockQty,
  });

  bool get isExpired {
    final now = DateTime.now();
    return expiryDate.isBefore(DateTime(now.year, now.month, now.day));
  }

  int get daysUntilExpiry {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final exp = DateTime(expiryDate.year, expiryDate.month, expiryDate.day);
    return exp.difference(today).inDays;
  }

  // Status: 'aman', 'peringatan' (H-30), 'kritis' (H-7), 'kadaluarsa'
  String get expiryStatus {
    final diff = daysUntilExpiry;
    if (diff < 0) return 'kadaluarsa';
    if (diff <= 7) return 'kritis';
    if (diff <= 30) return 'peringatan';
    return 'aman';
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'product_id': productId,
      'batch_number': batchNumber,
      'expiry_date': expiryDate.toIso8601String(),
      'stock_qty': stockQty,
    };
  }

  factory ProductBatchModel.fromMap(Map<String, dynamic> map) {
    return ProductBatchModel(
      id: map['id'],
      productId: map['product_id'],
      batchNumber: map['batch_number'] ?? '',
      expiryDate: DateTime.parse(map['expiry_date']),
      stockQty: (map['stock_qty'] as num).toDouble(),
    );
  }
}
