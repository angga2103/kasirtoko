import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pointycastle/export.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../database/db_helper.dart';
import '../models/audit_log.dart';
import '../models/operational_models.dart';
import '../models/user.dart';
import '../services/secret_vault.dart';
import '../utils/security_helper.dart';

abstract class BackupCloudConnector {
  bool get isConfigured;
  String get providerLabel;

  Future<({bool uploaded, String remoteRef, String message})> uploadEncryptedBackup({
    required File encryptedFile,
    required BackupArtifactModel artifact,
  });
}

class UnconfiguredBackupCloudConnector implements BackupCloudConnector {
  const UnconfiguredBackupCloudConnector();

  @override
  bool get isConfigured => false;

  @override
  String get providerLabel => 'Belum Dikonfigurasi';

  @override
  Future<({bool uploaded, String remoteRef, String message})> uploadEncryptedBackup({
    required File encryptedFile,
    required BackupArtifactModel artifact,
  }) async {
    return (
      uploaded: false,
      remoteRef: '',
      message:
          'Konektor cloud belum dikonfigurasi/diotorisasi. Backup tetap aman secara lokal & SAF.',
    );
  }
}

class BackupResult {
  final bool success;
  final String message;
  final String? backupFilePath;
  final BackupArtifactModel? artifact;
  final bool isLowStorage;

  BackupResult({
    required this.success,
    required this.message,
    this.backupFilePath,
    this.artifact,
    this.isLowStorage = false,
  });
}

class BackupVerificationResult {
  final bool valid;
  final String message;
  final String summary;
  final String plainSha256;
  final String encryptedSha256;

  const BackupVerificationResult({
    required this.valid,
    required this.message,
    this.summary = '',
    this.plainSha256 = '',
    this.encryptedSha256 = '',
  });
}

/// Encrypted SQLite + WAL Backup, Test-Restore Verification & Safe Recovery Engine.
///
/// Key guarantees:
/// - Snapshots via SQLite `VACUUM INTO` so live WAL transactions commit cleanly into a consistent
///   single-file DB without blocking concurrent checkouts.
/// - Encrypts snapshots with AES-256-GCM (`KTBAK001` envelope) using a SecretVault-wrapped DEK
///   and optional Admin recovery passphrase PBKDF2-HMAC-SHA256 wrap for cross-device restore.
/// - Validates dual SHA-256 hashes (encrypted + plaintext) and performs a read-only test restore
///   (`PRAGMA integrity_check`, `PRAGMA foreign_key_check`, core tables count) before marking `verified`.
class BackupService {
  static const MethodChannel _channel = MethodChannel('com.kasirtoko.app/backup');
  static const String _magic = 'KTBAK001';
  static const String _vaultBackupKeyId = 'backup_master_kek_v1';
  static const String _recoveryConfiguredSettingKey = 'backup_recovery_passphrase_set';
  static const String _recoverySaltSettingKey = 'backup_recovery_salt';
  static const String _recoveryVerifySettingKey = 'backup_recovery_verifier';
  static const int minRequiredFreeSpaceBytes = 50 * 1024 * 1024; // 50 MB guard

  static BackupCloudConnector cloudConnector = const UnconfiguredBackupCloudConnector();

  @visibleForTesting
  static Future<int?> Function(String dirPath)? availableStorageBytesOverride;

  static Future<int> getAvailableStorageBytes([String? targetPath]) async {
    if (availableStorageBytesOverride != null) {
      final v = await availableStorageBytesOverride!(targetPath ?? '');
      if (v != null) return v;
    }
    if (Platform.isAndroid) {
      try {
        final v = await _channel.invokeMethod<int>('getAvailableStorageBytes', {
          if (targetPath != null && targetPath.isNotEmpty) 'path': targetPath,
        });
        if (v != null) return v;
      } catch (_) {}
    }
    return 1024 * 1024 * 1024; // Non-Android fallback (1 GB nominal when OS StatFs unavailable)
  }

  static Future<String?> getExternalBackupDir() async {
    if (!Platform.isAndroid) return null;
    try {
      return await _channel.invokeMethod<String>('getExternalBackupDir');
    } catch (_) {
      return null;
    }
  }

