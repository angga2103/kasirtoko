import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:pointycastle/export.dart';

/// Hardware-backed (AndroidKeyStore on Android) or software AES-256-GCM vault
/// for sensitive secrets that MUST NOT live in plaintext SQLite or cloud/DB backups
/// (e.g., terminal HMAC secrets wrapped as `device_secret_enc` and LAN TLS private key).
abstract class SecretVault {
  Future<String> wrapSecret(String plaintext);
  Future<String> unwrapSecret(String envelope);
  Future<void> putRecord(String key, String value);
  Future<String?> getRecord(String key);
  Future<void> deleteRecord(String key);

  static SecretVault _instance = _createDefaultVault();
  static SecretVault get instance => _instance;

  static SecretVault _createDefaultVault() {
    if (Platform.isAndroid) {
      return AndroidKeystoreSecretVault();
    }
    return SoftwareAesGcmSecretVault();
  }

  @visibleForTesting
  static void configureForTesting(SecretVault vault) {
    _instance = vault;
  }

  @visibleForTesting
  static void resetTestConfiguration() {
    _instance = _createDefaultVault();
  }
}

class AndroidKeystoreSecretVault implements SecretVault {
  static const MethodChannel _channel = MethodChannel('com.kasirtoko.app/security');
  final SecretVault _fallback = SoftwareAesGcmSecretVault();

  @override
  Future<String> wrapSecret(String plaintext) async {
    try {
      final res = await _channel.invokeMethod<String>('wrapSecret', {'plaintext': plaintext});
      if (res != null && res.isNotEmpty) return res;
    } on MissingPluginException {
      return _fallback.wrapSecret(plaintext);
    }
    throw StateError('Android Keystore gagal membungkus rahasia.');
  }

  @override
  Future<String> unwrapSecret(String envelope) async {
    if (envelope.startsWith('swv1:')) {
      return _fallback.unwrapSecret(envelope);
    }
    try {
      final res = await _channel.invokeMethod<String>('unwrapSecret', {'envelope': envelope});
      if (res != null) return res;
    } on MissingPluginException {
      return _fallback.unwrapSecret(envelope);
    }
    throw StateError('Android Keystore gagal membuka rahasia.');
  }

  @override
  Future<void> putRecord(String key, String value) async {
    try {
      await _channel.invokeMethod('putVaultRecord', {'key': key, 'value': value});
    } on MissingPluginException {
      await _fallback.putRecord(key, value);
    }
  }

  @override
  Future<String?> getRecord(String key) async {
    try {
      return await _channel.invokeMethod<String>('getVaultRecord', {'key': key});
    } on MissingPluginException {
      return _fallback.getRecord(key);
    }
  }

  @override
  Future<void> deleteRecord(String key) async {
    try {
      await _channel.invokeMethod('deleteVaultRecord', {'key': key});
    } on MissingPluginException {
      await _fallback.deleteRecord(key);
    }
  }
}

/// Pure-Dart AES-256-GCM implementation backed by process-local random KEK
/// (used in host Dart tests & non-Android environments; secrets are NEVER stored
/// in plaintext in SQLite).
class SoftwareAesGcmSecretVault implements SecretVault {
  final Uint8List _masterKey;
  final Map<String, String> _records = {};

  SoftwareAesGcmSecretVault([Uint8List? masterKey])
      : _masterKey = masterKey ?? _randomBytes(32);

  static Uint8List _randomBytes(int length) {
    final rng = Random.secure();
    return Uint8List.fromList(List<int>.generate(length, (_) => rng.nextInt(256)));
  }

  @override
  Future<String> wrapSecret(String plaintext) async {
    final iv = _randomBytes(12);
    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        true,
        AEADParameters(KeyParameter(_masterKey), 128, iv, Uint8List(0)),
      );
    final plainBytes = Uint8List.fromList(utf8.encode(plaintext));
    final encrypted = cipher.process(plainBytes);
    return 'swv1:${base64.encode(iv)}:${base64.encode(encrypted)}';
  }

  @override
  Future<String> unwrapSecret(String envelope) async {
    if (!envelope.startsWith('swv1:')) {
      throw StateError('Format amplop vault tidak dikenali.');
    }
    final parts = envelope.split(':');
    if (parts.length != 3) {
      throw StateError('Format amplop vault rusak.');
    }
    final iv = base64.decode(parts[1]);
    final ct = base64.decode(parts[2]);
    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        false,
        AEADParameters(KeyParameter(_masterKey), 128, iv, Uint8List(0)),
      );
    final plain = cipher.process(Uint8List.fromList(ct));
    return utf8.decode(plain);
  }

  @override
  Future<void> putRecord(String key, String value) async {
    _records[key] = await wrapSecret(value);
  }

  @override
  Future<String?> getRecord(String key) async {
    final wrapped = _records[key];
    if (wrapped == null || wrapped.isEmpty) return null;
    return unwrapSecret(wrapped);
  }

  @override
  Future<void> deleteRecord(String key) async {
    _records.remove(key);
  }
}
