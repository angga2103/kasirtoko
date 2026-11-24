class CustomerDebtModel {
  final int? id;
  final String customerName;
  final String customerPhone;
  final String invoiceNumber;
  final double totalDebt;
  final double paidDebt;
  final DateTime transactionDate;
  final DateTime dueDate;
  final DateTime? lastPaymentDate;
  final String note;

  CustomerDebtModel({
    this.id,
    required this.customerName,
    required this.customerPhone,
    required this.invoiceNumber,
    required this.totalDebt,
    this.paidDebt = 0.0,
    required this.transactionDate,
    required this.dueDate,
    this.lastPaymentDate,
    this.note = '',
  });

  double get remainingDebt => totalDebt - paidDebt;
  bool get isPaidOff => remainingDebt <= 0;

  bool get isOverdue {
    if (isPaidOff) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final due = DateTime(dueDate.year, dueDate.month, dueDate.day);
    return due.isBefore(today);
  }

  int get daysUntilDue {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final due = DateTime(dueDate.year, dueDate.month, dueDate.day);
    return due.difference(today).inDays;
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'customer_name': customerName,
      'customer_phone': customerPhone,
      'invoice_number': invoiceNumber,
      'total_debt': totalDebt,
      'paid_debt': paidDebt,
      'transaction_date': transactionDate.toIso8601String(),
      'due_date': dueDate.toIso8601String(),
      'last_payment_date': lastPaymentDate?.toIso8601String(),
      'note': note,
    };
  }

  factory CustomerDebtModel.fromMap(Map<String, dynamic> map) {
    return CustomerDebtModel(
      id: map['id'],
      customerName: map['customer_name'] ?? 'Pelanggan',
      customerPhone: map['customer_phone'] ?? '',
      invoiceNumber: map['invoice_number'] ?? '',
      totalDebt: (map['total_debt'] as num).toDouble(),
      paidDebt: (map['paid_debt'] as num?)?.toDouble() ?? 0.0,
      transactionDate: DateTime.parse(map['transaction_date']),
      dueDate: DateTime.parse(map['due_date']),
      lastPaymentDate: map['last_payment_date'] != null
          ? DateTime.parse(map['last_payment_date'])
          : null,
      note: map['note'] ?? '',
    );
  }
}