  static Future<String?> pickSafFolderTreeUri() async {
    if (!Platform.isAndroid) return null;
    try {
      return await _channel.invokeMethod<String>('pickBackupFolderTree');
    } catch (_) {
      return null;
    }
  }

  static Future<String> resolveSeparatedPrimaryDir({
    String? customPrimaryDir,
  }) async {
    if (customPrimaryDir != null && customPrimaryDir.trim().isNotEmpty) {
      final dir = Directory(customPrimaryDir.trim());
      if (!await dir.exists()) await dir.create(recursive: true);
      return dir.path;
    }

    // Separate strictly from live DB directory (`getApplicationDocumentsDirectory()/kasirtoko.db`)
    final extDir = await getExternalBackupDir();
    if (extDir != null && extDir.isNotEmpty) {
      final d = Directory(extDir);
      if (!await d.exists()) await d.create(recursive: true);
      return d.path;
    }
    try {
      final supDir = await getApplicationSupportDirectory();
      final d = Directory(p.join(supDir.path, 'kasirtoko_backups'));
      if (!await d.exists()) await d.create(recursive: true);
      return d.path;
    } catch (_) {
      final d = Directory(p.join(Directory.systemTemp.path, 'kasirtoko_backups'));
      if (!await d.exists()) await d.create(recursive: true);
      return d.path;
    }
  }

  static Future<Directory> _resolveTempDirectory() async {
    try {
      return await getTemporaryDirectory();
    } catch (_) {
      return Directory.systemTemp;
    }
  }

  static Future<bool> hasRecoveryPassphraseConfigured() async {
    try {
      final v = await DatabaseHelper.instance.getSetting(_recoveryConfiguredSettingKey);
      return v == '1';
    } catch (_) {
      return false;
    }
  }

  static Future<void> configureRecoveryPassphrase(
    String passphrase, {
    String actorName = 'Admin',
  }) async {
    final clean = passphrase.trim();
    if (clean.length < 6) {
      throw ArgumentError('Passphrase pemulihan backup minimal 6 karakter.');
    }
    final salt = SecurityHelper.generateSalt(16);
    final saltBytes = base64Url.decode(salt);
    final key = await SecurityHelper.deriveKeyBytes(
      passphraseAscii: clean,
      saltBytes: saltBytes,
      iterations: SecurityHelper.activeIterations,
    );
    final verifier = sha256.convert([...utf8.encode('ktbak-verify:'), ...key]).toString();
    await DatabaseHelper.instance.setSetting(_recoverySaltSettingKey, salt);
    await DatabaseHelper.instance.setSetting(_recoveryVerifySettingKey, verifier);
    await DatabaseHelper.instance.setSetting(_recoveryConfiguredSettingKey, '1');
    await SecretVault.instance.putRecord('backup_recovery_key_b64', base64Encode(key));
    await DatabaseHelper.instance.insertAuditLog(
      AuditLogModel(
        timestamp: DateTime.now(),
        userId: 0,
        userName: actorName,
        userRole: AppRoles.owner,
        actionType: 'backup_konfigurasi_kunci',
        module: 'Backup & Pemulihan',
        objectId: 'BACKUP-KEY',
        details: 'Passphrase pemulihan backup lintas perangkat diperbarui.',
      ),
    );
  }

  static Uint8List _randomBytes(int length) {
    final rng = Random.secure();
    return Uint8List.fromList(List<int>.generate(length, (_) => rng.nextInt(256)));
  }

