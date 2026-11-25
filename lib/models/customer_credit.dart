class CustomerCreditTypes {
  static const String creditIssued = 'credit_issued';
  static const String creditRedeemed = 'credit_redeemed';
  static const String creditReversed = 'credit_reversed';
  static const String manualAdjustment = 'manual_adjustment';
}

class CustomerCreditEntryModel {
  final int? id;
  final int customerId;
  final String customerName;
  final String entryType;
  final double amount;
  final double balanceBefore;
  final double balanceAfter;
  final String referenceType;
  final int? referenceId;
  final String referenceNumber;
  final int userId;
  final String userName;
  final String note;
  final DateTime createdAt;

  CustomerCreditEntryModel({
    this.id,
    required this.customerId,
    this.customerName = '',
    required this.entryType,
    required this.amount,
    this.balanceBefore = 0.0,
    this.balanceAfter = 0.0,
    this.referenceType = '',
    this.referenceId,
    this.referenceNumber = '',
    this.userId = 1,
    this.userName = 'Sistem',
    this.note = '',
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  bool get isAddition =>
      entryType == CustomerCreditTypes.creditIssued || entryType == CustomerCreditTypes.manualAdjustment;

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'customer_id': customerId,
      'customer_name': customerName,
      'entry_type': entryType,
      'amount': amount,
      'balance_before': balanceBefore,
      'balance_after': balanceAfter,
      'reference_type': referenceType,
      if (referenceId != null) 'reference_id': referenceId,
      'reference_number': referenceNumber,
      'user_id': userId,
      'user_name': userName,
      'note': note,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory CustomerCreditEntryModel.fromMap(Map<String, dynamic> map) {
    return CustomerCreditEntryModel(
      id: map['id'] as int?,
      customerId: map['customer_id'] as int,
      customerName: (map['customer_name'] ?? '').toString(),
      entryType: (map['entry_type'] ?? '').toString(),
      amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
      balanceBefore: (map['balance_before'] as num?)?.toDouble() ?? 0.0,
      balanceAfter: (map['balance_after'] as num?)?.toDouble() ?? 0.0,
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
