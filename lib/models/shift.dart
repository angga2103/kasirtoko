class ShiftModel {
  final int? id;
  final int cashierId;
  final String cashierName;
  final String terminalId;
  final int cashRegisterId;
  final String drawerMode; // 'SHARED_DRAWER' | 'INDIVIDUAL_DRAWER'
  final DateTime startTime;
  final DateTime? endTime;
  final double startingCash;
  final double totalSalesCash;
  final double totalSalesQris;
  final double totalSalesTransfer;
  final double totalSalesKasbon;
  final double totalSalesCredit;
  final double totalCashIn;
  final double totalCashOut;
  final double totalReturnCash;
  final double? actualCash;
  final double? difference;
  final String status; // 'open', 'closed'
  final String note;

  ShiftModel({
    this.id,
    required this.cashierId,
    required this.cashierName,
    this.terminalId = 'ADMIN',
    this.cashRegisterId = 1,
    this.drawerMode = 'SHARED_DRAWER',
    required this.startTime,
    this.endTime,
    required this.startingCash,
    this.totalSalesCash = 0.0,
    this.totalSalesQris = 0.0,
    this.totalSalesTransfer = 0.0,
    this.totalSalesKasbon = 0.0,
    this.totalSalesCredit = 0.0,
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

  double get totalAllSales =>
      totalSalesCash + totalSalesQris + totalSalesTransfer + totalSalesKasbon + totalSalesCredit;

  bool get isOpen => status == 'open';

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'cashier_id': cashierId,
      'cashier_name': cashierName,
      'terminal_id': terminalId,
      'cash_register_id': cashRegisterId,
      'drawer_mode': drawerMode,
      'start_time': startTime.toIso8601String(),
      'end_time': endTime?.toIso8601String(),
      'starting_cash': startingCash,
      'total_sales_cash': totalSalesCash,
      'total_sales_qris': totalSalesQris,
      'total_sales_transfer': totalSalesTransfer,
      'total_sales_kasbon': totalSalesKasbon,
      'total_sales_credit': totalSalesCredit,
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
    final rawTerm = (map['terminal_id'] ?? '').toString().trim();
    return ShiftModel(
      id: map['id'] as int?,
      cashierId: map['cashier_id'] ?? 1,
      cashierName: map['cashier_name'] ?? 'Kasir',
      terminalId: rawTerm.isNotEmpty ? rawTerm : 'ADMIN',
      cashRegisterId: (map['cash_register_id'] as num?)?.toInt() ?? 1,
      drawerMode: (map['drawer_mode'] ?? 'SHARED_DRAWER').toString(),
      startTime: DateTime.parse(map['start_time']),
      endTime: map['end_time'] != null ? DateTime.parse(map['end_time']) : null,
      startingCash: (map['starting_cash'] as num).toDouble(),
      totalSalesCash: (map['total_sales_cash'] as num?)?.toDouble() ?? 0.0,
      totalSalesQris: (map['total_sales_qris'] as num?)?.toDouble() ?? 0.0,
      totalSalesTransfer: (map['total_sales_transfer'] as num?)?.toDouble() ?? 0.0,
      totalSalesKasbon: (map['total_sales_kasbon'] as num?)?.toDouble() ?? 0.0,
      totalSalesCredit: (map['total_sales_credit'] as num?)?.toDouble() ?? 0.0,
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
