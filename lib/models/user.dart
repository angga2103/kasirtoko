import 'dart:convert';

class AppRoles {
  static const String owner = 'owner';
  static const String admin = 'admin';
  static const String supervisor = 'supervisor';
  static const String cashier = 'cashier';
  static const String warehouse = 'warehouse';
  static const String technician = 'technician';
  static const String delivery = 'delivery';

  static const List<String> all = [
    owner,
    admin,
    supervisor,
    cashier,
    warehouse,
    technician,
    delivery,
  ];

  static String displayName(String role) {
    switch (role) {
      case owner:
        return 'Pemilik (Owner)';
      case admin:
        return 'Administrator';
      case supervisor:
        return 'Supervisor';
      case cashier:
        return 'Kasir';
      case warehouse:
        return 'Staff Gudang';
      case technician:
        return 'Teknisi / Staff Servis';
      case delivery:
        return 'Staff Pengiriman';
      default:
        return role;
    }
  }
}

class AppPermissions {
  static const String viewDashboard = 'view_dashboard';
  static const String accessPos = 'access_pos';
  static const String applyDiscount = 'apply_discount';
  static const String voidTransaction = 'void_transaction';
  static const String manageProducts = 'manage_products';
  static const String manageStock = 'manage_stock';
  static const String managePurchases = 'manage_purchases';
  static const String viewReports = 'view_reports';
  static const String viewCostPrice = 'view_cost_price';
  static const String viewProfit = 'view_profit';
  static const String manageCustomers = 'manage_customers';
  static const String manageService = 'manage_service';
  static const String managePrinters = 'manage_printers';
  static const String manageStoreSettings = 'manage_store_settings';
  static const String manageEmployees = 'manage_employees';

  static const Map<String, String> labels = {
    viewDashboard: 'Dashboard & Ringkasan',
    accessPos: 'Akses Kasir (POS)',
    applyDiscount: 'Beri Diskon Manual & Promo',
    voidTransaction: 'Pembatalan / Retur Transaksi',
    manageProducts: 'Kelola Produk & Harga Jual',
    manageStock: 'Stok Opname & Kadaluarsa',
    managePurchases: 'Pembelian / Restock Supplier',
    viewReports: 'Lihat Laporan Penjualan & Audit',
    viewCostPrice: 'Lihat Harga Modal (HPP)',
    viewProfit: 'Lihat Keuntungan / Laba',
    manageCustomers: 'Pelanggan & Kasbon',
    manageService: 'Modul Jasa Servis',
    managePrinters: 'Pengaturan Printer & Struk',
    manageStoreSettings: 'Pengaturan Toko & Backup',
    manageEmployees: 'Manajemen Karyawan & Hak Akses',
  };

  static Map<String, bool> allTrue() => {
        for (final key in labels.keys) key: true,
      };

  static Map<String, bool> defaultForRole(String role) {
    switch (role) {
      case AppRoles.owner:
        return allTrue();
      case AppRoles.admin:
        return {
          viewDashboard: true,
          accessPos: true,
          applyDiscount: true,
          voidTransaction: true,
          manageProducts: true,
          manageStock: true,
          managePurchases: true,
          viewReports: true,
          viewCostPrice: true,
          viewProfit: true,
          manageCustomers: true,
          manageService: true,
          managePrinters: true,
          manageStoreSettings: true,
          manageEmployees: false,
        };
      case AppRoles.supervisor:
        return {
          viewDashboard: true,
          accessPos: true,
          applyDiscount: true,
          voidTransaction: true,
          manageProducts: true,
          manageStock: true,
          managePurchases: true,
          viewReports: true,
          viewCostPrice: false,
          viewProfit: false,
          manageCustomers: true,
          manageService: true,
          managePrinters: true,
          manageStoreSettings: false,
          manageEmployees: false,
        };
      case AppRoles.cashier:
        return {
          viewDashboard: true,
          accessPos: true,
          applyDiscount: false,
          voidTransaction: false,
          manageProducts: false,
          manageStock: false,
          managePurchases: false,
          viewReports: false,
          viewCostPrice: false,
          viewProfit: false,
          manageCustomers: true,
          manageService: true,
          managePrinters: false,
          manageStoreSettings: false,
          manageEmployees: false,
        };
      case AppRoles.warehouse:
        return {
          viewDashboard: true,
          accessPos: false,
          applyDiscount: false,
          voidTransaction: false,
          manageProducts: true,
          manageStock: true,
          managePurchases: true,
          viewReports: false,
          viewCostPrice: false,
          viewProfit: false,
          manageCustomers: false,
          manageService: false,
          managePrinters: false,
          manageStoreSettings: false,
          manageEmployees: false,
        };
      case AppRoles.technician:
        return {
          viewDashboard: true,
          accessPos: false,
          applyDiscount: false,
          voidTransaction: false,
          manageProducts: false,
          manageStock: false,
          managePurchases: false,
          viewReports: false,
          viewCostPrice: false,
          viewProfit: false,
          manageCustomers: true,
          manageService: true,
          managePrinters: false,
          manageStoreSettings: false,
          manageEmployees: false,
        };
      case AppRoles.delivery:
        return {
          viewDashboard: true,
          accessPos: false,
          applyDiscount: false,
          voidTransaction: false,
          manageProducts: false,
          manageStock: true,
          managePurchases: false,
          viewReports: false,
          viewCostPrice: false,
          viewProfit: false,
          manageCustomers: true,
          manageService: false,
          managePrinters: false,
          manageStoreSettings: false,
          manageEmployees: false,
        };
      default:
        return defaultForRole(AppRoles.cashier);
    }
  }
}