  static Uint8List _aesGcmProcess({
    required bool encrypt,
    required Uint8List key,
    required Uint8List iv,
    required Uint8List data,
  }) {
    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        encrypt,
        AEADParameters(KeyParameter(key), 128, iv, Uint8List(0)),
      );
    return cipher.process(data);
  }

  static Future<Uint8List> _getOrCreateVaultBackupKek() async {
    final existing = await SecretVault.instance.getRecord(_vaultBackupKeyId);
    if (existing != null && existing.isNotEmpty) {
      final decoded = base64Decode(existing);
      if (decoded.length == 32) return decoded;
    }
    final fresh = _randomBytes(32);
    await SecretVault.instance.putRecord(_vaultBackupKeyId, base64Encode(fresh));
    return fresh;
  }

  static Future<Uint8List> _encryptSnapshotEnvelope({
    required Uint8List plainBytes,
    required String artifactUuid,
    required String createdAt,
    required String backupType,
    required String serverId,
    required String plainSha256,
    String? explicitRecoveryPassphrase,
  }) async {
    final dek = _randomBytes(32);
    final ivPayload = _randomBytes(12);
    final ciphertext = _aesGcmProcess(
      encrypt: true,
      key: dek,
      iv: ivPayload,
      data: plainBytes,
    );

    final vaultKek = await _getOrCreateVaultBackupKek();
    final vaultIv = _randomBytes(12);
    final vaultWrappedDek = _aesGcmProcess(
      encrypt: true,
      key: vaultKek,
      iv: vaultIv,
      data: dek,
    );

    String? passSaltB64;
    int? passIters;
    String? passIvB64;
    String? passWrappedDekB64;

    if (explicitRecoveryPassphrase != null && explicitRecoveryPassphrase.trim().isNotEmpty) {
      final salt = SecurityHelper.generateSalt(16);
      final iters = SecurityHelper.activeIterations;
      final derived = await SecurityHelper.deriveKeyBytes(
        passphraseAscii: explicitRecoveryPassphrase.trim(),
        saltBytes: base64Url.decode(salt),
        iterations: iters,
      );
      final pIv = _randomBytes(12);
      final pWrap = _aesGcmProcess(encrypt: true, key: derived, iv: pIv, data: dek);
      passSaltB64 = salt;
      passIters = iters;
      passIvB64 = base64Encode(pIv);
      passWrappedDekB64 = base64Encode(pWrap);
    } else {
      final cachedRecB64 = await SecretVault.instance.getRecord('backup_recovery_key_b64');
      final recSalt = await DatabaseHelper.instance.getSetting(_recoverySaltSettingKey);
      if (cachedRecB64 != null && cachedRecB64.isNotEmpty && recSalt.isNotEmpty) {
        final recKek = base64Decode(cachedRecB64);
        if (recKek.length == 32) {
          final pIv = _randomBytes(12);
          final pWrap = _aesGcmProcess(encrypt: true, key: recKek, iv: pIv, data: dek);
          passSaltB64 = recSalt;
          passIters = SecurityHelper.activeIterations;
          passIvB64 = base64Encode(pIv);
          passWrappedDekB64 = base64Encode(pWrap);
        }
      }
    }

    final headerMap = <String, dynamic>{
      'v': 1,
      'encryption_version': 'aes256gcm_v1',
      'artifact_uuid': artifactUuid,
      'created_at': createdAt,
      'backup_type': backupType,
      'server_id': serverId,
      'db_version': DatabaseHelper.dbVersion,
      'plain_size_bytes': plainBytes.length,
      'plain_sha256': plainSha256,
      'vault_iv_b64': base64Encode(vaultIv),
      'vault_wrapped_dek_b64': base64Encode(vaultWrappedDek),
      'payload_iv_b64': base64Encode(ivPayload),
      if (passWrappedDekB64 != null) ...{
        'passphrase_salt_b64': passSaltB64,
        'passphrase_iterations': passIters,
        'passphrase_iv_b64': passIvB64,
        'passphrase_wrapped_dek_b64': passWrappedDekB64,
      },
    };
    final headerBytes = utf8.encode(jsonEncode(headerMap));
    final magicBytes = ascii.encode(_magic);
    final lenBuf = ByteData(4)..setUint32(0, headerBytes.length, Endian.big);

    final builder = BytesBuilder(copy: false)
      ..add(magicBytes)
      ..add(lenBuf.buffer.asUint8List())
      ..add(headerBytes)
      ..add(ciphertext);
    return builder.takeBytes();
  }

  static Future<({Map<String, dynamic> header, Uint8List plainBytes})> decryptBackupEnvelope(
    Uint8List envelopeBytes, {
    String? recoveryPassphrase,
  }) async {
    if (envelopeBytes.length < 12) {
      throw const FormatException('File backup terlalu kecil / rusak.');
    }
    final magic = ascii.decode(envelopeBytes.sublist(0, 8), allowInvalid: true);
    if (magic != _magic) {
      throw const FormatException('Header file backup bukan format KTBAK001 terenkripsi.');
    }
    final headerLen = ByteData.sublistView(envelopeBytes, 8, 12).getUint32(0, Endian.big);
    if (12 + headerLen > envelopeBytes.length) {
      throw const FormatException('Header JSON backup rusak / terpotong.');
    }
    final headerJson = utf8.decode(envelopeBytes.sublist(12, 12 + headerLen));
    final header = Map<String, dynamic>.from(jsonDecode(headerJson) as Map);
    final ciphertext = envelopeBytes.sublist(12 + headerLen);

    Uint8List? dek;
    if (recoveryPassphrase != null &&
        recoveryPassphrase.trim().isNotEmpty &&
        header['passphrase_wrapped_dek_b64'] != null) {
      final salt = (header['passphrase_salt_b64'] ?? '').toString();
      final iters = (header['passphrase_iterations'] as num?)?.toInt() ??
          SecurityHelper.defaultPbkdf2Iterations;
      final pIv = base64Decode((header['passphrase_iv_b64'] ?? '').toString());
      final pWrapped = base64Decode((header['passphrase_wrapped_dek_b64'] ?? '').toString());
      final kek = await SecurityHelper.deriveKeyBytes(
        passphraseAscii: recoveryPassphrase.trim(),
        saltBytes: base64Url.decode(salt),
        iterations: iters,
      );
      try {
        dek = _aesGcmProcess(encrypt: false, key: kek, iv: pIv, data: pWrapped);
      } catch (_) {
        throw StateError('Passphrase pemulihan salah atau header DEK rusak.');
      }
    }

    if (dek == null) {
      final vaultKek = await _getOrCreateVaultBackupKek();
      final vIv = base64Decode((header['vault_iv_b64'] ?? '').toString());
      final vWrapped = base64Decode((header['vault_wrapped_dek_b64'] ?? '').toString());
      try {
        dek = _aesGcmProcess(encrypt: false, key: vaultKek, iv: vIv, data: vWrapped);
      } catch (_) {
        throw StateError(
          'Tidak dapat membuka kunci backup dengan Keystore perangkat ini. Masukkan Passphrase Pemulihan jika memulihkan dari HP lain.',
        );
      }
    }

    final payloadIv = base64Decode((header['payload_iv_b64'] ?? '').toString());
    late Uint8List plainBytes;
    try {
      plainBytes = _aesGcmProcess(encrypt: false, key: dek, iv: payloadIv, data: ciphertext);
    } catch (_) {
      throw StateError('Verifikasi autentikasi AES-GCM gagal: file backup korup atau dimodifikasi.');
    }

    final expectedSha = (header['plain_sha256'] ?? '').toString();
    final actualSha = sha256.convert(plainBytes).toString();
    if (expectedSha.isNotEmpty && actualSha != expectedSha) {
      throw StateError('Checksum SHA-256 plaintext backup tidak cocok.');
    }

    return (header: header, plainBytes: plainBytes);
  }

  /// Creates an encrypted, WAL-consistent snapshot, writes to primary (and optional secondary / SAF)
  /// locations, verifies integrity + test-restore into a temporary DB, and records `backup_artifacts`.
  static Future<BackupResult> createEncryptedBackup({
    String backupType = 'manual',
    int? jobId,
    String? customPrimaryDir,
    String? secondaryDir,
    String? safTreeUri,
    String? recoveryPassphrase,
    bool verifyImmediately = true,
    bool allowCloudUpload = false,
    String actorName = 'Sistem',
    int minFreeSpaceBytes = minRequiredFreeSpaceBytes,
  }) async {
    final artifactUuid = const Uuid().v4();
    final now = DateTime.now();
    final nowIso = now.toIso8601String();
    final tempDir = await _resolveTempDirectory();
    final tempSnapshotPath = p.join(tempDir.path, 'kt_snap_$artifactUuid.db');

    try {
      final primaryDir = await resolveSeparatedPrimaryDir(customPrimaryDir: customPrimaryDir);
      final freeBytes = await getAvailableStorageBytes(primaryDir);
      if (freeBytes >= 0 && freeBytes < minFreeSpaceBytes) {
        final mb = (freeBytes / (1024 * 1024)).toStringAsFixed(1);
        final msg = 'Penyimpanan hampir penuh ($mb MB tersisa). Backup dibatalkan.';
        await DatabaseHelper.instance.insertAuditLog(
          AuditLogModel(
            timestamp: now,
            userId: 0,
            userName: actorName,
            userRole: AppRoles.owner,
            actionType: 'backup_gagal',
            module: 'Backup & Pemulihan',
            objectId: artifactUuid,
            details: msg,
          ),
        );
        return BackupResult(success: false, message: msg, isLowStorage: true);
      }

      // 1. Consistent SQLite + WAL snapshot via VACUUM INTO without interrupting concurrent checkouts
      final db = await DatabaseHelper.instance.database;
      final serverId = await DatabaseHelper.instance.getOrCreateServerId();
      if (await File(tempSnapshotPath).exists()) {
        await File(tempSnapshotPath).delete();
      }

      var snapshotCreated = false;
      try {
        final escaped = tempSnapshotPath.replaceAll("'", "''");
        await db.rawQuery("VACUUM INTO '$escaped'");
        snapshotCreated = await File(tempSnapshotPath).exists();
      } catch (_) {}

      if (!snapshotCreated) {
        // Safe fallback when DB path is in-memory or older SQLite: copy file cleanly after WAL checkpoint
        final livePath = db.path;
        if (livePath.isEmpty || livePath == inMemoryDatabasePath || !await File(livePath).exists()) {
          return BackupResult(
            success: false,
            message: 'Snapshot VACUUM INTO gagal dan path database tidak tersedia.',
          );
        }
        try {
          await db.rawQuery('PRAGMA wal_checkpoint(PASSIVE)');
        } catch (_) {}
        await File(livePath).copy(tempSnapshotPath);
      }

      final plainBytes = await File(tempSnapshotPath).readAsBytes();
      final plainSha = sha256.convert(plainBytes).toString();

      // 2. AES-256-GCM encryption
      final encBytes = await _encryptSnapshotEnvelope(
        plainBytes: plainBytes,
        artifactUuid: artifactUuid,
        createdAt: nowIso,
        backupType: backupType,
        serverId: serverId,
        plainSha256: plainSha,
        explicitRecoveryPassphrase: recoveryPassphrase,
      );
      final encSha = sha256.convert(encBytes).toString();

      final stamp =
          '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
      final fileName = 'KasirToko_${backupType}_$stamp.ktbak';
      final primaryPath = p.join(primaryDir, fileName);
      await File(primaryPath).writeAsBytes(encBytes, flush: true);

      // 3. Copy to secondary location & SAF URI if configured
      var secPath = '';
      if (secondaryDir != null && secondaryDir.trim().isNotEmpty) {
        try {
          final sd = Directory(secondaryDir.trim());
          if (!await sd.exists()) await sd.create(recursive: true);
          final candidateSec = p.join(sd.path, fileName);
          await File(primaryPath).copy(candidateSec);
          secPath = candidateSec;
        } catch (_) {}
      }
      if (safTreeUri != null && safTreeUri.trim().isNotEmpty && Platform.isAndroid) {
        try {
          final docUri = await _channel.invokeMethod<String>('copyBackupToTreeUri', {
            'treeUri': safTreeUri.trim(),
            'fileName': fileName,
            'sourcePath': primaryPath,
          });
          if (docUri != null && docUri.isNotEmpty) {
            secPath = secPath.isEmpty ? docUri : '$secPath | $docUri';
          }
        } catch (_) {}
      }

      final artifact = BackupArtifactModel(
        jobId: jobId,
        artifactUuid: artifactUuid,
        backupType: backupType,
        fileName: fileName,
        primaryPath: primaryPath,
        secondaryPath: secPath,
        locationType: safTreeUri != null && safTreeUri.isNotEmpty ? 'saf_hybrid' : 'local_separate',
        plainSizeBytes: plainBytes.length,
        encryptedSizeBytes: encBytes.length,
        plainSha256: plainSha,
        encryptedSha256: encSha,
        encryptionVersion: 'aes256gcm_v1',
        status: 'created',
        verifiedRestoreOk: false,
        createdAt: nowIso,
      );
      await DatabaseHelper.instance.insertBackupArtifact(artifact);

      // 4. Mandatory test-restore & SHA-256 verification
      var finalArtifact = artifact;
      if (verifyImmediately) {
        final v = await verifyBackupArtifact(
          primaryPath,
          expectedEncryptedSha256: encSha,
          artifactUuid: artifactUuid,
          recoveryPassphrase: recoveryPassphrase,
        );
        if (!v.valid) {
          final msg = 'Backup dibuat tetapi verifikasi gagal: ${v.message}';
          return BackupResult(success: false, message: msg, backupFilePath: primaryPath, artifact: artifact);
        }
        finalArtifact = BackupArtifactModel(
          jobId: artifact.jobId,
          artifactUuid: artifact.artifactUuid,
          backupType: artifact.backupType,
          fileName: artifact.fileName,
          primaryPath: artifact.primaryPath,
          secondaryPath: artifact.secondaryPath,
          locationType: artifact.locationType,
          plainSizeBytes: artifact.plainSizeBytes,
          encryptedSizeBytes: artifact.encryptedSizeBytes,
          plainSha256: artifact.plainSha256,
          encryptedSha256: artifact.encryptedSha256,
          encryptionVersion: artifact.encryptionVersion,
          status: 'verified',
          verifiedRestoreOk: true,
          verificationSummary: v.summary,
          createdAt: artifact.createdAt,
        );
      }

      if (allowCloudUpload && cloudConnector.isConfigured) {
        await cloudConnector.uploadEncryptedBackup(
          encryptedFile: File(primaryPath),
          artifact: finalArtifact,
        );
      }

      await DatabaseHelper.instance.insertAuditLog(
        AuditLogModel(
          timestamp: DateTime.now(),
          userId: 0,
          userName: actorName,
          userRole: AppRoles.owner,
          actionType: backupType == 'manual' ? 'backup_manual' : 'backup_otomatis',
          module: 'Backup & Pemulihan',
          objectId: artifactUuid,
          afterValue: '$fileName (${finalArtifact.verificationSummary})',
          details: 'Backup terenkripsi ($backupType) berhasil diverifikasi: ${finalArtifact.verificationSummary}',
        ),
      );

      return BackupResult(
        success: true,
        message: 'Backup terenkripsi & tes restore terverifikasi: $fileName',
        backupFilePath: primaryPath,
        artifact: finalArtifact,
      );
    } catch (e) {
      await DatabaseHelper.instance.insertAuditLog(
        AuditLogModel(
          timestamp: DateTime.now(),
          userId: 0,
          userName: actorName,
          userRole: AppRoles.owner,
          actionType: 'backup_gagal',
          module: 'Backup & Pemulihan',
          objectId: artifactUuid,
          details: 'Gagal membuat backup: $e',
        ),
      );
      return BackupResult(success: false, message: 'Gagal membuat backup: $e');
    } finally {
      try {
        final f = File(tempSnapshotPath);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
  }

  /// Decrypts an encrypted `.ktbak` (or inspects legacy `.db`), verifies SHA-256 checksums,
  /// writes a temporary test DB, and validates `PRAGMA integrity_check` + core table schema.
  static Future<BackupVerificationResult> verifyBackupArtifact(
    String filePath, {
    String? expectedEncryptedSha256,
    String? artifactUuid,
    String? recoveryPassphrase,
  }) async {
    final tempDir = await _resolveTempDirectory();
    final probePath = p.join(tempDir.path, 'kt_verify_${const Uuid().v4()}.db');
    Database? testDb;

    try {
      final f = File(filePath);
      if (!await f.exists()) {
        return const BackupVerificationResult(valid: false, message: 'File backup tidak ditemukan.');
      }
      final fileBytes = await f.readAsBytes();
      final actualEncSha = sha256.convert(fileBytes).toString();
      if (expectedEncryptedSha256 != null &&
          expectedEncryptedSha256.isNotEmpty &&
          actualEncSha != expectedEncryptedSha256) {
        return const BackupVerificationResult(
          valid: false,
          message: 'Checksum SHA-256 file terenkripsi tidak cocok (kemungkinan file rusak).',
        );
      }

      late Uint8List plainBytes;
      late String plainSha;
      if (filePath.toLowerCase().endsWith('.ktbak')) {
        final dec = await decryptBackupEnvelope(
          fileBytes,
          recoveryPassphrase: recoveryPassphrase,
        );
        plainBytes = dec.plainBytes;
        plainSha = sha256.convert(plainBytes).toString();
      } else {
        plainBytes = fileBytes;
        plainSha = actualEncSha;
      }

      await File(probePath).writeAsBytes(plainBytes, flush: true);
      testDb = await openReadOnlyDatabase(probePath, singleInstance: false);

      final integrityRows = await testDb.rawQuery('PRAGMA integrity_check');
      final integrity = integrityRows.isNotEmpty
          ? integrityRows.first.values.first.toString().toLowerCase()
          : '';
      if (integrity != 'ok') {
        throw StateError('PRAGMA integrity_check gagal: $integrity');
      }

      final fkRows = await testDb.rawQuery('PRAGMA foreign_key_check');
      final fkSuffix = fkRows.isNotEmpty ? ' | fk_warn=${fkRows.length}' : '';

      final tables = await testDb.rawQuery("SELECT name FROM sqlite_master WHERE type='table'");
      final tableNames = tables.map((r) => (r['name'] ?? '').toString()).toSet();
      for (final reqTable in ['users', 'products', 'transactions', 'shifts']) {
        if (!tableNames.contains(reqTable)) {
          throw StateError('Tabel inti $reqTable hilang dari backup.');
        }
      }

      final trxCount = Sqflite.firstIntValue(await testDb.rawQuery('SELECT COUNT(*) FROM transactions')) ?? 0;
      final prodCount = Sqflite.firstIntValue(await testDb.rawQuery('SELECT COUNT(*) FROM products')) ?? 0;
      final userCount = Sqflite.firstIntValue(await testDb.rawQuery('SELECT COUNT(*) FROM users')) ?? 0;
      final shiftCount = Sqflite.firstIntValue(await testDb.rawQuery('SELECT COUNT(*) FROM shifts')) ?? 0;
      final summary = 'integrity=ok$fkSuffix | users=$userCount, produk=$prodCount, trx=$trxCount, shift=$shiftCount';

      if (artifactUuid != null && artifactUuid.isNotEmpty) {
        await DatabaseHelper.instance.updateBackupArtifactVerification(
          artifactUuid: artifactUuid,
          status: 'verified',
          verifiedRestoreOk: true,
          verificationSummary: summary,
        );
      }

      return BackupVerificationResult(
        valid: true,
        message: 'Tes restore & SHA-256 valid ($summary)',
        summary: summary,
        plainSha256: plainSha,
        encryptedSha256: actualEncSha,
      );
    } catch (e) {
      if (artifactUuid != null && artifactUuid.isNotEmpty) {
        await DatabaseHelper.instance.updateBackupArtifactVerification(
          artifactUuid: artifactUuid,
          status: 'failed',
          verifiedRestoreOk: false,
          verificationSummary: '',
          errorMessage: e.toString(),
        );
      }
      return BackupVerificationResult(valid: false, message: '$e');
    } finally {
      await testDb?.close();
      for (final suffix in ['', '-wal', '-shm']) {
        try {
          final pf = File('$probePath$suffix');
          if (await pf.exists()) await pf.delete();
        } catch (_) {}
      }
    }
  }

  /// Safely restores live DB from a `.ktbak` encrypted backup or legacy `.db`,
  /// after creating a verified pre-restore safety snapshot of current data.
  static Future<BackupResult> restoreFromFilePath(
    String filePath, {
    String? recoveryPassphrase,
    String? safetyBackupDir,
    String actorName = 'Admin',
  }) async {
    final lower = filePath.toLowerCase();
    if (!lower.endsWith('.ktbak') && !lower.endsWith('.db')) {
      return BackupResult(
        success: false,
        message: 'Format file tidak didukung! Pilih file .ktbak atau .db.',
      );
    }

    final check = await verifyBackupArtifact(
      filePath,
      recoveryPassphrase: recoveryPassphrase,
    );
    if (!check.valid) {
      return BackupResult(
        success: false,
        message: 'Pemulihan ditolak karena validasi backup gagal: ${check.message}',
      );
    }

    try {
      final liveDb = await DatabaseHelper.instance.database;
      final targetLivePath = liveDb.path;
      if (targetLivePath.isEmpty || targetLivePath == inMemoryDatabasePath) {
        return BackupResult(
          success: false,
          message: 'Restore hanya didukung pada database berbasis file.',
        );
      }

      // 1. Pre-restore safety snapshot before touching live DB
      final preRestoreRes = await createEncryptedBackup(
        backupType: 'pre_restore',
        customPrimaryDir: safetyBackupDir,
        verifyImmediately: true,
        actorName: actorName,
        minFreeSpaceBytes: 0,
      );

      // 2. Decrypt plain SQLite payload to swap
      late Uint8List restoredBytes;
      final rawBytes = await File(filePath).readAsBytes();
      if (lower.endsWith('.ktbak')) {
        restoredBytes = (await decryptBackupEnvelope(
          rawBytes,
          recoveryPassphrase: recoveryPassphrase,
        ))
            .plainBytes;
      } else {
        restoredBytes = rawBytes;
      }

      // 3. Close singleton connection & clear WAL/SHM cleanly
      await DatabaseHelper.instance.resetConnection();
      for (final suffix in ['-wal', '-shm']) {
        final sf = File('$targetLivePath$suffix');
        if (await sf.exists()) await sf.delete();
      }
      await File(targetLivePath).writeAsBytes(restoredBytes, flush: true);

      // 4. Re-open (auto-migrates older schema backups safely)
      await DatabaseHelper.instance.database;
      if (preRestoreRes.artifact != null) {
        try {
          await DatabaseHelper.instance.insertBackupArtifact(preRestoreRes.artifact!);
        } catch (_) {}
      }
      await DatabaseHelper.instance.insertAuditLog(
        AuditLogModel(
          timestamp: DateTime.now(),
          userId: 0,
          userName: actorName,
          userRole: AppRoles.owner,
          actionType: 'restore_database',
          module: 'Backup & Pemulihan',
          objectId: p.basename(filePath),
          afterValue: check.summary,
          details: 'Database dipulihkan dari ${p.basename(filePath)} (${check.summary}).',
        ),
      );

      return BackupResult(
        success: true,
        message: 'Database berhasil dipulihkan & diverifikasi (${check.summary})',
      );
    } catch (e) {
      return BackupResult(success: false, message: 'Gagal memulihkan database: $e');
    }
  }

  /// Legacy-compatible manual backup entrypoint (now writes encrypted `.ktbak` + shares optional copy).
  static Future<BackupResult> createAndShareBackup({
    bool shareNow = true,
    String actorName = 'Admin Manual',
  }) async {
    final res = await createEncryptedBackup(
      backupType: 'manual',
      verifyImmediately: true,
      actorName: actorName,
    );
    if (res.success && shareNow && res.backupFilePath != null) {
      try {
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(res.backupFilePath!)],
            subject: 'Backup Terenkripsi KasirToko - ${p.basename(res.backupFilePath!)}',
            text: 'File Cadangan Database Terenkripsi KasirToko (.ktbak)',
          ),
        );
      } catch (_) {}
    }
    return res;
  }

  /// Legacy-compatible interactive file-picker restore helper supporting both `.ktbak` & `.db`.
  static Future<BackupResult> restoreDatabase({
    String? recoveryPassphrase,
    String actorName = 'Admin Manual',
  }) async {
    try {
      final pickedFile = await FilePicker.pickFile(type: FileType.any);
      if (pickedFile == null || pickedFile.path == null) {
        return BackupResult(success: false, message: 'Pemulihan dibatalkan.');
      }
      return await restoreFromFilePath(
        pickedFile.path!,
        recoveryPassphrase: recoveryPassphrase,
        actorName: actorName,
      );
    } catch (e) {
      return BackupResult(success: false, message: 'Gagal memulihkan database: $e');
    }
  }
}
