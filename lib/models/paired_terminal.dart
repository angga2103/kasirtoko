class PairedTerminalModel {
  final int? id;
  final String terminalId;
  final String terminalCode;
  final String terminalName;
  final String deviceModel;
  final String deviceUuid;
  final String deviceSecretHash;
  final String deviceSecretEnc;
  final String deviceTokenHash;
  final int? assignedRegisterId;
  final int? defaultPrinterId;
  final bool allowOpenCashDrawer;
  final bool allowAutoOpenDrawer;
  final bool allowManualOpenDrawer;
  final bool isRevoked;
  final String pairedAt;
  final String? lastSeenAt;

  const PairedTerminalModel({
    this.id,
    required this.terminalId,
    this.terminalCode = '',
    required this.terminalName,
    this.deviceModel = '',
    this.deviceUuid = '',
    required this.deviceSecretHash,
    this.deviceSecretEnc = '',
    required this.deviceTokenHash,
    this.assignedRegisterId,
    this.defaultPrinterId,
    this.allowOpenCashDrawer = false,
    this.allowAutoOpenDrawer = false,
    this.allowManualOpenDrawer = false,
    this.isRevoked = false,
    required this.pairedAt,
    this.lastSeenAt,
  });

  factory PairedTerminalModel.fromMap(Map<String, dynamic> map) {
    final legacyDrawer = (map['allow_open_cash_drawer'] ?? 0) == 1;
    final hasAuto = map.containsKey('allow_auto_open_drawer');
    final hasManual = map.containsKey('allow_manual_open_drawer');
    return PairedTerminalModel(
      id: (map['id'] as num?)?.toInt(),
      terminalId: (map['terminal_id'] ?? '').toString(),
      terminalCode: (map['terminal_code'] ?? map['terminal_id'] ?? '').toString(),
      terminalName: (map['terminal_name'] ?? '').toString(),
      deviceModel: (map['device_model'] ?? '').toString(),
      deviceUuid: (map['device_uuid'] ?? '').toString(),
      deviceSecretHash: (map['device_secret_hash'] ?? '').toString(),
      deviceSecretEnc: (map['device_secret_enc'] ?? '').toString(),
      deviceTokenHash: (map['device_token_hash'] ?? '').toString(),
      assignedRegisterId: (map['assigned_register_id'] as num?)?.toInt(),
      defaultPrinterId: (map['default_printer_id'] as num?)?.toInt(),
      allowOpenCashDrawer: legacyDrawer,
      allowAutoOpenDrawer: hasAuto ? (map['allow_auto_open_drawer'] ?? 0) == 1 : legacyDrawer,
      allowManualOpenDrawer: hasManual ? (map['allow_manual_open_drawer'] ?? 0) == 1 : legacyDrawer,
      isRevoked: (map['is_revoked'] ?? 0) == 1,
      pairedAt: (map['paired_at'] ?? '').toString(),
      lastSeenAt: map['last_seen_at']?.toString(),
    );
  }

  /// Safe public JSON representation for UI/API (NEVER emits secret/token hashes or ciphertexts).
  Map<String, dynamic> toPublicJson() => {
        'id': id,
        'terminal_id': terminalId,
        'terminal_code': terminalCode.isNotEmpty ? terminalCode : terminalId,
        'terminal_name': terminalName,
        'device_model': deviceModel,
        'device_uuid': deviceUuid,
        'assigned_register_id': assignedRegisterId,
        'default_printer_id': defaultPrinterId,
        'allow_auto_open_drawer': allowAutoOpenDrawer,
        'allow_manual_open_drawer': allowManualOpenDrawer,
        'is_revoked': isRevoked,
        'paired_at': pairedAt,
        'last_seen_at': lastSeenAt,
      };
}