class UserModel {
  final int? id;
  final String name;
  final String username;
  final String passwordHash;
  final String passwordSalt;
  final String pin; // Legacy masked field (empty for hashed users)
  final String pinHash;
  final String role;
  final String phone;
  final String? photoPath;
  final Map<String, bool> permissions;
  final bool isActive;

  UserModel({
    this.id,
    required this.name,
    this.username = '',
    this.passwordHash = '',
    this.passwordSalt = '',
    this.pin = '',
    this.pinHash = '',
    required this.role,
    this.phone = '',
    this.photoPath,
    Map<String, bool>? permissions,
    this.isActive = true,
  }) : permissions = permissions ?? AppPermissions.defaultForRole(role);

  bool get isOwner => role == AppRoles.owner;
  bool get isAdmin => role == AppRoles.admin || isOwner;
  bool get isSupervisor => role == AppRoles.supervisor || isAdmin;
  bool get isCashier => role == AppRoles.cashier;
  bool get isWarehouse => role == AppRoles.warehouse;
  bool get isTechnician => role == AppRoles.technician;
  bool get isDelivery => role == AppRoles.delivery;

  String get roleDisplay => AppRoles.displayName(role);

  bool hasPermission(String permissionKey) {
    if (isOwner) return true;
    return permissions[permissionKey] ?? false;
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'username': username.isNotEmpty ? username : null,
      'password_hash': passwordHash,
      'password_salt': passwordSalt,
      'pin': pin,
      'pin_hash': pinHash,
      'role': role,
      'phone': phone,
      'photo_path': photoPath,
      'permissions_json': jsonEncode(permissions),
      'is_active': isActive ? 1 : 0,
    };
  }

  factory UserModel.fromMap(Map<String, dynamic> map) {
    final role = (map['role'] ?? AppRoles.cashier).toString();
    Map<String, bool> perms = AppPermissions.defaultForRole(role);
    final rawJson = map['permissions_json'] as String?;
    if (rawJson != null && rawJson.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawJson) as Map<String, dynamic>;
        for (final entry in decoded.entries) {
          perms[entry.key] = entry.value == true;
        }
      } catch (_) {}
    }

    return UserModel(
      id: map['id'] as int?,
      name: (map['name'] ?? '').toString(),
      username: (map['username'] ?? '').toString(),
      passwordHash: (map['password_hash'] ?? '').toString(),
      passwordSalt: (map['password_salt'] ?? '').toString(),
      pin: (map['pin'] ?? '').toString(),
      pinHash: (map['pin_hash'] ?? '').toString(),
      role: role,
      phone: (map['phone'] ?? '').toString(),
      photoPath: map['photo_path'] as String?,
      permissions: perms,
      isActive: (map['is_active'] ?? 1) == 1,
    );
  }

  UserModel copyWith({
    int? id,
    String? name,
    String? username,
    String? passwordHash,
    String? passwordSalt,
    String? pin,
    String? pinHash,
    String? role,
    String? phone,
    String? photoPath,
    Map<String, bool>? permissions,
    bool? isActive,
  }) {
    return UserModel(
      id: id ?? this.id,
      name: name ?? this.name,
      username: username ?? this.username,
      passwordHash: passwordHash ?? this.passwordHash,
      passwordSalt: passwordSalt ?? this.passwordSalt,
      pin: pin ?? this.pin,
      pinHash: pinHash ?? this.pinHash,
      role: role ?? this.role,
      phone: phone ?? this.phone,
      photoPath: photoPath ?? this.photoPath,
      permissions: permissions ?? Map<String, bool>.from(this.permissions),
      isActive: isActive ?? this.isActive,
    );
  }
}
