class CashFlowModel {
  final int? id;
  final int? shiftId;
  final String type; // 'in' (pemasukan), 'out' (pengeluaran)
  final String category; // 'operasional', 'listrik', 'kantong_plastik', 'modal_tambahan', 'prive', 'lainnya'
  final double amount;
  final String note;
  final DateTime date;
  final String cashierName;

  CashFlowModel({
    this.id,
    this.shiftId,
    required this.type,
    required this.category,
    required this.amount,
    this.note = '',
    required this.date,
    required this.cashierName,
  });

  bool get isIn => type == 'in';
  bool get isOut => type == 'out';

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'shift_id': shiftId,
      'type': type,
      'category': category,
      'amount': amount,
      'note': note,
      'date': date.toIso8601String(),
      'cashier_name': cashierName,
    };
  }

  factory CashFlowModel.fromMap(Map<String, dynamic> map) {
    return CashFlowModel(
      id: map['id'],
      shiftId: map['shift_id'],
      type: map['type'],
      category: map['category'] ?? 'Operasional',
      amount: (map['amount'] as num).toDouble(),
      note: map['note'] ?? '',
      date: DateTime.parse(map['date']),
      cashierName: map['cashier_name'] ?? 'Kasir',
    );
  }
}
