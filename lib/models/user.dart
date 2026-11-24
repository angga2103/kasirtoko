class UserModel {
  final int? id;
  final String name;
  final String pin;
  final String role; // 'owner', 'supervisor', 'cashier', 'warehouse'
  final bool isActive;

  UserModel({
    this.id,
    required this.name,
    required this.pin,
    required this.role,
    this.isActive = true,
  });

  bool get isOwner => role == 'owner';
  bool get isSupervisor => role == 'supervisor' || isOwner;
  bool get isCashier => role == 'cashier';
  bool get isWarehouse => role == 'warehouse';

  String get roleDisplay {
    switch (role) {
      case 'owner':
        return 'Pemilik (Owner)';
      case 'supervisor':
        return 'Supervisor / Manager';
      case 'cashier':
        return 'Kasir';
      case 'warehouse':
        return 'Gudang';
      default:
        return role;
    }
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'pin': pin,
      'role': role,
      'is_active': isActive ? 1 : 0,
    };
  }

  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      id: map['id'],
      name: map['name'],
      pin: map['pin'],
      role: map['role'],
      isActive: (map['is_active'] ?? 1) == 1,
    );
  }
}
