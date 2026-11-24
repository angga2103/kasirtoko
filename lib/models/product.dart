import 'product_unit.dart';
import 'tiered_price.dart';
import 'product_batch.dart';

class ProductModel {
  final int? id;
  final String code;
  final String name;
  final String category;
  final String barcode;
  final bool isService;
  final String baseUnit;
  final double costPrice;
  final double sellingPrice;
  final double stock;
  final double minStockAlert;
  final String? imagePath;
  final bool isActive;

  // Transient / related lists
  List<ProductUnitModel> units;
  List<TieredPriceModel> tieredPrices;
  List<ProductBatchModel> batches;

  ProductModel({
    this.id,
    required this.code,
    required this.name,
    this.category = 'Umum',
    this.barcode = '',
    this.isService = false,
    this.baseUnit = 'Pcs',
    this.costPrice = 0.0,
    required this.sellingPrice,
    this.stock = 0.0,
    this.minStockAlert = 5.0,
    this.imagePath,
    this.isActive = true,
    List<ProductUnitModel>? units,
    List<TieredPriceModel>? tieredPrices,
    List<ProductBatchModel>? batches,
  })  : units = units ?? [],
        tieredPrices = tieredPrices ?? [],
        batches = batches ?? [];

  bool get isLowStock => !isService && stock <= minStockAlert;

  double getPriceForQty(double qty) {
    if (tieredPrices.isEmpty) return sellingPrice;
    
    // Sort descending by minQty
    final sorted = List<TieredPriceModel>.from(tieredPrices)
      ..sort((a, b) => b.minQty.compareTo(a.minQty));

    for (final tp in sorted) {
      if (qty >= tp.minQty) {
        return tp.price;
      }
    }
    return sellingPrice;
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'code': code,
      'name': name,
      'category': category,
      'barcode': barcode,
      'is_service': isService ? 1 : 0,
      'base_unit': baseUnit,
      'cost_price': costPrice,
      'selling_price': sellingPrice,
      'stock': stock,
      'min_stock_alert': minStockAlert,
      'image_path': imagePath,
      'is_active': isActive ? 1 : 0,
    };
  }

  factory ProductModel.fromMap(Map<String, dynamic> map) {
    return ProductModel(
      id: map['id'],
      code: map['code'] ?? '',
      name: map['name'] ?? '',
      category: map['category'] ?? 'Umum',
      barcode: map['barcode'] ?? '',
      isService: (map['is_service'] ?? 0) == 1,
      baseUnit: map['base_unit'] ?? 'Pcs',
      costPrice: (map['cost_price'] as num?)?.toDouble() ?? 0.0,
      sellingPrice: (map['selling_price'] as num?)?.toDouble() ?? 0.0,
      stock: (map['stock'] as num?)?.toDouble() ?? 0.0,
      minStockAlert: (map['min_stock_alert'] as num?)?.toDouble() ?? 5.0,
      imagePath: map['image_path'],
      isActive: (map['is_active'] ?? 1) == 1,
    );
  }

  ProductModel copyWith({
    int? id,
    String? code,
    String? name,
    String? category,
    String? barcode,
    bool? isService,
    String? baseUnit,
    double? costPrice,
    double? sellingPrice,
    double? stock,
    double? minStockAlert,
    String? imagePath,
    bool? isActive,
    List<ProductUnitModel>? units,
    List<TieredPriceModel>? tieredPrices,
    List<ProductBatchModel>? batches,
  }) {
    return ProductModel(
      id: id ?? this.id,
      code: code ?? this.code,
      name: name ?? this.name,
      category: category ?? this.category,
      barcode: barcode ?? this.barcode,
      isService: isService ?? this.isService,
      baseUnit: baseUnit ?? this.baseUnit,
      costPrice: costPrice ?? this.costPrice,
      sellingPrice: sellingPrice ?? this.sellingPrice,
      stock: stock ?? this.stock,
      minStockAlert: minStockAlert ?? this.minStockAlert,
      imagePath: imagePath ?? this.imagePath,
      isActive: isActive ?? this.isActive,
      units: units ?? this.units,
      tieredPrices: tieredPrices ?? this.tieredPrices,
      batches: batches ?? this.batches,
    );
  }
}
