class TerminalSessionModel {
  final int? id;
  final String sessionTokenHash;
  final String terminalId;
  final int cashierId;
  final int? shiftId;
  final String deviceName;
  final String issuedAt;
  final String expiresAt;
  final String? revokedAt;
  final String revokedReason;
  final String revokedBy;
  final String lastSeenAt;

  const TerminalSessionModel({
    this.id,
    required this.sessionTokenHash,
    required this.terminalId,
    required this.cashierId,
    this.shiftId,
    this.deviceName = '',
    required this.issuedAt,
    required this.expiresAt,
    this.revokedAt,
    this.revokedReason = '',
    this.revokedBy = '',
    this.lastSeenAt = '',
  });

  bool isExpiredAt(DateTime now) {
    final exp = DateTime.tryParse(expiresAt);
    if (exp == null) return true;
    return !now.isBefore(exp);
  }

  bool get isRevoked => revokedAt != null && revokedAt!.trim().isNotEmpty;

  factory TerminalSessionModel.fromMap(Map<String, dynamic> map) {
    return TerminalSessionModel(
      id: (map['id'] as num?)?.toInt(),
      sessionTokenHash: (map['session_token_hash'] ?? '').toString(),
      terminalId: (map['terminal_id'] ?? '').toString(),
      cashierId: (map['cashier_id'] as num).toInt(),
      shiftId: (map['shift_id'] as num?)?.toInt(),
      deviceName: (map['device_name'] ?? '').toString(),
      issuedAt: (map['issued_at'] ?? '').toString(),
      expiresAt: (map['expires_at'] ?? '').toString(),
      revokedAt: map['revoked_at']?.toString(),
      revokedReason: (map['revoked_reason'] ?? '').toString(),
      revokedBy: (map['revoked_by'] ?? '').toString(),
      lastSeenAt: (map['last_seen_at'] ?? '').toString(),
    );
  }
}

class TerminalSessionDetailModel {
  final TerminalSessionModel session;
  final String cashierName;
  final String cashierRole;
  final String terminalName;
  final String deviceModel;

  const TerminalSessionDetailModel({
    required this.session,
    required this.cashierName,
    required this.cashierRole,
    required this.terminalName,
    this.deviceModel = '',
  });

  bool get isActive => !session.isRevoked && !session.isExpiredAt(DateTime.now());
}
