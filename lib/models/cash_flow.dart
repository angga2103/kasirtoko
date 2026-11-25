class CashFlowModel {
  final int? id;
  final int? shiftId;
  final String type; // 'in' | 'out' | 'transfer'
  final String category;
  final double amount;
  final String paymentMethod; // 'tunai' | 'transfer' | 'qris'
  final String accountName; // 'Laci Kasir' | 'Rekening Bank' | 'Kas Toko'
  final String sourceType; // 'manual' | 'shift_open' | 'penjualan' | 'pembelian' | 'kasbon_bayar' | 'utang_supplier_bayar' | 'retur' | 'servis' | 'transfer_akun'
  final String sourceId;
  final bool isInternalTransfer;
  final String note;
  final DateTime date;
  final String cashierName;

  CashFlowModel({
    this.id,
    this.shiftId,
    required this.type,
    required this.category,
    required this.amount,
    this.paymentMethod = 'tunai',
    this.accountName = 'Laci Kasir',
    this.sourceType = 'manual',
    this.sourceId = '',
    this.isInternalTransfer = false,
    this.note = '',
    required this.date,
    required this.cashierName,
  });

  bool get isIn => type == 'in';
  bool get isOut => type == 'out';

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'shift_id': shiftId,
      'type': type,
      'category': category,
      'amount': amount,
      'payment_method': paymentMethod,
      'account_name': accountName,
      'source_type': sourceType,
      'source_id': sourceId,
      'is_internal_transfer': isInternalTransfer ? 1 : 0,
      'note': note,
      'date': date.toIso8601String(),
      'cashier_name': cashierName,
    };
  }

  factory CashFlowModel.fromMap(Map<String, dynamic> map) {
    return CashFlowModel(
      id: map['id'] as int?,
      shiftId: map['shift_id'] as int?,
      type: map['type'],
      category: map['category'] ?? 'Operasional',
      amount: (map['amount'] as num).toDouble(),
      paymentMethod: (map['payment_method'] ?? 'tunai').toString(),
      accountName: (map['account_name'] ?? 'Laci Kasir').toString(),
      sourceType: (map['source_type'] ?? 'manual').toString(),
      sourceId: (map['source_id'] ?? '').toString(),
      isInternalTransfer: (map['is_internal_transfer'] ?? 0) == 1,
      note: map['note'] ?? '',
      date: DateTime.parse(map['date']),
      cashierName: map['cashier_name'] ?? 'Kasir',
    );
  }
}
