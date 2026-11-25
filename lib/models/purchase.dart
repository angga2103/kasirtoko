class PurchaseItemModel {
  final int? id;
  final int? purchaseId;
  final int productId;
  final String productName;
  final double qty;
  final String unitName;
  final double conversionFactor;
  final double costPrice; // Cost per chosen unit
  final double subtotal;

  PurchaseItemModel({
    this.id,
    this.purchaseId,
    required this.productId,
    required this.productName,
    required this.qty,
    this.unitName = 'Pcs',
    this.conversionFactor = 1.0,
    required this.costPrice,
    required this.subtotal,
  });

  double get baseStockQty => qty * conversionFactor;

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'purchase_id': purchaseId,
        'product_id': productId,
        'product_name': productName,
        'qty': qty,
        'unit_name': unitName,
        'conversion_factor': conversionFactor,
        'cost_price': costPrice,
        'subtotal': subtotal,
      };

  factory PurchaseItemModel.fromMap(Map<String, dynamic> map) {
    return PurchaseItemModel(
      id: map['id'] as int?,
      purchaseId: map['purchase_id'] as int?,
      productId: map['product_id'] as int,
      productName: (map['product_name'] ?? '').toString(),
      qty: (map['qty'] as num).toDouble(),
      unitName: (map['unit_name'] ?? 'Pcs').toString(),
      conversionFactor: (map['conversion_factor'] as num?)?.toDouble() ?? 1.0,
      costPrice: (map['cost_price'] as num).toDouble(),
      subtotal: (map['subtotal'] as num).toDouble(),
    );
  }
}

class PurchaseModel {
  final int? id;
  final String purchaseNumber;
  final String supplierName;
  final String supplierPhone;
  final DateTime date;
  final double totalAmount;
  final String paymentMethod; // 'kas_laci' | 'transfer' | 'hutang' | 'campuran'
  final double cashPaid;
  final double transferPaid;
  final double creditAmount;
  final String transferAccount;
  final String transferRef;
  final DateTime? dueDate;
  final String status; // 'completed' | 'voided'
  final int? shiftId;
  final String note;
  final String createdBy;
  final List<PurchaseItemModel> items;

  PurchaseModel({
    this.id,
    required this.purchaseNumber,
    required this.supplierName,
    this.supplierPhone = '',
    DateTime? date,
    required this.totalAmount,
    this.paymentMethod = 'kas_laci',
    double? cashPaid,
    double? transferPaid,
    double? creditAmount,
    this.transferAccount = '',
    this.transferRef = '',
    this.dueDate,
    this.status = 'completed',
    this.shiftId,
    this.note = '',
    this.createdBy = 'Admin',
    List<PurchaseItemModel>? items,
  })  : date = date ?? DateTime.now(),
        cashPaid = cashPaid ?? (paymentMethod == 'kas_laci' ? totalAmount : 0.0),
        transferPaid = transferPaid ?? (paymentMethod == 'transfer' ? totalAmount : 0.0),
        creditAmount = creditAmount ?? (paymentMethod == 'hutang' ? totalAmount : 0.0),
        items = items ?? [];

  bool get isVoided => status == 'voided';

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'purchase_number': purchaseNumber,
        'supplier_name': supplierName,
        'supplier_phone': supplierPhone,
        'date': date.toIso8601String(),
        'total_amount': totalAmount,
        'payment_method': paymentMethod,
        'cash_paid': cashPaid,
        'transfer_paid': transferPaid,
        'credit_amount': creditAmount,
        'transfer_account': transferAccount,
        'transfer_ref': transferRef,
        'due_date': dueDate?.toIso8601String(),
        'status': status,
        if (shiftId != null) 'shift_id': shiftId,
        'note': note,
        'created_by': createdBy,
      };

  factory PurchaseModel.fromMap(Map<String, dynamic> map) {
    final total = (map['total_amount'] as num).toDouble();
    final method = (map['payment_method'] ?? 'kas_laci').toString();
    return PurchaseModel(
      id: map['id'] as int?,
      purchaseNumber: (map['purchase_number'] ?? '').toString(),
      supplierName: (map['supplier_name'] ?? '').toString(),
      supplierPhone: (map['supplier_phone'] ?? '').toString(),
      date: DateTime.parse(map['date']),
      totalAmount: total,
      paymentMethod: method,
      cashPaid: (map['cash_paid'] as num?)?.toDouble() ?? (method == 'kas_laci' ? total : 0.0),
      transferPaid: (map['transfer_paid'] as num?)?.toDouble() ?? (method == 'transfer' ? total : 0.0),
      creditAmount: (map['credit_amount'] as num?)?.toDouble() ?? (method == 'hutang' ? total : 0.0),
      transferAccount: (map['transfer_account'] ?? '').toString(),
      transferRef: (map['transfer_ref'] ?? '').toString(),
      dueDate: map['due_date'] != null ? DateTime.tryParse(map['due_date'].toString()) : null,
      status: (map['status'] ?? 'completed').toString(),
      shiftId: map['shift_id'] as int?,
      note: (map['note'] ?? '').toString(),
      createdBy: (map['created_by'] ?? 'Admin').toString(),
    );
  }
}

