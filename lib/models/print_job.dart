class PrintJobStatus {
  static const String queued = 'queued';
  static const String processing = 'processing';
  static const String submitted = 'submitted';
  static const String retrying = 'retrying';
  static const String failed = 'failed';
  static const String cancelled = 'cancelled';
}

class PrintJobType {
  static const String receipt = 'receipt';
  static const String reprint = 'reprint';
  static const String manualDrawer = 'manual_drawer';
}

class PrintJobModel {
  final int? id;
  final String jobUuid;
  final String terminalId;
  final int? cashierId;
  final int? transactionId;
  final String invoiceNumber;
  final int? printerId;
  final String jobType;
  final bool isReprint;
  final bool openDrawerRequested;
  final bool drawerOpened;
  final bool drawerPulseSent;
  final String status;
  final int attempts;
  final String errorMessage;
  final String? idempotencyKey;
  final String payloadJson;
  final String createdAt;
  final String? completedAt;

  const PrintJobModel({
    this.id,
    required this.jobUuid,
    required this.terminalId,
    this.cashierId,
    this.transactionId,
    this.invoiceNumber = '',
    this.printerId,
    this.jobType = PrintJobType.receipt,
    this.isReprint = false,
    this.openDrawerRequested = false,
    this.drawerOpened = false,
    this.drawerPulseSent = false,
    this.status = PrintJobStatus.queued,
    this.attempts = 0,
    this.errorMessage = '',
    this.idempotencyKey,
    this.payloadJson = '',
    required this.createdAt,
    this.completedAt,
  });

  bool get isTerminalState =>
      status == PrintJobStatus.submitted ||
      status == PrintJobStatus.failed ||
      status == PrintJobStatus.cancelled;

  factory PrintJobModel.fromMap(Map<String, dynamic> map) {
    return PrintJobModel(
      id: (map['id'] as num?)?.toInt(),
      jobUuid: (map['job_uuid'] ?? '').toString(),
      terminalId: (map['terminal_id'] ?? '').toString(),
      cashierId: (map['cashier_id'] as num?)?.toInt(),
      transactionId: (map['transaction_id'] as num?)?.toInt(),
      invoiceNumber: (map['invoice_number'] ?? '').toString(),
      printerId: (map['printer_id'] as num?)?.toInt(),
      jobType: (map['job_type'] ?? PrintJobType.receipt).toString(),
      isReprint: (map['is_reprint'] ?? 0) == 1,
      openDrawerRequested: (map['open_drawer_requested'] ?? 0) == 1,
      drawerOpened: (map['drawer_opened'] ?? 0) == 1,
      drawerPulseSent: (map['drawer_pulse_sent'] ?? 0) == 1,
      status: (map['status'] ?? PrintJobStatus.queued).toString(),
      attempts: (map['attempts'] as num?)?.toInt() ?? 0,
      errorMessage: (map['error_message'] ?? '').toString(),
      idempotencyKey: map['idempotency_key']?.toString(),
      payloadJson: (map['payload_json'] ?? '').toString(),
      createdAt: (map['created_at'] ?? '').toString(),
      completedAt: map['completed_at']?.toString(),
    );
  }

  Map<String, dynamic> toApiJson() => {
        'id': id,
        'job_id': jobUuid,
        'job_uuid': jobUuid,
        'terminal_id': terminalId,
        'cashier_id': cashierId,
        'transaction_id': transactionId,
        'invoice_number': invoiceNumber,
        'printer_id': printerId,
        'job_type': jobType,
        'is_reprint': isReprint,
        'open_drawer_requested': openDrawerRequested,
        'drawer_opened': drawerOpened,
        'drawer_pulse_sent': drawerPulseSent,
        'status': status,
        'attempts': attempts,
        'error_message': errorMessage,
        'created_at': createdAt,
        'completed_at': completedAt,
      };
}
