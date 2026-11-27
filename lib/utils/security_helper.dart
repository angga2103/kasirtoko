import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:pointycastle/export.dart';

abstract class PepperProvider {
  Future<Uint8List> getPepperBytes();
}

/// Production Android Keystore-backed pepper provider.
/// The pepper is generated once inside Android and stored encrypted with an
/// AES-256-GCM Keystore key in private preferences (excluded from DB & cloud backups).
class AndroidKeystorePepperProvider implements PepperProvider {
  static const MethodChannel _channel = MethodChannel('com.kasirtoko.app/security');
  Uint8List? _cachedPepper;

  @override
  Future<Uint8List> getPepperBytes() async {
    if (_cachedPepper != null) return _cachedPepper!;
    final b64 = await _channel.invokeMethod<String>('getOrCreatePepper');
    if (b64 == null || b64.isEmpty) {
      throw StateError('Android Keystore gagal mengembalikan pepper kriptografis.');
    }
    final normalized = base64Url.normalize(b64);
    _cachedPepper = Uint8List.fromList(base64Url.decode(normalized));
    return _cachedPepper!;
  }

  void clearCache() {
    _cachedPepper = null;
  }
}

/// Test-only / non-Android ephemeral pepper provider (never persisted into SQLite).
class InMemoryPepperProvider implements PepperProvider {
  Uint8List _bytes;

  InMemoryPepperProvider([Uint8List? initial])
      : _bytes = initial ?? _generateRandomBytes(32);

  static Uint8List _generateRandomBytes(int len) {
    final rng = Random.secure();
    return Uint8List.fromList(List<int>.generate(len, (_) => rng.nextInt(256)));
  }

  @override
  Future<Uint8List> getPepperBytes() async => _bytes;

  void rotateForTesting(Uint8List nextBytes) {
    _bytes = nextBytes;
  }
}

class ParsedV2Hash {
  final String algorithm;
  final int version;
  final int iterations;
  final int keyLength;
  final String domain;
  final bool peppered;
  final String salt;
  final String hashBase64Url;

  const ParsedV2Hash({
    required this.algorithm,
    required this.version,
    required this.iterations,
    required this.keyLength,
    required this.domain,
    required this.peppered,
    required this.salt,
    required this.hashBase64Url,
  });
}

class SecurityBenchmarkResult {
  final int iterations;
  final int keyLength;
  final int elapsedMs;
  final String engine;

  const SecurityBenchmarkResult({
    required this.iterations,
    required this.keyLength,
    required this.elapsedMs,
    required this.engine,
  });
}

/// Security utilities for password and PIN hashing.
///
/// v2 Standard:
/// - Tested RFC 8018 PBKDF2-HMAC-SHA256 (`pointycastle` PBKDF2KeyDerivator, or
///   hardware-accelerated Android SecretKeyFactory PBKDF2WithHmacSHA256 on API 26+).
/// - Default 600,000 iterations, 32-byte derived key.
/// - Unique per-credential cryptographic random salt (PIN salt strictly separated from password salt).
/// - Domain separation (`pin` vs `pw`) + Android Keystore-backed pepper (`p=1`).
/// - Versioned PHC-style string encoding derivation parameters.
///
/// Legacy v1 (`hashSecret` / `verifySecret`) is retained solely for transparent
/// migration of existing v1-v4 accounts on first successful authentication.
class SecurityHelper {
  static const int legacyV1Iterations = 1000;
  static const int defaultPbkdf2Iterations = 600000;
  static const int defaultKeyLength = 32;
  static const String hashVersionLegacyV1 = 'legacy_v1';
  static const String hashVersionV2Pbkdf2 = 'v2_pbkdf2_sha256';
  static const String domainPin = 'pin';
  static const String domainPassword = 'pw';

  static const MethodChannel _channel = MethodChannel('com.kasirtoko.app/security');

  static final AndroidKeystorePepperProvider _androidPepperProvider = AndroidKeystorePepperProvider();
  static PepperProvider? _overridePepperProvider;
  static int? _overrideIterationsForTest;

  static const int testFixturePbkdf2Iterations = 50000;

  static bool get hasTestIterationOverride => _overrideIterationsForTest != null;
  static int get activeIterations => _overrideIterationsForTest ?? defaultPbkdf2Iterations;

