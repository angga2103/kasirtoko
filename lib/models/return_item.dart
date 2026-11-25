class ReturnConditions {
  static const String baik = 'baik';
  static const String perluPeriksa = 'perlu_periksa';
  static const String kemasanRusak = 'kemasan_rusak';
  static const String cacat = 'cacat';
  static const String rusak = 'rusak';

  static const List<String> all = [
    baik,
    perluPeriksa,
    kemasanRusak,
    cacat,
    rusak,
  ];

  static String label(String condition) {
    switch (condition) {
      case baik:
        return 'Baik / Segel Utuh';
      case perluPeriksa:
        return 'Perlu Diperiksa';
      case kemasanRusak:
        return 'Kemasan Rusak';
      case cacat:
        return 'Cacat Produksi';
      case rusak:
        return 'Rusak / Afkir';
      default:
        return condition;
    }
  }
}

class StockTreatments {
  static const String restockSellable = 'restock_sellable';
  static const String quarantine = 'quarantine';
  static const String damaged = 'damaged';
  static const String noStockChange = 'no_stock_change';

  static const List<String> all = [
    restockSellable,
    quarantine,
    damaged,
    noStockChange,
  ];

  static String label(String treatment) {
    switch (treatment) {
      case restockSellable:
        return 'Kembalikan ke Stok Jual';
      case quarantine:
        return 'Masuk Stok Karantina';
      case damaged:
        return 'Masuk Stok Rusak / Afkir';
      case noStockChange:
        return 'Tidak Ubah Stok (Jasa/Kompensasi)';
      default:
        return treatment;
    }
  }

  static String defaultForCondition(String condition, {bool tracksStock = true}) {
    if (!tracksStock) return noStockChange;
    switch (condition) {
      case ReturnConditions.baik:
        return restockSellable;
      case ReturnConditions.perluPeriksa:
      case ReturnConditions.kemasanRusak:
        return quarantine;
      case ReturnConditions.cacat:
      case ReturnConditions.rusak:
        return damaged;
      default:
        return restockSellable;
    }
  }
}

class ReturnItemModel {
  final int? id;
  final int? returnOrderId;
  final int productId;
  final String sku;
  final String productName;
  final String unitName;
  final double conversionFactor;
  final double purchasedQty;
  final double previouslyReturnedQty;
  final double returnQty;
  final double refundPrice;
  final double costPrice;
  final double subtotal;
  final String condition; // ReturnConditions
  final String stockTreatment; // StockTreatments

  ReturnItemModel({
    this.id,
    this.returnOrderId,
    required this.productId,
    this.sku = '',
    required this.productName,
    this.unitName = 'Pcs',
    this.conversionFactor = 1.0,
    this.purchasedQty = 0.0,
    this.previouslyReturnedQty = 0.0,
    required this.returnQty,
    required this.refundPrice,
    this.costPrice = 0.0,
    double? subtotal,
    this.condition = ReturnConditions.baik,
    String? stockTreatment,
  })  : subtotal = subtotal ?? (returnQty * refundPrice),
        stockTreatment = stockTreatment ?? StockTreatments.defaultForCondition(condition);

  double get baseStockQty => returnQty * conversionFactor;

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      if (returnOrderId != null) 'return_order_id': returnOrderId,
      'product_id': productId,
      'sku': sku,
      'product_name': productName,
      'unit_name': unitName,
      'conversion_factor': conversionFactor,
      'purchased_qty': purchasedQty,
      'previously_returned_qty': previouslyReturnedQty,
      'return_qty': returnQty,
      'refund_price': refundPrice,
      'cost_price': costPrice,
      'subtotal': subtotal,
      'condition': condition,
      'stock_treatment': stockTreatment,
    };
  }

  factory ReturnItemModel.fromMap(Map<String, dynamic> map) {
    final cond = (map['condition'] ?? ReturnConditions.baik).toString();
    final rawTreatment = (map['stock_treatment'] ?? '').toString().trim();
    return ReturnItemModel(
      id: map['id'] as int?,
      returnOrderId: map['return_order_id'] as int?,
      productId: map['product_id'] as int,
      sku: (map['sku'] ?? '').toString(),
      productName: (map['product_name'] ?? '').toString(),
      unitName: (map['unit_name'] ?? 'Pcs').toString(),
      conversionFactor: (map['conversion_factor'] as num?)?.toDouble() ?? 1.0,
      purchasedQty: (map['purchased_qty'] as num?)?.toDouble() ?? 0.0,
      previouslyReturnedQty: (map['previously_returned_qty'] as num?)?.toDouble() ?? 0.0,
      returnQty: (map['return_qty'] as num).toDouble(),
      refundPrice: (map['refund_price'] as num).toDouble(),
      costPrice: (map['cost_price'] as num?)?.toDouble() ?? 0.0,
      subtotal: (map['subtotal'] as num).toDouble(),
      condition: cond,
      stockTreatment: rawTreatment.isNotEmpty
          ? rawTreatment
          : StockTreatments.defaultForCondition(cond),
    );
  }
}
