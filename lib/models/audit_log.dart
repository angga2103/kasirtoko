class AuditLogModel {
  final int? id;
  final DateTime timestamp;
  final int userId;
  final String userName;
  final String userRole;
  final String actionType;
  final String module;
  final String objectId;
  final String beforeValue;
  final String afterValue;
  final String details;

  AuditLogModel({
    this.id,
    required this.timestamp,
    required this.userId,
    required this.userName,
    required this.userRole,
    required this.actionType,
    String? module,
    this.objectId = '',
    this.beforeValue = '',
    this.afterValue = '',
    required this.details,
  }) : module = (module != null && module.isNotEmpty) ? module : inferModule(actionType);

  static String inferModule(String actionType) {
    if (actionType.contains('login') ||
        actionType.contains('logout') ||
        actionType.contains('password') ||
        actionType.contains('pin_lockout') ||
        actionType.contains('migrasi_kdf')) {
      return 'Autentikasi';
    }
    if (actionType.contains('karyawan')) return 'Karyawan';
    if (actionType.contains('shift') ||
        actionType.contains('kas') ||
        actionType.contains('laci') ||
        actionType.contains('drawer')) {
      return 'Kas & Shift';
    }
    if (actionType.contains('pembelian') || actionType.contains('supplier')) return 'Pembelian & Supplier';
    if (actionType.contains('retur')) return 'Retur';
    if (actionType.contains('stok') || actionType.contains('opname') || actionType.contains('produk')) {
      return 'Inventori';
    }
    if (actionType.contains('kasbon') || actionType.contains('pelanggan')) return 'Pelanggan & Kasbon';
    if (actionType.contains('absensi')) return 'Absensi';
    if (actionType.contains('servis')) return 'Servis';
    if (actionType.contains('pengaturan') || actionType.contains('struk') || actionType.contains('printer')) {
      return 'Pengaturan';
    }
    return 'Transaksi POS';
  }

  String get actionDisplay {
    switch (actionType) {
      case 'login':
        return 'Login Sistem';
      case 'login_gagal':
        return 'Percobaan Login Gagal';
      case 'pin_lockout':
        return 'Kunci Sementara (Rate Limit PIN)';
      case 'migrasi_kdf_akun':
        return 'Upgrade KDF Kredensial (v1 ke v2)';
      case 'logout':
        return 'Logout Sistem';
      case 'ubah_password':
      case 'pemulihan_password':
        return 'Perubahan Kredensial';
      case 'transaksi_selesai':
        return 'Transaksi Penjualan';
      case 'void_transaksi':
        return 'Pembatalan (Void) / Reversal Transaksi';
      case 'buka_shift':
        return 'Buka Shift Kasir';
      case 'tutup_shift':
        return 'Tutup Shift Kasir';
      case 'ubah_drawer_mode':
        return 'Perubahan Mode Laci Kas';
      case 'assign_laci_kas':
        return 'Penugasan Laci Kas';
      case 'void_pembelian':
        return 'Pembatalan Pembelian Supplier';
      case 'pembelian_stok':
        return 'Pembelian Supplier';
      case 'bayar_utang_supplier':
        return 'Pembayaran Utang Supplier';
      case 'bayar_kasbon':
        return 'Pembayaran Piutang / Kasbon';
      case 'koreksi_shift':
        return 'Koreksi Shift oleh Admin';
      case 'koreksi_absensi':
        return 'Koreksi Absensi oleh Admin';
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
      case 'absensi_selfie':
        return 'Absensi Selfie Liveness';
      default:
        return actionType;
    }
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'timestamp': timestamp.toIso8601String(),
      'user_id': userId,
      'user_name': userName,
      'user_role': userRole,
      'action_type': actionType,
      'module': module,
      'object_id': objectId,
      'before_value': beforeValue,
      'after_value': afterValue,
      'details': details,
    };
  }

  factory AuditLogModel.fromMap(Map<String, dynamic> map) {
    final actionType = (map['action_type'] ?? '').toString();
    return AuditLogModel(
      id: map['id'] as int?,
      timestamp: DateTime.parse(map['timestamp']),
      userId: map['user_id'] as int,
      userName: map['user_name'] ?? 'User',
      userRole: map['user_role'] ?? 'Kasir',
      actionType: actionType,
      module: (map['module'] ?? '').toString(),
      objectId: (map['object_id'] ?? '').toString(),
      beforeValue: (map['before_value'] ?? '').toString(),
      afterValue: (map['after_value'] ?? '').toString(),
      details: map['details'] ?? '',
    );
  }
}
