import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../../utils/security_helper.dart';

class ReplayCheckResult {
  final bool valid;
  final String errorCode;
  final String message;

  const ReplayCheckResult({
    required this.valid,
    this.errorCode = '',
    this.message = '',
  });
}

class RequestSecurityValidator {
  static const int maxClockDriftMs = 120000;
  static const Duration nonceTtl = Duration(seconds: 150);

  final Map<String, DateTime> _seenNonces = {};
  final Map<String, List<DateTime>> _terminalRequestWindows = {};

  static String sha256HexBytes(List<int> bytes) => sha256.convert(bytes).toString();
  static String sha256HexString(String text) => sha256.convert(utf8.encode(text)).toString();

  static String buildCanonicalPayload({
    required String method,
    required String pathAndQuery,
    required String timestampMs,
    required String nonce,
    required String bodySha256Hex,
  }) {
    return '${method.toUpperCase()}\n$pathAndQuery\n$timestampMs\n$nonce\n$bodySha256Hex';
  }

  static String computeHmacSignature({
    required String deviceSecret,
    required String method,
    required String pathAndQuery,
    required String timestampMs,
    required String nonce,
    required String bodySha256Hex,
  }) {
    final canonical = buildCanonicalPayload(
      method: method,
      pathAndQuery: pathAndQuery,
      timestampMs: timestampMs,
      nonce: nonce,
      bodySha256Hex: bodySha256Hex,
    );
    final hmac = Hmac(sha256, utf8.encode(deviceSecret));
    return hmac.convert(utf8.encode(canonical)).toString();
  }

  static bool verifyHmacSignature({
    required String deviceSecret,
    required String method,
    required String pathAndQuery,
    required String timestampMs,
    required String nonce,
    required String bodySha256Hex,
    required String providedSignature,
  }) {
    final expected = computeHmacSignature(
      deviceSecret: deviceSecret,
      method: method,
      pathAndQuery: pathAndQuery,
      timestampMs: timestampMs,
      nonce: nonce,
      bodySha256Hex: bodySha256Hex,
    );
    return SecurityHelper.constantTimeEquals(expected.toLowerCase(), providedSignature.trim().toLowerCase());
  }

  ReplayCheckResult validateTimestampAndNonce({
    required String terminalId,
    required String timestampHeader,
    required String nonceHeader,
    DateTime? now,
  }) {
    final current = now ?? DateTime.now();
    final tsMs = int.tryParse(timestampHeader.trim());
    if (tsMs == null) {
      return const ReplayCheckResult(
        valid: false,
        errorCode: 'REPLAY_TIMESTAMP_EXPIRED',
        message: 'Header X-Request-Timestamp tidak valid.',
      );
    }
    final diff = (current.millisecondsSinceEpoch - tsMs).abs();
    if (diff > maxClockDriftMs) {
      return const ReplayCheckResult(
        valid: false,
        errorCode: 'REPLAY_TIMESTAMP_EXPIRED',
        message: 'Timestamp permintaan terlalu jauh dari jam server Admin (toleransi ±120 detik).',
      );
    }

    final cleanNonce = nonceHeader.trim();
    if (cleanNonce.length < 8 || cleanNonce.length > 128) {
      return const ReplayCheckResult(
        valid: false,
        errorCode: 'REPLAY_NONCE_DETECTED',
        message: 'Header X-Request-Nonce tidak valid.',
      );
    }

    _pruneExpiredNonces(current);
    final nonceKey = '$terminalId:$cleanNonce';
    if (_seenNonces.containsKey(nonceKey)) {
      return const ReplayCheckResult(
        valid: false,
        errorCode: 'REPLAY_NONCE_DETECTED',
        message: 'Permintaan duplikat/replay ditolak (nonce sudah digunakan).',
      );
    }
    _seenNonces[nonceKey] = current.add(nonceTtl);
    return const ReplayCheckResult(valid: true);
  }

  bool allowRateLimit(
    String terminalId, {
    int maxRequestsPerWindow = 180,
    Duration window = const Duration(seconds: 10),
    DateTime? now,
  }) {
    final current = now ?? DateTime.now();
    final cutoff = current.subtract(window);
    final bucket = _terminalRequestWindows.putIfAbsent(terminalId, () => <DateTime>[]);
    bucket.removeWhere((t) => t.isBefore(cutoff));
    if (bucket.length >= maxRequestsPerWindow) {
      return false;
    }
    bucket.add(current);
    return true;
  }

  void _pruneExpiredNonces(DateTime current) {
    if (_seenNonces.length < 256) return;
    _seenNonces.removeWhere((_, exp) => !current.isBefore(exp));
  }
}
