class ShiftModel {
  final int? id;
  final int cashierId;
  final String cashierName;
  final DateTime startTime;
  final DateTime? endTime;
  final double startingCash; // Modal awal di laci
  final double totalSalesCash;
  final double totalCashIn;
  final double totalCashOut;
  final double totalReturnCash;
  final double? actualCash; // Uang fisik dihitung kasir saat tutup shift
  final double? difference; // actualCash - expectedCash
  final String status; // 'open', 'closed'
  final String note;

  ShiftModel({
    this.id,
    required this.cashierId,
    required this.cashierName,
    required this.startTime,
    this.endTime,
    required this.startingCash,
    this.totalSalesCash = 0.0,
    this.totalCashIn = 0.0,
    this.totalCashOut = 0.0,
    this.totalReturnCash = 0.0,
    this.actualCash,
    this.difference,
    this.status = 'open',
    this.note = '',
  });

  double get expectedCash =>
      startingCash + totalSalesCash + totalCashIn - totalCashOut - totalReturnCash;

  bool get isOpen => status == 'open';

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'cashier_id': cashierId,
      'cashier_name': cashierName,
      'start_time': startTime.toIso8601String(),
      'end_time': endTime?.toIso8601String(),
      'starting_cash': startingCash,
      'total_sales_cash': totalSalesCash,
      'total_cash_in': totalCashIn,
      'total_cash_out': totalCashOut,
      'total_return_cash': totalReturnCash,
      'actual_cash': actualCash,
      'difference': difference,
      'status': status,
      'note': note,
    };
  }

  factory ShiftModel.fromMap(Map<String, dynamic> map) {
    return ShiftModel(
      id: map['id'],
      cashierId: map['cashier_id'],
      cashierName: map['cashier_name'] ?? 'Kasir',
      startTime: DateTime.parse(map['start_time']),
      endTime: map['end_time'] != null ? DateTime.parse(map['end_time']) : null,
      startingCash: (map['starting_cash'] as num).toDouble(),
      totalSalesCash: (map['total_sales_cash'] as num?)?.toDouble() ?? 0.0,
      totalCashIn: (map['total_cash_in'] as num?)?.toDouble() ?? 0.0,
      totalCashOut: (map['total_cash_out'] as num?)?.toDouble() ?? 0.0,
      totalReturnCash: (map['total_return_cash'] as num?)?.toDouble() ?? 0.0,
      actualCash: (map['actual_cash'] as num?)?.toDouble(),
      difference: (map['difference'] as num?)?.toDouble(),
      status: map['status'] ?? 'open',
      note: map['note'] ?? '',
    );
  }
}
