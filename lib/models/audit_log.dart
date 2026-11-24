class AuditLogModel {
  final int? id;
  final DateTime timestamp;
  final int userId;
  final String userName;
  final String userRole;
  final String actionType; // 'void_transaksi', 'ubah_harga', 'buka_laci', 'retur_transaksi', 'stok_opname', 'hapus_item'
  final String details;

  AuditLogModel({
    this.id,
    required this.timestamp,
    required this.userId,
    required this.userName,
    required this.userRole,
    required this.actionType,
    required this.details,
  });

  String get actionDisplay {
    switch (actionType) {
      case 'void_transaksi':
        return 'Pembatalan (Void) Transaksi';
      case 'ubah_harga':
        return 'Ubah Harga Manual';
      case 'buka_laci':
        return 'Buka Laci Kasir Manual';
      case 'retur_transaksi':
        return 'Proses Retur Barang';
      case 'stok_opname':
        return 'Penyesuaian Stok Opname';
      case 'hapus_item':
        return 'Hapus Item dari Keranjang';
      case 'diskon_manual':
        return 'Pemberian Diskon Manual';
      default:
        return actionType;
    }
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'timestamp': timestamp.toIso8601String(),
      'user_id': userId,
      'user_name': userName,
      'user_role': userRole,
      'action_type': actionType,
      'details': details,
    };
  }

  factory AuditLogModel.fromMap(Map<String, dynamic> map) {
    return AuditLogModel(
      id: map['id'],
      timestamp: DateTime.parse(map['timestamp']),
      userId: map['user_id'],
      userName: map['user_name'] ?? 'User',
      userRole: map['user_role'] ?? 'Kasir',
      actionType: map['action_type'],
      details: map['details'] ?? '',
    );
  }
}
