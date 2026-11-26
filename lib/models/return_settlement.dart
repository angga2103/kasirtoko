class ReturnSettlementModel {
  final int? id;
  final int? returnOrderId;
  final String settlementType; // 'refund_tunai', 'refund_transfer', 'refund_qris', 'saldo_kredit', 'potong_piutang', 'tukar_sama', 'tukar_bayar_selisih', 'tukar_kembalian_selisih', 'reversal'
  final String direction; // 'out_to_customer' | 'in_from_customer' | 'debt_offset' | 'credit_issued' | 'credit_used'
  final String method; // 'tunai' | 'transfer' | 'qris' | 'qris_manual' | 'potong_piutang' | 'saldo_kredit'
  final double amount;
  final String accountName;
  final String referenceNumber;
  final int? shiftId;
  final int? settlementShiftId;
  final int? settlementCashRegisterId;
  final int? customerId;
  final int? cashFlowId;
  final String note;
  final DateTime createdAt;

  ReturnSettlementModel({
    this.id,
    this.returnOrderId,
    required this.settlementType,
    required this.direction,
    required this.method,
    required this.amount,
    this.accountName = '',
    this.referenceNumber = '',
    this.shiftId,
    this.settlementShiftId,
    this.settlementCashRegisterId,
    this.customerId,
    this.cashFlowId,
    this.note = '',
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      if (returnOrderId != null) 'return_order_id': returnOrderId,
      'settlement_type': settlementType,
      'direction': direction,
      'method': method,
      'amount': amount,
      'account_name': accountName,
      'reference_number': referenceNumber,
      if (shiftId != null) 'shift_id': shiftId,
      if (settlementShiftId != null) 'settlement_shift_id': settlementShiftId,
      if (settlementCashRegisterId != null) 'settlement_cash_register_id': settlementCashRegisterId,
      if (customerId != null) 'customer_id': customerId,
      if (cashFlowId != null) 'cash_flow_id': cashFlowId,
      'note': note,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory ReturnSettlementModel.fromMap(Map<String, dynamic> map) {
    return ReturnSettlementModel(
      id: map['id'] as int?,
      returnOrderId: map['return_order_id'] as int?,
      settlementType: (map['settlement_type'] ?? '').toString(),
      direction: (map['direction'] ?? '').toString(),
      method: (map['method'] ?? '').toString(),
      amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
      accountName: (map['account_name'] ?? '').toString(),
      referenceNumber: (map['reference_number'] ?? '').toString(),
      shiftId: map['shift_id'] as int?,
      settlementShiftId: map['settlement_shift_id'] as int?,
      settlementCashRegisterId: map['settlement_cash_register_id'] as int?,
      customerId: map['customer_id'] as int?,
      cashFlowId: map['cash_flow_id'] as int?,
      note: (map['note'] ?? '').toString(),
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}
