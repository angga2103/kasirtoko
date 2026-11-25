class CustomerModel {
  final int? id;
  final String name;
  final String phone;
  final String address;
  final String email;
  final String notes;
  final int points;
  final DateTime createdAt;

  CustomerModel({
    this.id,
    required this.name,
    this.phone = '',
    this.address = '',
    this.email = '',
    this.notes = '',
    this.points = 0,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'phone': phone,
      'address': address,
      'email': email,
      'notes': notes,
      'points': points,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory CustomerModel.fromMap(Map<String, dynamic> map) {
    return CustomerModel(
      id: map['id'] as int?,
      name: (map['name'] ?? '').toString(),
      phone: (map['phone'] ?? '').toString(),
      address: (map['address'] ?? '').toString(),
      email: (map['email'] ?? '').toString(),
      notes: (map['notes'] ?? '').toString(),
      points: (map['points'] as num?)?.toInt() ?? 0,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CustomerModel && id != null && other.id == id;

  @override
  int get hashCode => id?.hashCode ?? name.hashCode;
}
