import 'return_exchange_item.dart';
import 'return_item.dart';
import 'return_settlement.dart';

class RefundMethods {
  static const String tukarBarang = 'tukar_barang';
  static const String tunai = 'tunai';
  static const String transfer = 'transfer';
  static const String saldoKredit = 'saldo_kredit';
  static const String potongPiutang = 'potong_piutang';
  static const String qrisManual = 'qris_manual';

  static const List<String> all = [
    tukarBarang,
    tunai,
    transfer,
    saldoKredit,
    potongPiutang,
    qrisManual,
  ];

  static String label(String method) {
    switch (method) {
      case tukarBarang:
        return 'Tukar Barang';
      case tunai:
        return 'Tunai (Kas Laci)';
      case transfer:
        return 'Transfer Bank';
      case saldoKredit:
        return 'Saldo Kredit Pelanggan';
      case potongPiutang:
        return 'Potong Piutang (Kasbon)';
      case qrisManual:
        return 'QRIS / E-Wallet Manual';
      default:
        return method;
    }
  }
}

class ReturnOrderModel {
  final int? id;
  final String returnNumber;
  final int transactionId;
  final String invoiceNumber;
  final DateTime date;
  final int cashierId;
  final String cashierName;
  final int? customerId;
  final String customerName;
  final double totalRefund;
  final String refundMethod; // RefundMethods
  final String reason;
  final String note;
  final String status; // 'completed' | 'voided'
  final double exchangeTotal;
  final double differenceAmount; // exchangeTotal - totalRefund (>0 customer pays, <0 store refunds)
  final String differencePaymentMethod; // used for exchange diff or excess potong_piutang
  final String transferAccount;
  final String transferReference;
  final String? idempotencyKey;
  final DateTime? voidedAt;
  final int? voidedBy;
  final String voidedByName;
  final String voidReason;
  List<ReturnItemModel> items;
  List<ReturnExchangeItemModel> exchangeItems;
  List<ReturnSettlementModel> settlements;

  ReturnOrderModel({
    this.id,
    required this.returnNumber,
    required this.transactionId,
    required this.invoiceNumber,
    required this.date,
    required this.cashierId,
    required this.cashierName,
    this.customerId,
    this.customerName = 'Pelanggan Umum',
    required this.totalRefund,
    required this.refundMethod,
    this.reason = '',
    this.note = '',
    this.status = 'completed',
    this.exchangeTotal = 0.0,
    this.differenceAmount = 0.0,
    this.differencePaymentMethod = '',
    this.transferAccount = '',
    this.transferReference = '',
    this.idempotencyKey,
    this.voidedAt,
    this.voidedBy,
    this.voidedByName = '',
    this.voidReason = '',
    List<ReturnItemModel>? items,
    List<ReturnExchangeItemModel>? exchangeItems,
    List<ReturnSettlementModel>? settlements,
  })  : items = items ?? [],
        exchangeItems = exchangeItems ?? [],
        settlements = settlements ?? [];

  bool get isVoided => status == 'voided';
  bool get isExchange => refundMethod == RefundMethods.tukarBarang;

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'return_number': returnNumber,
      'transaction_id': transactionId,
      'invoice_number': invoiceNumber,
      'date': date.toIso8601String(),
      'cashier_id': cashierId,
      'cashier_name': cashierName,
      if (customerId != null) 'customer_id': customerId,
      'customer_name': customerName,
      'total_refund': totalRefund,
      'refund_method': refundMethod,
      'reason': reason,
      'note': note,
      'status': status,
      'exchange_total': exchangeTotal,
      'difference_amount': differenceAmount,
      'difference_payment_method': differencePaymentMethod,
      if (idempotencyKey != null && idempotencyKey!.isNotEmpty) 'idempotency_key': idempotencyKey,
      'voided_at': voidedAt?.toIso8601String(),
      'voided_by': voidedBy,
      'voided_by_name': voidedByName,
      'void_reason': voidReason,
    };
  }

  factory ReturnOrderModel.fromMap(Map<String, dynamic> map) {
    return ReturnOrderModel(
      id: map['id'] as int?,
      returnNumber: (map['return_number'] ?? '').toString(),
      transactionId: map['transaction_id'] as int,
      invoiceNumber: (map['invoice_number'] ?? '').toString(),
      date: DateTime.parse(map['date'].toString()),
      cashierId: (map['cashier_id'] as num?)?.toInt() ?? 1,
      cashierName: (map['cashier_name'] ?? 'Kasir').toString(),
      customerId: map['customer_id'] as int?,
      customerName: (map['customer_name'] ?? 'Pelanggan Umum').toString(),
      totalRefund: (map['total_refund'] as num).toDouble(),
      refundMethod: (map['refund_method'] ?? RefundMethods.tunai).toString(),
      reason: (map['reason'] ?? '').toString(),
      note: (map['note'] ?? '').toString(),
      status: (map['status'] ?? 'completed').toString(),
      exchangeTotal: (map['exchange_total'] as num?)?.toDouble() ?? 0.0,
      differenceAmount: (map['difference_amount'] as num?)?.toDouble() ?? 0.0,
      differencePaymentMethod: (map['difference_payment_method'] ?? '').toString(),
      idempotencyKey: map['idempotency_key'] as String?,
      voidedAt: map['voided_at'] != null ? DateTime.tryParse(map['voided_at'].toString()) : null,
      voidedBy: map['voided_by'] as int?,
      voidedByName: (map['voided_by_name'] ?? '').toString(),
      voidReason: (map['void_reason'] ?? '').toString(),
    );
  }
}
