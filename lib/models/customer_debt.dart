class CustomerDebtPaymentModel {
  final int? id;
  final int debtId;
  final int? customerId;
  final double amount;
  final String paymentMethod; // 'tunai' | 'transfer' | 'qris' | 'retur'
  final int? shiftId;
  final String cashierName;
  final DateTime date;
  final String note;

  CustomerDebtPaymentModel({
    this.id,
    required this.debtId,
    this.customerId,
    required this.amount,
    this.paymentMethod = 'tunai',
    this.shiftId,
    this.cashierName = 'Kasir',
    DateTime? date,
    this.note = '',
  }) : date = date ?? DateTime.now();

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'debt_id': debtId,
        if (customerId != null) 'customer_id': customerId,
        'amount': amount,
        'payment_method': paymentMethod,
        if (shiftId != null) 'shift_id': shiftId,
        'cashier_name': cashierName,
        'date': date.toIso8601String(),
        'note': note,
      };

  factory CustomerDebtPaymentModel.fromMap(Map<String, dynamic> map) {
    return CustomerDebtPaymentModel(
      id: map['id'] as int?,
      debtId: map['debt_id'] as int,
      customerId: map['customer_id'] as int?,
      amount: (map['amount'] as num).toDouble(),
      paymentMethod: (map['payment_method'] ?? 'tunai').toString(),
      shiftId: map['shift_id'] as int?,
      cashierName: (map['cashier_name'] ?? 'Kasir').toString(),
      date: DateTime.parse(map['date']),
      note: (map['note'] ?? '').toString(),
    );
  }
}

class CustomerDebtModel {
  final int? id;
  final int? customerId;
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
    this.customerId,
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

  double get remainingDebt => (totalDebt - paidDebt).clamp(0.0, double.infinity);
  bool get isPaidOff => remainingDebt <= 0.001;

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
      if (id != null) 'id': id,
      if (customerId != null) 'customer_id': customerId,
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
      id: map['id'] as int?,
      customerId: map['customer_id'] as int?,
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