class SupplierDebtModel {
  final int? id;
  final int purchaseId;
  final String purchaseNumber;
  final String supplierName;
  final String supplierPhone;
  final double totalDebt;
  final double paidDebt;
  final DateTime purchaseDate;
  final DateTime? dueDate;
  final DateTime? lastPaymentDate;
  final String status; // 'belum_lunas' | 'cicilan' | 'lunas' | 'dibatalkan'
  final String note;

  SupplierDebtModel({
    this.id,
    required this.purchaseId,
    required this.purchaseNumber,
    required this.supplierName,
    this.supplierPhone = '',
    required this.totalDebt,
    this.paidDebt = 0.0,
    required this.purchaseDate,
    this.dueDate,
    this.lastPaymentDate,
    this.status = 'belum_lunas',
    this.note = '',
  });

  double get remainingDebt => (totalDebt - paidDebt).clamp(0.0, double.infinity);
  bool get isPaidOff => status == 'lunas' || remainingDebt <= 0.001;
  bool get isCancelled => status == 'dibatalkan';
  bool get isOverdue {
    if (isPaidOff || isCancelled || dueDate == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final due = DateTime(dueDate!.year, dueDate!.month, dueDate!.day);
    return due.isBefore(today);
  }

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'purchase_id': purchaseId,
        'purchase_number': purchaseNumber,
        'supplier_name': supplierName,
        'supplier_phone': supplierPhone,
        'total_debt': totalDebt,
        'paid_debt': paidDebt,
        'purchase_date': purchaseDate.toIso8601String(),
        'due_date': dueDate?.toIso8601String(),
        'last_payment_date': lastPaymentDate?.toIso8601String(),
        'status': status,
        'note': note,
      };

  factory SupplierDebtModel.fromMap(Map<String, dynamic> map) {
    return SupplierDebtModel(
      id: map['id'] as int?,
      purchaseId: map['purchase_id'] as int,
      purchaseNumber: (map['purchase_number'] ?? '').toString(),
      supplierName: (map['supplier_name'] ?? '').toString(),
      supplierPhone: (map['supplier_phone'] ?? '').toString(),
      totalDebt: (map['total_debt'] as num).toDouble(),
      paidDebt: (map['paid_debt'] as num?)?.toDouble() ?? 0.0,
      purchaseDate: DateTime.parse(map['purchase_date']),
      dueDate: map['due_date'] != null ? DateTime.tryParse(map['due_date'].toString()) : null,
      lastPaymentDate: map['last_payment_date'] != null
          ? DateTime.tryParse(map['last_payment_date'].toString())
          : null,
      status: (map['status'] ?? 'belum_lunas').toString(),
      note: (map['note'] ?? '').toString(),
    );
  }
}

class SupplierDebtPaymentModel {
  final int? id;
  final int supplierDebtId;
  final double amount;
  final String paymentSource; // 'kas_laci' | 'transfer'
  final String accountName;
  final String referenceNumber;
  final int? shiftId;
  final String paidBy;
  final DateTime date;
  final String note;

  SupplierDebtPaymentModel({
    this.id,
    required this.supplierDebtId,
    required this.amount,
    required this.paymentSource,
    this.accountName = 'Laci Kasir',
    this.referenceNumber = '',
    this.shiftId,
    this.paidBy = 'Admin',
    DateTime? date,
    this.note = '',
  }) : date = date ?? DateTime.now();

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'supplier_debt_id': supplierDebtId,
        'amount': amount,
        'payment_source': paymentSource,
        'account_name': accountName,
        'reference_number': referenceNumber,
        if (shiftId != null) 'shift_id': shiftId,
        'paid_by': paidBy,
        'date': date.toIso8601String(),
        'note': note,
      };

  factory SupplierDebtPaymentModel.fromMap(Map<String, dynamic> map) {
    return SupplierDebtPaymentModel(
      id: map['id'] as int?,
      supplierDebtId: map['supplier_debt_id'] as int,
      amount: (map['amount'] as num).toDouble(),
      paymentSource: (map['payment_source'] ?? 'kas_laci').toString(),
      accountName: (map['account_name'] ?? 'Laci Kasir').toString(),
      referenceNumber: (map['reference_number'] ?? '').toString(),
      shiftId: map['shift_id'] as int?,
      paidBy: (map['paid_by'] ?? 'Admin').toString(),
      date: DateTime.parse(map['date']),
      note: (map['note'] ?? '').toString(),
    );
  }
}
