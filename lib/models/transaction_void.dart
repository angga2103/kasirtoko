class VoidTypes {
  static const String prePaymentVoid = 'pre_payment_void';
  static const String postPaymentReversal = 'post_payment_reversal';

  static String label(String type) {
    switch (type) {
      case prePaymentVoid:
        return 'Void Sebelum Pembayaran Selesai';
      case postPaymentReversal:
      default:
        return 'Reversal / Refund Setelah Pembayaran';
    }
  }
}

class TransactionVoidModel {
  final int? id;
  final int originalTransactionId;
  final String originalInvoiceNumber;
  final int? originalShiftId;
  final int originalCashRegisterId;
  final String voidType; // VoidTypes.prePaymentVoid | VoidTypes.postPaymentReversal
  final String refundMethod; // 'none' | 'tunai' | 'qris' | 'transfer' | 'kasbon_cancel' | 'saldo_kredit'
  final double refundAmount;
  final double creditRestored;
  final DateTime voidedAt;
  final int voidedBy;
  final String voidedByName;
  final String voidReason;
  final int? settlementShiftId;
  final int? settlementCashRegisterId;
  final String settlementTerminalId;
  final int? cashFlowId;

  TransactionVoidModel({
    this.id,
    required this.originalTransactionId,
    required this.originalInvoiceNumber,
    this.originalShiftId,
    this.originalCashRegisterId = 1,
    this.voidType = VoidTypes.postPaymentReversal,
    this.refundMethod = 'none',
    this.refundAmount = 0.0,
    this.creditRestored = 0.0,
    DateTime? voidedAt,
    required this.voidedBy,
    this.voidedByName = 'Admin',
    this.voidReason = '',
    this.settlementShiftId,
    this.settlementCashRegisterId,
    this.settlementTerminalId = 'ADMIN',
    this.cashFlowId,
  }) : voidedAt = voidedAt ?? DateTime.now();

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'original_transaction_id': originalTransactionId,
        'original_invoice_number': originalInvoiceNumber,
        'original_shift_id': originalShiftId,
        'original_cash_register_id': originalCashRegisterId,
        'void_type': voidType,
        'refund_method': refundMethod,
        'refund_amount': refundAmount,
        'credit_restored': creditRestored,
        'voided_at': voidedAt.toIso8601String(),
        'voided_by': voidedBy,
        'voided_by_name': voidedByName,
        'void_reason': voidReason,
        'settlement_shift_id': settlementShiftId,
        'settlement_cash_register_id': settlementCashRegisterId,
        'settlement_terminal_id': settlementTerminalId,
        'cash_flow_id': cashFlowId,
      };

  factory TransactionVoidModel.fromMap(Map<String, dynamic> map) {
    return TransactionVoidModel(
      id: map['id'] as int?,
      originalTransactionId: (map['original_transaction_id'] as num).toInt(),
      originalInvoiceNumber: (map['original_invoice_number'] ?? '').toString(),
      originalShiftId: (map['original_shift_id'] as num?)?.toInt(),
      originalCashRegisterId: (map['original_cash_register_id'] as num?)?.toInt() ?? 1,
      voidType: (map['void_type'] ?? VoidTypes.postPaymentReversal).toString(),
      refundMethod: (map['refund_method'] ?? 'none').toString(),
      refundAmount: (map['refund_amount'] as num?)?.toDouble() ?? 0.0,
      creditRestored: (map['credit_restored'] as num?)?.toDouble() ?? 0.0,
      voidedAt: map['voided_at'] != null
          ? DateTime.tryParse(map['voided_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      voidedBy: (map['voided_by'] as num?)?.toInt() ?? 1,
      voidedByName: (map['voided_by_name'] ?? 'Admin').toString(),
      voidReason: (map['void_reason'] ?? '').toString(),
      settlementShiftId: (map['settlement_shift_id'] as num?)?.toInt(),
      settlementCashRegisterId: (map['settlement_cash_register_id'] as num?)?.toInt(),
      settlementTerminalId: (map['settlement_terminal_id'] ?? 'ADMIN').toString(),
      cashFlowId: (map['cash_flow_id'] as num?)?.toInt(),
    );
  }
}
