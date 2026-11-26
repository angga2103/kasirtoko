class TerminalSessionModel {
  final int? id;
  final String sessionTokenHash;
  final String terminalId;
  final int cashierId;
  final int? shiftId;
  final String issuedAt;
  final String expiresAt;
  final String? revokedAt;

  const TerminalSessionModel({
    this.id,
    required this.sessionTokenHash,
    required this.terminalId,
    required this.cashierId,
    this.shiftId,
    required this.issuedAt,
    required this.expiresAt,
    this.revokedAt,
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
      issuedAt: (map['issued_at'] ?? '').toString(),
      expiresAt: (map['expires_at'] ?? '').toString(),
      revokedAt: map['revoked_at']?.toString(),
    );
  }
}
