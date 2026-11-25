import 'dart:convert';
import 'transaction_item.dart';

class TransactionModel {
  final int? id;
  final String invoiceNumber;
  final DateTime date;
  final int cashierId;
  final String cashierName;
  final int? customerId;
  final int? shiftId;
  final String customerName;
  final String customerPhone;
  final double subtotal;
  final double discountTotal;
  final double taxAmount;
  final String promoName;
  final double grandTotal;
  final String paymentMethod; // 'tunai', 'qris', 'transfer', 'kasbon'
  final double amountPaid;
  final double changeAmount;
  final String status; // 'completed', 'voided', 'returned', 'partial_return'
  final String qrCodePayload;
  final String note;
  final String printerSnapshotJson;
  List<TransactionItemModel> items;

  TransactionModel({
    this.id,
    required this.invoiceNumber,
    required this.date,
    required this.cashierId,
    required this.cashierName,
    this.customerId,
    this.shiftId,
    this.customerName = 'Pelanggan Umum',
    this.customerPhone = '',
    required this.subtotal,
    this.discountTotal = 0.0,
    this.taxAmount = 0.0,
    this.promoName = '',
    required this.grandTotal,
    this.paymentMethod = 'tunai',
    required this.amountPaid,
    this.changeAmount = 0.0,
    this.status = 'completed',
    String? qrCodePayload,
    this.note = '',
    this.printerSnapshotJson = '',
    List<TransactionItemModel>? items,
  })  : qrCodePayload = qrCodePayload ?? 'TRX|$invoiceNumber|${grandTotal.toInt()}',
        items = items ?? [];

  Map<String, dynamic>? get snapshotMap {
    if (printerSnapshotJson.isEmpty) return null;
    try {
      return jsonDecode(printerSnapshotJson) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'invoice_number': invoiceNumber,
      'date': date.toIso8601String(),
      'cashier_id': cashierId,
      'cashier_name': cashierName,
      if (customerId != null) 'customer_id': customerId,
      if (shiftId != null) 'shift_id': shiftId,
      'customer_name': customerName,
      'customer_phone': customerPhone,
      'subtotal': subtotal,
      'discount_total': discountTotal,
      'tax_amount': taxAmount,
      'promo_name': promoName,
      'grand_total': grandTotal,
      'payment_method': paymentMethod,
      'amount_paid': amountPaid,
      'change_amount': changeAmount,
      'status': status,
      'qr_code_payload': qrCodePayload,
      'note': note,
      'printer_snapshot_json': printerSnapshotJson,
    };
  }

  factory TransactionModel.fromMap(Map<String, dynamic> map) {
    return TransactionModel(
      id: map['id'] as int?,
      invoiceNumber: map['invoice_number'],
      date: DateTime.parse(map['date']),
      cashierId: map['cashier_id'] ?? 1,
      cashierName: map['cashier_name'] ?? 'Kasir',
      customerId: map['customer_id'] as int?,
      shiftId: map['shift_id'] as int?,
      customerName: map['customer_name'] ?? 'Pelanggan Umum',
      customerPhone: map['customer_phone'] ?? '',
      subtotal: (map['subtotal'] as num).toDouble(),
      discountTotal: (map['discount_total'] as num?)?.toDouble() ?? 0.0,
      taxAmount: (map['tax_amount'] as num?)?.toDouble() ?? 0.0,
      promoName: (map['promo_name'] ?? '').toString(),
      grandTotal: (map['grand_total'] as num).toDouble(),
      paymentMethod: map['payment_method'] ?? 'tunai',
      amountPaid: (map['amount_paid'] as num).toDouble(),
      changeAmount: (map['change_amount'] as num?)?.toDouble() ?? 0.0,
      status: map['status'] ?? 'completed',
      qrCodePayload: map['qr_code_payload'] ?? '',
      note: map['note'] ?? '',
      printerSnapshotJson: (map['printer_snapshot_json'] ?? '').toString(),
    );
  }
}
