class DrawerMode {
  static const String sharedDrawer = 'SHARED_DRAWER';
  static const String individualDrawer = 'INDIVIDUAL_DRAWER';

  static const List<String> all = [sharedDrawer, individualDrawer];

  static String normalize(String? raw) {
    if (raw == individualDrawer) return individualDrawer;
    return sharedDrawer;
  }

  static String label(String mode) {
    switch (normalize(mode)) {
      case individualDrawer:
        return 'INDIVIDUAL_DRAWER (Laci Per Kasir / Terminal)';
      case sharedDrawer:
      default:
        return 'SHARED_DRAWER (Laci Kas Bersama)';
    }
  }
}

class CashRegisterModel {
  final int? id;
  final String registerCode;
  final String name;
  final int? printerId;
  final bool isShared;
  final bool isActive;
  final String notes;
  final DateTime createdAt;

  CashRegisterModel({
    this.id,
    required this.registerCode,
    required this.name,
    this.printerId,
    this.isShared = false,
    this.isActive = true,
    this.notes = '',
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'register_code': registerCode.trim().toUpperCase(),
        'name': name.trim(),
        'printer_id': printerId,
        'is_shared': isShared ? 1 : 0,
        'is_active': isActive ? 1 : 0,
        'notes': notes,
        'created_at': createdAt.toIso8601String(),
      };

  factory CashRegisterModel.fromMap(Map<String, dynamic> map) {
    return CashRegisterModel(
      id: map['id'] as int?,
      registerCode: (map['register_code'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      printerId: map['printer_id'] as int?,
      isShared: (map['is_shared'] ?? 0) == 1,
      isActive: (map['is_active'] ?? 1) == 1,
      notes: (map['notes'] ?? '').toString(),
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  CashRegisterModel copyWith({
    int? id,
    String? registerCode,
    String? name,
    int? printerId,
    bool? isShared,
    bool? isActive,
    String? notes,
  }) {
    return CashRegisterModel(
      id: id ?? this.id,
      registerCode: registerCode ?? this.registerCode,
      name: name ?? this.name,
      printerId: printerId ?? this.printerId,
      isShared: isShared ?? this.isShared,
      isActive: isActive ?? this.isActive,
      notes: notes ?? this.notes,
      createdAt: createdAt,
    );
  }
}

class CashRegisterAssignmentModel {
  final int? id;
  final int cashRegisterId;
  final String? terminalId; // null or empty => matches across terminals for cashierId
  final int? cashierId; // null => matches across cashiers on terminalId
  final int priority;
  final bool isActive;
  final String assignedBy;
  final DateTime createdAt;

  CashRegisterAssignmentModel({
    this.id,
    required this.cashRegisterId,
    String? terminalId,
    this.cashierId,
    this.priority = 0,
    this.isActive = true,
    this.assignedBy = 'Admin',
    DateTime? createdAt,
  })  : terminalId = (terminalId != null && terminalId.trim().isNotEmpty) ? terminalId.trim() : null,
        createdAt = createdAt ?? DateTime.now();

  /// Deterministic specificity rank:
  /// 3 = exact (terminalId + cashierId)
  /// 2 = cashier-level (cashierId only)
  /// 1 = terminal-level (terminalId only)
  int get specificityRank {
    final hasTerm = terminalId != null && terminalId!.isNotEmpty;
    final hasCashier = cashierId != null;
    if (hasTerm && hasCashier) return 3;
    if (hasCashier) return 2;
    if (hasTerm) return 1;
    return 0;
  }

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'cash_register_id': cashRegisterId,
        'terminal_id': terminalId,
        'cashier_id': cashierId,
        'priority': priority,
        'is_active': isActive ? 1 : 0,
        'assigned_by': assignedBy,
        'created_at': createdAt.toIso8601String(),
      };

  factory CashRegisterAssignmentModel.fromMap(Map<String, dynamic> map) {
    final rawTerm = map['terminal_id']?.toString();
    return CashRegisterAssignmentModel(
      id: map['id'] as int?,
      cashRegisterId: (map['cash_register_id'] as num).toInt(),
      terminalId: (rawTerm != null && rawTerm.trim().isNotEmpty) ? rawTerm.trim() : null,
      cashierId: (map['cashier_id'] as num?)?.toInt(),
      priority: (map['priority'] as num?)?.toInt() ?? 0,
      isActive: (map['is_active'] ?? 1) == 1,
      assignedBy: (map['assigned_by'] ?? 'Admin').toString(),
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}
