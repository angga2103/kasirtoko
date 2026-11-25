class MovementTypes {
  static const String saleOut = 'sale_out';
  static const String voidRestore = 'void_restore';
  static const String returnIn = 'return_in';
  static const String exchangeOut = 'exchange_out';
  static const String quarantineIn = 'quarantine_in';
  static const String quarantineRelease = 'quarantine_release';
  static const String damagedIn = 'damaged_in';
  static const String noStockChange = 'no_stock_change';
  static const String returnVoidReverse = 'return_void_reverse';
  static const String purchaseIn = 'purchase_in';
  static const String purchaseVoidOut = 'purchase_void_out';
  static const String opnameAdjust = 'opname_adjust';

  static String label(String type) {
    switch (type) {
      case saleOut:
        return 'Penjualan Keluar';
      case voidRestore:
        return 'Void Penjualan';
      case returnIn:
        return 'Retur Masuk (Layak Jual)';
      case exchangeOut:
        return 'Tukar Barang Keluar';
      case quarantineIn:
        return 'Masuk Karantina';
      case quarantineRelease:
        return 'Pelepasan Karantina';
      case damagedIn:
        return 'Masuk Stok Rusak';
      case noStockChange:
        return 'Tanpa Mutasi Stok';
      case returnVoidReverse:
        return 'Pembalikan Void Retur';
      case purchaseIn:
        return 'Pembelian Masuk';
      case purchaseVoidOut:
        return 'Void Pembelian';
      case opnameAdjust:
        return 'Penyesuaian Stok Opname';
      default:
        return type;
    }
  }
}

class InventoryMovementModel {
  final int? id;
  final int productId;
  final String sku;
  final String productName;
  final String movementType;
  final String bucket; // 'sellable' | 'quarantine' | 'damaged' | 'none'
  final double qtyDelta;
  final double stockBefore;
  final double stockAfter;
  final double bucketBefore;
  final double bucketAfter;
  final String referenceType;
  final int? referenceId;
  final String referenceNumber;
  final int userId;
  final String userName;
  final String note;
  final DateTime createdAt;

  InventoryMovementModel({
    this.id,
    required this.productId,
    this.sku = '',
    this.productName = '',
    required this.movementType,
    this.bucket = 'sellable',
    required this.qtyDelta,
    required this.stockBefore,
    required this.stockAfter,
    this.bucketBefore = 0.0,
    this.bucketAfter = 0.0,
    this.referenceType = '',
    this.referenceId,
    this.referenceNumber = '',
    this.userId = 1,
    this.userName = 'Sistem',
    this.note = '',
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'product_id': productId,
      'sku': sku,
      'product_name': productName,
      'movement_type': movementType,
      'bucket': bucket,
      'qty_delta': qtyDelta,
      'stock_before': stockBefore,
      'stock_after': stockAfter,
      'bucket_before': bucketBefore,
      'bucket_after': bucketAfter,
      'reference_type': referenceType,
      if (referenceId != null) 'reference_id': referenceId,
      'reference_number': referenceNumber,
      'user_id': userId,
      'user_name': userName,
      'note': note,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory InventoryMovementModel.fromMap(Map<String, dynamic> map) {
    return InventoryMovementModel(
      id: map['id'] as int?,
      productId: map['product_id'] as int,
      sku: (map['sku'] ?? '').toString(),
      productName: (map['product_name'] ?? '').toString(),
      movementType: (map['movement_type'] ?? '').toString(),
      bucket: (map['bucket'] ?? 'sellable').toString(),
      qtyDelta: (map['qty_delta'] as num?)?.toDouble() ?? 0.0,
      stockBefore: (map['stock_before'] as num?)?.toDouble() ?? 0.0,
      stockAfter: (map['stock_after'] as num?)?.toDouble() ?? 0.0,
      bucketBefore: (map['bucket_before'] as num?)?.toDouble() ?? 0.0,
      bucketAfter: (map['bucket_after'] as num?)?.toDouble() ?? 0.0,
      referenceType: (map['reference_type'] ?? '').toString(),
      referenceId: map['reference_id'] as int?,
      referenceNumber: (map['reference_number'] ?? '').toString(),
      userId: (map['user_id'] as num?)?.toInt() ?? 1,
      userName: (map['user_name'] ?? 'Sistem').toString(),
      note: (map['note'] ?? '').toString(),
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}
