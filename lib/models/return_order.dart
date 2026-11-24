import 'return_item.dart';

class ReturnOrderModel {
  final int? id;
  final String returnNumber;
  final int transactionId;
  final String invoiceNumber;
  final DateTime date;
  final int cashierId;
  final String cashierName;
  final double totalRefund;
  final String refundMethod; // 'tunai', 'potong_piutang', 'tukar_barang'
  final String note;
  List<ReturnItemModel> items;

  ReturnOrderModel({
    this.id,
    required this.returnNumber,
    required this.transactionId,
    required this.invoiceNumber,
    required this.date,
    required this.cashierId,
    required this.cashierName,
    required this.totalRefund,
    this.refundMethod = 'tunai',
    this.note = '',
    List<ReturnItemModel>? items,
  }) : items = items ?? [];

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'return_number': returnNumber,
      'transaction_id': transactionId,
      'invoice_number': invoiceNumber,
      'date': date.toIso8601String(),
      'cashier_id': cashierId,
      'cashier_name': cashierName,
      'total_refund': totalRefund,
      'refund_method': refundMethod,
      'note': note,
    };
  }

  factory ReturnOrderModel.fromMap(Map<String, dynamic> map) {
    return ReturnOrderModel(
      id: map['id'],
      returnNumber: map['return_number'],
      transactionId: map['transaction_id'],
      invoiceNumber: map['invoice_number'],
      date: DateTime.parse(map['date']),
      cashierId: map['cashier_id'],
      cashierName: map['cashier_name'] ?? 'Kasir',
      totalRefund: (map['total_refund'] as num).toDouble(),
      refundMethod: map['refund_method'] ?? 'tunai',
      note: map['note'] ?? '',
    );
  }
}
