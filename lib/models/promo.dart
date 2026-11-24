class PromoModel {
  final int? id;
  final String name;
  final String promoType; // 'diskon_persen', 'potongan_nominal', 'beli_x_gratis_y'
  final double minPurchase; // Minimal belanja untuk dapat promo
  final double discountValue; // Persen atau nominal
  final int? buyQty; // Jika beli X
  final int? getQty; // Gratis Y
  final int? targetProductId; // ID produk yang dibeli/dapat promo
  final String? targetProductName;
  final DateTime startDate;
  final DateTime endDate;
  final bool isActive;

  PromoModel({
    this.id,
    required this.name,
    required this.promoType,
    this.minPurchase = 0.0,
    this.discountValue = 0.0,
    this.buyQty,
    this.getQty,
    this.targetProductId,
    this.targetProductName,
    required this.startDate,
    required this.endDate,
    this.isActive = true,
  });

  bool get isRunning {
    if (!isActive) return false;
    final now = DateTime.now();
    return now.isAfter(startDate) && now.isBefore(endDate.add(const Duration(days: 1)));
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'promo_type': promoType,
      'min_purchase': minPurchase,
      'discount_value': discountValue,
      'buy_qty': buyQty,
      'get_qty': getQty,
      'target_product_id': targetProductId,
      'target_product_name': targetProductName,
      'start_date': startDate.toIso8601String(),
      'end_date': endDate.toIso8601String(),
      'is_active': isActive ? 1 : 0,
    };
  }

  factory PromoModel.fromMap(Map<String, dynamic> map) {
    return PromoModel(
      id: map['id'],
      name: map['name'],
      promoType: map['promo_type'],
      minPurchase: (map['min_purchase'] as num?)?.toDouble() ?? 0.0,
      discountValue: (map['discount_value'] as num?)?.toDouble() ?? 0.0,
      buyQty: map['buy_qty'],
      getQty: map['get_qty'],
      targetProductId: map['target_product_id'],
      targetProductName: map['target_product_name'],
      startDate: DateTime.parse(map['start_date']),
      endDate: DateTime.parse(map['end_date']),
      isActive: (map['is_active'] ?? 1) == 1,
    );
  }
}