  @visibleForTesting
  static void configureForTesting({
    PepperProvider? pepperProvider,
    int? iterations,
  }) {
    _overridePepperProvider = pepperProvider;
    _overrideIterationsForTest = iterations;
  }

  @visibleForTesting
  static void resetTestConfiguration() {
    _overridePepperProvider = null;
    _overrideIterationsForTest = null;
  }

  static PepperProvider _resolvePepperProvider() {
    if (_overridePepperProvider != null) return _overridePepperProvider!;
    if (Platform.isAndroid) return _androidPepperProvider;
    // Non-Android host test runner fallback if test did not inject explicit provider
    _overridePepperProvider = InMemoryPepperProvider(
      Uint8List.fromList(utf8.encode('kasirtoko_host_test_ephemeral_pepper_32b')),
    );
    return _overridePepperProvider!;
  }

  /// Generates a cryptographically secure random salt encoded in base64url.
  static String generateSalt([int length = 16]) {
    final rng = Random.secure();
    final bytes = List<int>.generate(length, (_) => rng.nextInt(256));
    return base64UrlEncode(bytes);
  }

  static bool constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    int diff = 0;
    for (int i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  static bool isV2PhcHash(String hash) {
    return hash.startsWith(r'$pbkdf2-sha256$');
  }

  static ParsedV2Hash? parseV2Hash(String encoded) {
    if (!isV2PhcHash(encoded)) return null;
    final parts = encoded.split(r'$');
    // Expected: ['', 'pbkdf2-sha256', 'v=2,i=600000,l=32,d=pin,p=1', '<salt>', '<hash>']
    if (parts.length != 5) return null;
    final algo = parts[1];
    final paramStr = parts[2];
    final salt = parts[3];
    final hash = parts[4];
    if (algo != 'pbkdf2-sha256' || salt.isEmpty || hash.isEmpty) return null;

    int version = 2;
    int iterations = defaultPbkdf2Iterations;
    int keyLength = defaultKeyLength;
    String domain = domainPin;
    bool peppered = true;

    for (final kv in paramStr.split(',')) {
      final eq = kv.indexOf('=');
      if (eq <= 0) continue;
      final k = kv.substring(0, eq).trim();
      final v = kv.substring(eq + 1).trim();
      switch (k) {
        case 'v':
          version = int.tryParse(v) ?? version;
          break;
        case 'i':
          iterations = int.tryParse(v) ?? iterations;
          break;
        case 'l':
          keyLength = int.tryParse(v) ?? keyLength;
          break;
        case 'd':
          domain = v;
          break;
        case 'p':
          peppered = v == '1' || v.toLowerCase() == 'true';
          break;
      }
    }

    if (iterations < 1 || keyLength < 16 || keyLength > 128) return null;
    return ParsedV2Hash(
      algorithm: algo,
      version: version,
      iterations: iterations,
      keyLength: keyLength,
      domain: domain,
      peppered: peppered,
      salt: salt,
      hashBase64Url: hash,
    );
  }

  /// Prepares pure-ASCII PBKDF2 input combining domain separation and optional Keystore pepper.
  /// Using base64url(HMAC-SHA256(pepper, "$domain:$secret")) guarantees 100% byte-for-byte
  /// parity between Java PBEKeySpec(char[]) and Dart PointyCastle UTF-8 bytes.
  static Future<String> _prepareInputAscii({
    required String secret,
    required String domain,
    required bool usePepper,
  }) async {
    if (!usePepper) {
      return base64UrlEncode(utf8.encode('$domain:$secret'));
    }
    final pepperBytes = await _resolvePepperProvider().getPepperBytes();
    final mac = Hmac(sha256, pepperBytes).convert(utf8.encode('$domain:$secret')).bytes;
    return base64UrlEncode(mac);
  }

  /// Computes a keyed lookup digest for fast O(1) candidate identification before
  /// running full 600,000-iteration PBKDF2 verification. Protected by Android Keystore pepper
  /// (never usable as authentication proof on its own).
  static Future<String> computePinLookupDigest(String pin) async {
    final pepperBytes = await _resolvePepperProvider().getPepperBytes();
    final digest = Hmac(sha256, pepperBytes).convert(utf8.encode('lookup:$domainPin:$pin')).bytes;
    return base64UrlEncode(digest);
  }

  /// Tested RFC 8018 PBKDF2-HMAC-SHA256 derivation via PointyCastle (native API26+ on Android).
  static Future<Uint8List> deriveKeyBytes({
    required String passphraseAscii,
    required Uint8List saltBytes,
    required int iterations,
    int keyLength = defaultKeyLength,
  }) =>
      _derivePbkdf2(
        inputAscii: passphraseAscii,
        saltBytes: saltBytes,
        iterations: iterations,
        keyLength: keyLength,
      );

  /// Tested RFC 8018 PBKDF2-HMAC-SHA256 derivation via PointyCastle.
  static Uint8List derivePbkdf2PointyCastle({
    required Uint8List inputBytes,
    required Uint8List saltBytes,
    required int iterations,
    int keyLength = defaultKeyLength,
  }) {
    final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64));
    derivator.init(Pbkdf2Parameters(saltBytes, iterations, keyLength));
    return derivator.process(inputBytes);
  }

  static Future<Uint8List> _derivePbkdf2({
    required String inputAscii,
    required Uint8List saltBytes,
    required int iterations,
    required int keyLength,
  }) async {
    if (Platform.isAndroid) {
      try {
        final nativeBytes = await _channel.invokeMethod<Uint8List>('derivePbkdf2HmacSha256', {
          'secretAscii': inputAscii,
          'salt': saltBytes,
          'iterations': iterations,
          'keyLength': keyLength,
        });
        if (nativeBytes != null && nativeBytes.length == keyLength) {
          return nativeBytes;
        }
      } on PlatformException {
        // Fallback transparently to PointyCastle on API < 26
      } on MissingPluginException {
        // Fallback transparently to PointyCastle in test environments
      }
    }

    final inputBytes = Uint8List.fromList(utf8.encode(inputAscii));
    if (iterations >= 20000) {
      return await Isolate.run(
        () => derivePbkdf2PointyCastle(
          inputBytes: inputBytes,
          saltBytes: saltBytes,
          iterations: iterations,
          keyLength: keyLength,
        ),
      );
    }
    return derivePbkdf2PointyCastle(
      inputBytes: inputBytes,
      saltBytes: saltBytes,
      iterations: iterations,
      keyLength: keyLength,
    );
  }

  /// Derives a v2 PBKDF2-HMAC-SHA256 PHC string with unique salt, domain separation,
  /// and Android Keystore pepper.
  static Future<({String salt, String hash})> hashSecretV2(
    String secret, {
    String? salt,
    String domain = domainPin,
    int? iterations,
    int keyLength = defaultKeyLength,
    bool usePepper = true,
  }) async {
    final cleanSalt = (salt != null && salt.isNotEmpty) ? salt : generateSalt(16);
    final iters = iterations ?? activeIterations;
    final inputAscii = await _prepareInputAscii(
      secret: secret,
      domain: domain,
      usePepper: usePepper,
    );
    final saltBytes = Uint8List.fromList(utf8.encode(cleanSalt));
    final derived = await _derivePbkdf2(
      inputAscii: inputAscii,
      saltBytes: saltBytes,
      iterations: iters,
      keyLength: keyLength,
    );
    final derivedB64 = base64UrlEncode(derived);
    final phc =
        '\$pbkdf2-sha256\$v=2,i=$iters,l=$keyLength,d=$domain,p=${usePepper ? 1 : 0}\$$cleanSalt\$$derivedB64';
    return (salt: cleanSalt, hash: phc);
  }

  /// Verifies a plaintext [secret] against a versioned v2 PHC string using constant-time comparison.
  static Future<bool> verifySecretV2(
    String secret,
    String storedPhcHash, {
    String? expectedSalt,
    String? expectedDomain,
  }) async {
    final parsed = parseV2Hash(storedPhcHash);
    if (parsed == null) return false;
    if (expectedSalt != null && expectedSalt.isNotEmpty && parsed.salt != expectedSalt) {
      return false;
    }
    if (expectedDomain != null && expectedDomain.isNotEmpty && parsed.domain != expectedDomain) {
      return false;
    }

    final inputAscii = await _prepareInputAscii(
      secret: secret,
      domain: parsed.domain,
      usePepper: parsed.peppered,
    );
    final saltBytes = Uint8List.fromList(utf8.encode(parsed.salt));
    final derived = await _derivePbkdf2(
      inputAscii: inputAscii,
      saltBytes: saltBytes,
      iterations: parsed.iterations,
      keyLength: parsed.keyLength,
    );
    final actualB64 = base64UrlEncode(derived);
    return constantTimeEquals(actualB64, parsed.hashBase64Url);
  }

  /// Unified verifier supporting both v2 PBKDF2-HMAC-SHA256 PHC hashes and legacy v1 hashes.
  static Future<({bool valid, bool needsRehash})> verifyCredential({
    required String secret,
    required String storedHash,
    required String legacyOrV2Salt,
    String? expectedDomain,
  }) async {
    if (storedHash.isEmpty) return (valid: false, needsRehash: false);

    if (isV2PhcHash(storedHash)) {
      final parsed = parseV2Hash(storedHash);
      final ok = await verifySecretV2(
        secret,
        storedHash,
        expectedSalt: legacyOrV2Salt,
        expectedDomain: expectedDomain,
      );
      final needsUpgrade = ok && parsed != null && parsed.iterations < activeIterations;
      return (valid: ok, needsRehash: needsUpgrade);
    }

    final legacyOk = verifyLegacyV1Secret(secret, legacyOrV2Salt, storedHash);
    return (valid: legacyOk, needsRehash: legacyOk);
  }

  /// Measures real PBKDF2-HMAC-SHA256 execution time on the current runtime.
  static Future<SecurityBenchmarkResult> benchmarkPbkdf2({
    int? iterations,
    int keyLength = defaultKeyLength,
  }) async {
    final iters = iterations ?? activeIterations;
    final sw = Stopwatch()..start();
    String engine = 'pointycastle_dart';
    final saltBytes = Uint8List.fromList(utf8.encode('benchmark_salt_16'));
    const inputAscii = 'benchmark_ascii_input_key';

    if (Platform.isAndroid) {
      try {
        final res = await _channel.invokeMethod<Uint8List>('derivePbkdf2HmacSha256', {
          'secretAscii': inputAscii,
          'salt': saltBytes,
          'iterations': iters,
          'keyLength': keyLength,
        });
        if (res != null && res.length == keyLength) {
          engine = 'android_native_pbkdf2';
        } else {
          await _derivePbkdf2(
            inputAscii: inputAscii,
            saltBytes: saltBytes,
            iterations: iters,
            keyLength: keyLength,
          );
        }
      } catch (_) {
        derivePbkdf2PointyCastle(
          inputBytes: Uint8List.fromList(utf8.encode(inputAscii)),
          saltBytes: saltBytes,
          iterations: iters,
          keyLength: keyLength,
        );
      }
    } else {
      await _derivePbkdf2(
        inputAscii: inputAscii,
        saltBytes: saltBytes,
        iterations: iters,
        keyLength: keyLength,
      );
    }
    sw.stop();
    return SecurityBenchmarkResult(
      iterations: iters,
      keyLength: keyLength,
      elapsedMs: sw.elapsedMilliseconds,
      engine: engine,
    );
  }

  // ==================== LEGACY V1 COMPATIBILITY ====================

  /// Legacy v1 iterative HMAC-SHA256 (1000 rounds). Kept ONLY for verifying existing
  /// legacy_v1 hashes during transparent migration to v2 PBKDF2-HMAC-SHA256.
  static String hashLegacyV1Secret(String secret, String salt) {
    final key = utf8.encode(salt);
    List<int> block = utf8.encode('$salt:$secret');
    final hmac = Hmac(sha256, key);
    for (int i = 0; i < legacyV1Iterations; i++) {
      block = hmac.convert(block).bytes;
    }
    return base64UrlEncode(block);
  }

  /// Verifies a legacy v1 secret in constant time.
  static bool verifyLegacyV1Secret(String secret, String salt, String expectedHash) {
    if (salt.isEmpty || expectedHash.isEmpty) return false;
    final actualHash = hashLegacyV1Secret(secret, salt);
    return constantTimeEquals(actualHash, expectedHash);
  }

  @Deprecated('Use hashSecretV2 for all new hashes; kept for legacy v1 compatibility.')
  static String hashSecret(String secret, String salt) => hashLegacyV1Secret(secret, salt);

  @Deprecated('Use verifyCredential or verifySecretV2; kept for legacy v1 compatibility.')
  static bool verifySecret(String secret, String salt, String expectedHash) =>
      verifyLegacyV1Secret(secret, salt, expectedHash);
}
