import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';

/// Security utilities for password and PIN hashing without storing plaintext credentials.
class SecurityHelper {
  static const int _iterations = 1000;

  /// Generates a cryptographically secure random salt encoded in base64url.
  static String generateSalt([int length = 16]) {
    final rng = Random.secure();
    final bytes = List<int>.generate(length, (_) => rng.nextInt(256));
    return base64UrlEncode(bytes);
  }

  /// Derives a salted iterative HMAC-SHA256 hash string for passwords and PINs.
  static String hashSecret(String secret, String salt) {
    final key = utf8.encode(salt);
    List<int> block = utf8.encode('$salt:$secret');
    final hmac = Hmac(sha256, key);
    for (int i = 0; i < _iterations; i++) {
      block = hmac.convert(block).bytes;
    }
    return base64UrlEncode(block);
  }

  /// Verifies a plaintext [secret] against [expectedHash] using constant-time comparison.
  static bool verifySecret(String secret, String salt, String expectedHash) {
    if (salt.isEmpty || expectedHash.isEmpty) return false;
    final actualHash = hashSecret(secret, salt);
    if (actualHash.length != expectedHash.length) return false;
    int diff = 0;
    for (int i = 0; i < actualHash.length; i++) {
      diff |= actualHash.codeUnitAt(i) ^ expectedHash.codeUnitAt(i);
    }
    return diff == 0;
  }
}
