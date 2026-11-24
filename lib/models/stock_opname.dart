class StockOpnameModel {
  final int? id;
  final DateTime date;
  final int productId;
  final String productCode;
  final String productName;
  final double systemStock;
  final double physicalStock;
  final double difference; // physicalStock - systemStock
  final String note; // Alasan: rusak, hilang, salah hitung, kadaluarsa
  final String auditedBy;

  StockOpnameModel({
    this.id,
    required this.date,
    required this.productId,
    required this.productCode,
    required this.productName,
    required this.systemStock,
    required this.physicalStock,
    required this.difference,
    this.note = '',
    required this.auditedBy,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'date': date.toIso8601String(),
      'product_id': productId,
      'product_code': productCode,
      'product_name': productName,
      'system_stock': systemStock,
      'physical_stock': physicalStock,
      'difference': difference,
      'note': note,
      'audited_by': auditedBy,
    };
  }

  factory StockOpnameModel.fromMap(Map<String, dynamic> map) {
    return StockOpnameModel(
      id: map['id'],
      date: DateTime.parse(map['date']),
      productId: map['product_id'],
      productCode: map['product_code'] ?? '',
      productName: map['product_name'] ?? '',
      systemStock: (map['system_stock'] as num).toDouble(),
      physicalStock: (map['physical_stock'] as num).toDouble(),
      difference: (map['difference'] as num).toDouble(),
      note: map['note'] ?? '',
      auditedBy: map['audited_by'] ?? 'Gudang',
    );
  }
}
