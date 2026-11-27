import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

import '../models/cash_register.dart';
import '../models/paired_terminal.dart';
import '../models/print_job.dart';
import '../models/product.dart';
import '../models/terminal_session.dart';
import '../models/transaction.dart';
import '../models/transaction_item.dart';
import '../models/user.dart';
import '../services/secret_vault.dart';
import 'db_helper.dart';

class PairingTicket {
  final String pairingCode;
  final String expiresAt;
  final int? assignedRegisterId;
  final bool allowAutoOpenDrawer;
  final bool allowManualOpenDrawer;

  const PairingTicket({
    required this.pairingCode,
    required this.expiresAt,
    this.assignedRegisterId,
    required this.allowAutoOpenDrawer,
    required this.allowManualOpenDrawer,
  });
}

class CompletedPairingResult {
  final PairedTerminalModel terminal;
  final String deviceToken;
  final String deviceSecret;
  final CashRegisterModel? assignedRegister;

  const CompletedPairingResult({
    required this.terminal,
    required this.deviceToken,
    required this.deviceSecret,
    this.assignedRegister,
  });
}

class ValidatedSession {
  final TerminalSessionModel session;
  final UserModel cashier;

  const ValidatedSession({
    required this.session,
    required this.cashier,
  });
}

class SessionValidationFailure {
  final String errorCode;
  final String message;

  const SessionValidationFailure(this.errorCode, this.message);
}

class SessionLimitExceededException implements Exception {
  final int activeCount;
  final int maxAllowed;
  final List<Map<String, dynamic>> activeDevices;
  final String message;

  const SessionLimitExceededException({
    required this.activeCount,
    required this.maxAllowed,
    required this.activeDevices,
    required this.message,
  });

  @override
  String toString() => message;
}

class MultiDeviceDao {
  final DatabaseHelper _dbHelper;
  final SecretVault Function() _vaultProvider;
  final Uuid _uuid = const Uuid();
  final Map<int, Future<void>> _cashierSessionLocks = {};

  MultiDeviceDao({
    DatabaseHelper? dbHelper,
    SecretVault Function()? vaultProvider,
  })  : _dbHelper = dbHelper ?? DatabaseHelper.instance,
        _vaultProvider = vaultProvider ?? (() => SecretVault.instance);

  static String sha256Hex(String input) =>
      sha256.convert(utf8.encode(input)).toString();

  static String generateOpaqueSecret({int byteLength = 32}) {
    final rng = Random.secure();
    final bytes = List<int>.generate(byteLength, (_) => rng.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  static String normalizePairingCode(String raw) =>
      raw.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  // ==================== PAIRING TOKENS & TERMINALS ====================

  Future<PairingTicket> createPairingToken({
    String suggestedName = '',
    int? assignedRegisterId,
    bool allowAutoOpenDrawer = false,
    bool allowManualOpenDrawer = false,
    Duration ttl = const Duration(minutes: 5),
    String actorName = 'Admin',
  }) async {
    final db = await _dbHelper.database;
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rng = Random.secure();
    final codeRaw = List<String>.generate(8, (_) => alphabet[rng.nextInt(alphabet.length)]).join();
    final formatted = '${codeRaw.substring(0, 4)}-${codeRaw.substring(4)}';
    final now = DateTime.now();
    final expiresAt = now.add(ttl).toIso8601String();

    await db.insert('pairing_tokens', {
      'token_hash': sha256Hex(codeRaw),
      'suggested_terminal_name': suggestedName.trim(),
      'assigned_register_id': assignedRegisterId,
      'allow_auto_open_drawer': allowAutoOpenDrawer ? 1 : 0,
      'allow_manual_open_drawer': allowManualOpenDrawer ? 1 : 0,
      'created_at': now.toIso8601String(),
      'expires_at': expiresAt,
    });

    await db.insert('audit_logs', {
      'timestamp': now.toIso8601String(),
      'user_id': 0,
      'user_name': actorName,
      'user_role': 'admin',
      'action_type': 'pairing_token_dibuat',
      'module': 'Multi-Perangkat',
      'object_id': 'PAIRING-$formatted',
      'before_value': '',
      'after_value': 'expires_at=$expiresAt, reg=$assignedRegisterId',
      'details': 'Kode pairing terminal sementara dibuat ($formatted).',
    });

    return PairingTicket(
      pairingCode: formatted,
      expiresAt: expiresAt,
      assignedRegisterId: assignedRegisterId,
      allowAutoOpenDrawer: allowAutoOpenDrawer,
      allowManualOpenDrawer: allowManualOpenDrawer,
    );
  }

  Future<CompletedPairingResult> completePairing({
    required String pairingCode,
    required String terminalName,
    required String deviceModel,
    required String deviceUuid,
  }) async {
    final cleanCode = normalizePairingCode(pairingCode);
    if (cleanCode.isEmpty) {
      throw StateError('PAIRING_CODE_INVALID: Kode pairing kosong atau tidak valid.');
    }
    final cleanName = terminalName.trim().isEmpty ? 'Terminal Kasir' : terminalName.trim();
    final cleanUuid = deviceUuid.trim().isEmpty ? _uuid.v4() : deviceUuid.trim();
    final tokenHash = sha256Hex(cleanCode);
    final rawDeviceToken = generateOpaqueSecret(byteLength: 32);
    final rawDeviceSecret = generateOpaqueSecret(byteLength: 32);
    final wrappedSecret = await _vaultProvider().wrapSecret(rawDeviceSecret);
    final tokenDigest = sha256Hex(rawDeviceToken);
    final secretDigest = sha256Hex(rawDeviceSecret);

    final db = await _dbHelper.database;
    late PairedTerminalModel savedTerminal;
    CashRegisterModel? assignedReg;

    await db.transaction((txn) async {
      final tokenRows = await txn.query(
        'pairing_tokens',
        where: 'token_hash = ?',
        whereArgs: [tokenHash],
        limit: 1,
      );
      if (tokenRows.isEmpty) {
        throw StateError('PAIRING_CODE_INVALID: Kode pairing tidak dikenali.');
      }
      final tRow = tokenRows.first;
      if ((tRow['consumed_at'] ?? '').toString().isNotEmpty) {
        throw StateError('PAIRING_CODE_USED: Kode pairing ini sudah digunakan.');
      }
      final exp = DateTime.tryParse((tRow['expires_at'] ?? '').toString());
      if (exp == null || DateTime.now().isAfter(exp)) {
        throw StateError('PAIRING_CODE_EXPIRED: Kode pairing sudah kedaluwarsa.');
      }

      final suggestedName = (tRow['suggested_terminal_name'] ?? '').toString().trim();
      final effectiveName = cleanName == 'Terminal Kasir' && suggestedName.isNotEmpty
          ? suggestedName
          : cleanName;
      int? regId = (tRow['assigned_register_id'] as num?)?.toInt();
      if (regId == null) {
        final drawerModeRow = await txn.query(
          'store_settings',
          where: 'key = ?',
          whereArgs: ['drawer_mode'],
          limit: 1,
        );
        final mode = drawerModeRow.isNotEmpty
            ? (drawerModeRow.first['value'] ?? '').toString()
            : DrawerMode.sharedDrawer;
        if (mode == DrawerMode.sharedDrawer) {
          regId = 1;
        }
      }

      if (regId != null) {
        final regRows = await txn.query(
          'cash_registers',
          where: 'id = ? AND is_active = 1',
          whereArgs: [regId],
          limit: 1,
        );
        if (regRows.isNotEmpty) {
          assignedReg = CashRegisterModel.fromMap(regRows.first);
        } else {
          regId = null;
        }
      }

      final allowAuto = (tRow['allow_auto_open_drawer'] ?? 0) == 1 ? 1 : 0;
      final allowManual = (tRow['allow_manual_open_drawer'] ?? 0) == 1 ? 1 : 0;
      final nowIso = DateTime.now().toIso8601String();

      // Re-use existing terminal ID if same physical device_uuid re-pairs cleanly
      final existingByUuid = await txn.query(
        'paired_terminals',
        where: 'device_uuid = ?',
        whereArgs: [cleanUuid],
        limit: 1,
      );

      late final String terminalId;
      if (existingByUuid.isNotEmpty) {
        terminalId = (existingByUuid.first['terminal_id'] ?? '').toString();
        await txn.update(
          'paired_terminals',
          {
            'terminal_name': effectiveName,
            'device_model': deviceModel.trim(),
            'device_secret_hash': secretDigest,
            'device_secret_enc': wrappedSecret,
            'device_token_hash': tokenDigest,
            'assigned_register_id': regId,
            'allow_open_cash_drawer': (allowAuto == 1 || allowManual == 1) ? 1 : 0,
            'allow_auto_open_drawer': allowAuto,
            'allow_manual_open_drawer': allowManual,
            'is_revoked': 0,
            'paired_at': nowIso,
            'last_seen_at': nowIso,
          },
          where: 'terminal_id = ?',
          whereArgs: [terminalId],
        );
        await txn.update(
          'terminal_sessions',
          {'revoked_at': nowIso},
          where: "terminal_id = ? AND (revoked_at IS NULL OR revoked_at = '')",
          whereArgs: [terminalId],
        );
      } else {
        final allRows = await txn.query('paired_terminals', columns: ['id', 'terminal_id']);
        var seq = allRows.length + 1;
        while (true) {
          final candidate = 'TERM-${seq.toString().padLeft(3, '0')}';
          final collision = allRows.any((r) => r['terminal_id'] == candidate);
          if (!collision) {
            terminalId = candidate;
            break;
          }
          seq++;
        }
        await txn.insert('paired_terminals', {
          'terminal_id': terminalId,
          'terminal_code': terminalId,
          'terminal_name': effectiveName,
          'device_model': deviceModel.trim(),
          'device_uuid': cleanUuid,
          'device_secret_hash': secretDigest,
          'device_secret_enc': wrappedSecret,
          'device_token_hash': tokenDigest,
          'assigned_register_id': regId,
          'allow_open_cash_drawer': (allowAuto == 1 || allowManual == 1) ? 1 : 0,
          'allow_auto_open_drawer': allowAuto,
          'allow_manual_open_drawer': allowManual,
          'is_revoked': 0,
          'paired_at': nowIso,
          'last_seen_at': nowIso,
        });
      }

      if (regId != null) {
        // Ensure deterministic terminal-level assignment exists for this terminal if non-conflicting
        await txn.delete(
          'cash_register_assignments',
          where: 'terminal_id = ? AND cashier_id IS NULL',
          whereArgs: [terminalId],
        );
        await txn.insert('cash_register_assignments', {
          'cash_register_id': regId,
          'terminal_id': terminalId,
          'cashier_id': null,
          'priority': 10,
          'is_active': 1,
          'assigned_by': 'Pairing Admin',
          'created_at': nowIso,
        });
      }

      await txn.update(
        'pairing_tokens',
        {
          'consumed_at': nowIso,
          'consumed_by_terminal_id': terminalId,
        },
        where: 'id = ?',
        whereArgs: [tRow['id']],
      );

      final loaded = await txn.query(
        'paired_terminals',
        where: 'terminal_id = ?',
        whereArgs: [terminalId],
        limit: 1,
      );
      savedTerminal = PairedTerminalModel.fromMap(loaded.first);

      await txn.insert('audit_logs', {
        'timestamp': nowIso,
        'user_id': 0,
        'user_name': 'Sistem Server',
        'user_role': 'admin',
        'action_type': 'pairing_terminal_berhasil',
        'module': 'Multi-Perangkat',
        'object_id': terminalId,
        'before_value': '',
        'after_value': 'name=$effectiveName, reg=$regId, model=$deviceModel',
        'details': 'Perangkat Staff "$effectiveName" berhasil dipasangkan sebagai $terminalId.',
      });
    });

    return CompletedPairingResult(
      terminal: savedTerminal,
      deviceToken: rawDeviceToken,
      deviceSecret: rawDeviceSecret,
      assignedRegister: assignedReg,
    );
  }

  Future<List<PairedTerminalModel>> listTerminals({bool includeRevoked = true}) async {
    final db = await _dbHelper.database;
    final rows = includeRevoked
        ? await db.query('paired_terminals', orderBy: 'is_revoked ASC, id ASC')
        : await db.query(
            'paired_terminals',
            where: 'is_revoked = 0',
            orderBy: 'id ASC',
          );
    return rows.map((r) => PairedTerminalModel.fromMap(r)).toList();
  }

  Future<PairedTerminalModel?> getTerminalById(String terminalId) async {
    final clean = terminalId.trim();
    if (clean.isEmpty) return null;
    final db = await _dbHelper.database;
    final rows = await db.query(
      'paired_terminals',
      where: 'terminal_id = ?',
      whereArgs: [clean],
      limit: 1,
    );
    return rows.isNotEmpty ? PairedTerminalModel.fromMap(rows.first) : null;
  }

  Future<String?> unwrapTerminalSecret(PairedTerminalModel terminal) async {
    if (terminal.deviceSecretEnc.isEmpty) return null;
    return _vaultProvider().unwrapSecret(terminal.deviceSecretEnc);
  }

  Future<void> touchTerminalLastSeen(String terminalId) async {
    try {
      final db = await _dbHelper.database;
      await db.update(
        'paired_terminals',
        {'last_seen_at': DateTime.now().toIso8601String()},
        where: 'terminal_id = ?',
        whereArgs: [terminalId],
      );
    } catch (_) {
      // Best-effort telemetry; never fail active requests if DB is closing/stopping.
    }
  }

  Future<void> updateTerminalPolicy({
    required String terminalId,
    String? terminalName,
    int? assignedRegisterId,
    bool clearAssignedRegister = false,
    int? defaultPrinterId,
    bool clearDefaultPrinter = false,
    bool? allowAutoOpenDrawer,
    bool? allowManualOpenDrawer,
    String actorName = 'Admin',
  }) async {
    final db = await _dbHelper.database;
    final updates = <String, dynamic>{};
    if (terminalName != null && terminalName.trim().isNotEmpty) {
      updates['terminal_name'] = terminalName.trim();
    }
    if (clearAssignedRegister) {
      updates['assigned_register_id'] = null;
    } else if (assignedRegisterId != null) {
      updates['assigned_register_id'] = assignedRegisterId;
    }
    if (clearDefaultPrinter) {
      updates['default_printer_id'] = null;
    } else if (defaultPrinterId != null) {
      updates['default_printer_id'] = defaultPrinterId;
    }
    if (allowAutoOpenDrawer != null) {
      updates['allow_auto_open_drawer'] = allowAutoOpenDrawer ? 1 : 0;
    }
    if (allowManualOpenDrawer != null) {
      updates['allow_manual_open_drawer'] = allowManualOpenDrawer ? 1 : 0;
    }

    await db.transaction((txn) async {
      final rows = await txn.query(
        'paired_terminals',
        where: 'terminal_id = ?',
        whereArgs: [terminalId],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw StateError('Terminal "$terminalId" tidak ditemukan.');
      }
      final existing = PairedTerminalModel.fromMap(rows.first);
      final nextAuto = allowAutoOpenDrawer ?? existing.allowAutoOpenDrawer;
      final nextManual = allowManualOpenDrawer ?? existing.allowManualOpenDrawer;
      updates['allow_open_cash_drawer'] = (nextAuto || nextManual) ? 1 : 0;

      if (updates.isNotEmpty) {
        await txn.update(
          'paired_terminals',
          updates,
          where: 'terminal_id = ?',
          whereArgs: [terminalId],
        );
      }

      if (clearAssignedRegister || assignedRegisterId != null) {
        await txn.delete(
          'cash_register_assignments',
          where: 'terminal_id = ? AND cashier_id IS NULL',
          whereArgs: [terminalId],
        );
        if (!clearAssignedRegister && assignedRegisterId != null) {
          await txn.insert('cash_register_assignments', {
            'cash_register_id': assignedRegisterId,
            'terminal_id': terminalId,
            'cashier_id': null,
            'priority': 10,
            'is_active': 1,
            'assigned_by': actorName,
            'created_at': DateTime.now().toIso8601String(),
          });
        }
      }

      await txn.insert('audit_logs', {
        'timestamp': DateTime.now().toIso8601String(),
        'user_id': 0,
        'user_name': actorName,
        'user_role': 'admin',
        'action_type': 'ubah_kebijakan_terminal',
        'module': 'Multi-Perangkat',
        'object_id': terminalId,
        'before_value': 'auto=${existing.allowAutoOpenDrawer}, manual=${existing.allowManualOpenDrawer}, reg=${existing.assignedRegisterId}',
        'after_value': 'auto=$nextAuto, manual=$nextManual, reg=${clearAssignedRegister ? null : (assignedRegisterId ?? existing.assignedRegisterId)}',
        'details': 'Kebijakan terminal $terminalId diperbarui oleh $actorName.',
      });
    });

    _dbHelper.onMultiDeviceEvent?.call('terminal_policy_updated', {
      'terminal_id': terminalId,
    });
  }

  Future<void> revokeTerminal(String terminalId, {String actorName = 'Admin'}) async {
    final db = await _dbHelper.database;
    final nowIso = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      await txn.update(
        'paired_terminals',
        {'is_revoked': 1},
        where: 'terminal_id = ?',
        whereArgs: [terminalId],
      );
      await txn.update(
        'terminal_sessions',
        {'revoked_at': nowIso},
        where: "terminal_id = ? AND (revoked_at IS NULL OR revoked_at = '')",
        whereArgs: [terminalId],
      );
      await txn.insert('audit_logs', {
        'timestamp': nowIso,
        'user_id': 0,
        'user_name': actorName,
        'user_role': 'admin',
        'action_type': 'cabut_terminal',
        'module': 'Multi-Perangkat',
        'object_id': terminalId,
        'before_value': 'is_revoked=0',
        'after_value': 'is_revoked=1',
        'details': 'Akses terminal $terminalId dicabut oleh $actorName.',
      });
    });

    _dbHelper.onMultiDeviceEvent?.call('terminal_revoked', {
      'terminal_id': terminalId,
      'reason': 'Akses terminal dicabut oleh Admin',
    });
  }

  Future<Map<String, String>> rotateTerminalCredentials(
    String terminalId, {
    String actorName = 'Admin',
  }) async {
    final db = await _dbHelper.database;
    final rawToken = generateOpaqueSecret(byteLength: 32);
    final rawSecret = generateOpaqueSecret(byteLength: 32);
    final wrappedSecret = await _vaultProvider().wrapSecret(rawSecret);
    final nowIso = DateTime.now().toIso8601String();

    await db.transaction((txn) async {
      final rows = await txn.query(
        'paired_terminals',
        where: 'terminal_id = ? AND is_revoked = 0',
        whereArgs: [terminalId],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw StateError('Terminal aktif "$terminalId" tidak ditemukan.');
      }
      await txn.update(
        'paired_terminals',
        {
          'device_token_hash': sha256Hex(rawToken),
          'device_secret_hash': sha256Hex(rawSecret),
          'device_secret_enc': wrappedSecret,
        },
        where: 'terminal_id = ?',
        whereArgs: [terminalId],
      );
      await txn.insert('audit_logs', {
        'timestamp': nowIso,
        'user_id': 0,
        'user_name': actorName,
        'user_role': 'admin',
        'action_type': 'rotasi_secret_terminal',
        'module': 'Keamanan & Autentikasi',
        'object_id': terminalId,
        'before_value': '',
        'after_value': 'credential_rotated=true',
        'details': 'Token & secret HMAC terminal $terminalId dirotasi.',
      });
    });

    return {
      'terminal_id': terminalId,
      'device_token': rawToken,
      'device_secret': rawSecret,
    };
  }

  // ==================== SESSIONS ====================

  Future<T> _runWithCashierSessionLock<T>(int cashierId, Future<T> Function() fn) async {
    final prev = _cashierSessionLocks[cashierId] ?? Future<void>.value();
    final completer = Completer<void>();
    _cashierSessionLocks[cashierId] = prev.then((_) => completer.future, onError: (_) => completer.future);
    try {
      await prev.catchError((_) {});
      return await fn();
    } finally {
      completer.complete();
      if (_cashierSessionLocks[cashierId] == completer.future) {
        _cashierSessionLocks.remove(cashierId);
      }
    }
  }

  Future<Map<String, dynamic>> issueSession({
    required String terminalId,
    required UserModel cashier,
    int? shiftId,
    String? deviceName,
    Duration ttl = const Duration(hours: 8),
  }) async {
    final cashierId = cashier.id;
    if (cashierId == null) {
      throw StateError('ID akun kasir tidak valid.');
    }

    return _runWithCashierSessionLock(cashierId, () async {
      final db = await _dbHelper.database;
      final rawToken = generateOpaqueSecret(byteLength: 32);
      final tokenHash = sha256Hex(rawToken);
      final now = DateTime.now();
      final expiresAt = now.add(ttl).toIso8601String();
      final issuedAt = now.toIso8601String();
      late int maxAllowed;
      late int activeAfterIssue;

      await db.transaction((txn) async {
        maxAllowed = await _dbHelper.resolveEffectiveMaxSessionsTxn(txn, cashier);

        final termRows = await txn.query(
          'paired_terminals',
          columns: ['terminal_name'],
          where: 'terminal_id = ?',
          whereArgs: [terminalId],
          limit: 1,
        );
        final resolvedDeviceName = (deviceName != null && deviceName.trim().isNotEmpty)
            ? deviceName.trim()
            : (termRows.isNotEmpty
                ? (termRows.first['terminal_name'] ?? terminalId).toString()
                : terminalId);

        final activeRows = await txn.rawQuery('''
          SELECT ts.id, ts.terminal_id, ts.device_name, ts.issued_at, ts.expires_at,
                 COALESCE(NULLIF(TRIM(pt.terminal_name), ''), NULLIF(TRIM(ts.device_name), ''), ts.terminal_id) AS resolved_name
          FROM terminal_sessions ts
          LEFT JOIN paired_terminals pt ON pt.terminal_id = ts.terminal_id
          WHERE ts.cashier_id = ?
            AND (ts.revoked_at IS NULL OR TRIM(ts.revoked_at) = '')
            AND ts.expires_at > ?
          ORDER BY ts.id DESC
        ''', [cashierId, issuedAt]);

        final otherActive = activeRows
            .where((r) => (r['terminal_id'] ?? '').toString() != terminalId)
            .toList();

        if (otherActive.length >= maxAllowed) {
          final activeList = otherActive
              .map((r) => {
                    'terminal_id': (r['terminal_id'] ?? '').toString(),
                    'device_name': (r['resolved_name'] ?? '').toString(),
                    'issued_at': (r['issued_at'] ?? '').toString(),
                  })
              .toList();
          final deviceNames = activeList
              .map((d) => '${d['device_name']} (${d['terminal_id']})')
              .join(', ');

          await txn.insert('audit_logs', {
            'timestamp': issuedAt,
            'user_id': cashierId,
            'user_name': cashier.name,
            'user_role': cashier.role,
            'action_type': 'login_staff_ditolak_batas_sesi',
            'module': 'Keamanan & Autentikasi',
            'object_id': '$terminalId:USER-$cashierId',
            'before_value': 'active=${otherActive.length}/$maxAllowed',
            'after_value': 'rejected=$terminalId',
            'details':
                'Login "${cashier.name}" dari $terminalId ($resolvedDeviceName) ditolak karena batas maksimal $maxAllowed sesi aktif sudah terpakai oleh: $deviceNames.',
          });

          throw SessionLimitExceededException(
            activeCount: otherActive.length,
            maxAllowed: maxAllowed,
            activeDevices: activeList,
            message:
                'Akun "${cashier.name}" sudah aktif pada ${otherActive.length}/$maxAllowed perangkat ($deviceNames). Minta Admin mencabut sesi lama atau naikkan batas sesi terlebih dahulu.',
          );
        }

        // Revoke prior active session ONLY on the same terminal so 1 terminal = 1 clean active session
        await txn.update(
          'terminal_sessions',
          {
            'revoked_at': issuedAt,
            'revoked_reason': 'Digantikan login baru pada terminal yang sama',
            'revoked_by': cashier.name,
          },
          where: "terminal_id = ? AND (revoked_at IS NULL OR revoked_at = '')",
          whereArgs: [terminalId],
        );

        await txn.insert('terminal_sessions', {
          'session_token_hash': tokenHash,
          'terminal_id': terminalId,
          'cashier_id': cashierId,
          'shift_id': shiftId,
          'device_name': resolvedDeviceName,
          'issued_at': issuedAt,
          'expires_at': expiresAt,
          'last_seen_at': issuedAt,
        });
        activeAfterIssue = otherActive.length + 1;

        await txn.insert('audit_logs', {
          'timestamp': issuedAt,
          'user_id': cashierId,
          'user_name': cashier.name,
          'user_role': cashier.role,
          'action_type': 'login_staff_terminal',
          'module': 'Keamanan & Autentikasi',
          'object_id': '$terminalId:USER-$cashierId',
          'before_value': 'active_other=${otherActive.length}',
          'after_value': 'active=$activeAfterIssue/$maxAllowed expires_at=$expiresAt',
          'details':
              'Kasir "${cashier.name}" login PIN pada terminal $terminalId ($resolvedDeviceName) [Sesi $activeAfterIssue/$maxAllowed].',
        });
      });

      return {
        'session_token': rawToken,
        'expires_at': expiresAt,
        'issued_at': issuedAt,
        'max_active_sessions': maxAllowed,
        'active_session_count': activeAfterIssue,
      };
    });
  }

  Future<({ValidatedSession? ok, SessionValidationFailure? failure})> validateSession({
    required String rawSessionToken,
    required String terminalId,
  }) async {
    final cleanToken = rawSessionToken.trim();
    if (cleanToken.isEmpty) {
      return (
        ok: null,
        failure: const SessionValidationFailure('UNAUTHORIZED', 'Sesi kasir tidak disertakan.'),
      );
    }
    final db = await _dbHelper.database;
    final rows = await db.query(
      'terminal_sessions',
      where: 'session_token_hash = ?',
      whereArgs: [sha256Hex(cleanToken)],
      limit: 1,
    );
    if (rows.isEmpty) {
      return (
        ok: null,
        failure: const SessionValidationFailure('SESSION_INVALID', 'Sesi kasir tidak dikenal.'),
      );
    }
    final session = TerminalSessionModel.fromMap(rows.first);
    if (session.terminalId != terminalId) {
      return (
        ok: null,
        failure: const SessionValidationFailure('SESSION_INVALID', 'Token sesi bukan milik terminal ini.'),
      );
    }
    if (session.isRevoked) {
      return (
        ok: null,
        failure: const SessionValidationFailure('SESSION_REVOKED', 'Sesi kasir telah dicabut. Silakan login ulang.'),
      );
    }
    if (session.isExpiredAt(DateTime.now())) {
      return (
        ok: null,
        failure: const SessionValidationFailure('SESSION_EXPIRED', 'Masa berlaku sesi kasir habis. Silakan login ulang.'),
      );
    }
    final userRows = await db.query(
      'users',
      where: 'id = ?',
      whereArgs: [session.cashierId],
      limit: 1,
    );
    if (userRows.isEmpty) {
      return (
        ok: null,
        failure: const SessionValidationFailure('CASHIER_INACTIVE', 'Akun kasir tidak ditemukan.'),
      );
    }
    final cashier = UserModel.fromMap(userRows.first);
    if (!cashier.isActive) {
      return (
        ok: null,
        failure: const SessionValidationFailure('CASHIER_INACTIVE', 'Akun kasir telah dinonaktifkan oleh Admin.'),
      );
    }
    return (ok: ValidatedSession(session: session, cashier: cashier), failure: null);
  }

  Future<void> revokeSessionByRawToken(
    String rawSessionToken, {
    String actorName = 'Kasir Staff',
  }) async {
    final clean = rawSessionToken.trim();
    if (clean.isEmpty) return;
    final db = await _dbHelper.database;
    final hash = sha256Hex(clean);
    final nowIso = DateTime.now().toIso8601String();
    final existing = await db.query(
      'terminal_sessions',
      where: "session_token_hash = ? AND (revoked_at IS NULL OR revoked_at = '')",
      whereArgs: [hash],
      limit: 1,
    );
    await db.update(
      'terminal_sessions',
      {
        'revoked_at': nowIso,
        'revoked_reason': 'Logout oleh kasir',
        'revoked_by': actorName,
      },
      where: "session_token_hash = ? AND (revoked_at IS NULL OR revoked_at = '')",
      whereArgs: [hash],
    );
    if (existing.isNotEmpty) {
      final row = existing.first;
      await db.insert('audit_logs', {
        'timestamp': nowIso,
        'user_id': (row['cashier_id'] as num?)?.toInt() ?? 0,
        'user_name': actorName,
        'user_role': AppRoles.cashier,
        'action_type': 'logout_staff_terminal',
        'module': 'Keamanan & Autentikasi',
        'object_id': '${row['terminal_id']}:USER-${row['cashier_id']}',
        'before_value': 'active',
        'after_value': 'logged_out',
        'details': 'Kasir logout dari terminal ${row['terminal_id']}.',
      });
    }
  }

  Future<List<TerminalSessionDetailModel>> listTerminalSessions({
    bool includeInactive = false,
    int? cashierId,
    String? terminalId,
    int limit = 100,
  }) async {
    final db = await _dbHelper.database;
    final nowIso = DateTime.now().toIso8601String();
    final whereParts = <String>[];
    final args = <dynamic>[];
    if (!includeInactive) {
      whereParts.add("(ts.revoked_at IS NULL OR TRIM(ts.revoked_at) = '') AND ts.expires_at > ?");
      args.add(nowIso);
    }
    if (cashierId != null) {
      whereParts.add('ts.cashier_id = ?');
      args.add(cashierId);
    }
    if (terminalId != null && terminalId.trim().isNotEmpty) {
      whereParts.add('ts.terminal_id = ?');
      args.add(terminalId.trim());
    }
    final whereClause = whereParts.isEmpty ? '' : 'WHERE ${whereParts.join(' AND ')}';
    final rows = await db.rawQuery('''
      SELECT ts.*,
             COALESCE(u.name, 'Kasir #${cashierId ?? ""}') AS cashier_name,
             COALESCE(u.role, 'cashier') AS cashier_role,
             COALESCE(NULLIF(TRIM(pt.terminal_name), ''), NULLIF(TRIM(ts.device_name), ''), ts.terminal_id) AS resolved_terminal_name,
             COALESCE(pt.device_model, '') AS device_model
      FROM terminal_sessions ts
      LEFT JOIN users u ON u.id = ts.cashier_id
      LEFT JOIN paired_terminals pt ON pt.terminal_id = ts.terminal_id
      $whereClause
      ORDER BY ts.id DESC
      LIMIT ?
    ''', [...args, limit]);

    return rows
        .map((r) => TerminalSessionDetailModel(
              session: TerminalSessionModel.fromMap(r),
              cashierName: (r['cashier_name'] ?? '').toString(),
              cashierRole: (r['cashier_role'] ?? AppRoles.cashier).toString(),
              terminalName: (r['resolved_terminal_name'] ?? '').toString(),
              deviceModel: (r['device_model'] ?? '').toString(),
            ))
        .toList();
  }

  /// Revokes a single device session without affecting shifts held by other devices/cashiers.
  Future<void> revokeSessionById(
    int sessionId, {
    String actorName = 'Admin',
    String reason = 'Sesi perangkat dicabut oleh Admin',
  }) async {
    final db = await _dbHelper.database;
    final nowIso = DateTime.now().toIso8601String();
    final rows = await db.query('terminal_sessions', where: 'id = ?', whereArgs: [sessionId], limit: 1);
    if (rows.isEmpty) return;
    final row = rows.first;
    final cashierId = (row['cashier_id'] as num?)?.toInt();
    final terminalId = (row['terminal_id'] ?? '').toString();

    await db.transaction((txn) async {
      await txn.update(
        'terminal_sessions',
        {
          'revoked_at': nowIso,
          'revoked_reason': reason,
          'revoked_by': actorName,
        },
        where: "id = ? AND (revoked_at IS NULL OR revoked_at = '')",
        whereArgs: [sessionId],
      );
      await txn.insert('audit_logs', {
        'timestamp': nowIso,
        'user_id': cashierId ?? 0,
        'user_name': actorName,
        'user_role': AppRoles.owner,
        'action_type': 'cabut_sesi_staff',
        'module': 'Keamanan & Autentikasi',
        'object_id': '$terminalId:SESSION-$sessionId',
        'before_value': 'active',
        'after_value': 'revoked',
        'details': 'Sesi #$sessionId pada terminal $terminalId (Kasir #$cashierId) dicabut oleh $actorName: $reason',
      });
    });

    _dbHelper.onMultiDeviceEvent?.call('session_revoked', {
      if (cashierId != null) 'cashier_id': cashierId,
      'terminal_id': terminalId,
      'session_id': sessionId,
      'reason': reason,
    });
  }

  /// Revokes all active sessions for a specific employee account without closing shared shifts.
  Future<int> revokeAllSessionsForCashier(
    int cashierId, {
    String actorName = 'Admin',
    String reason = 'Seluruh sesi akun dicabut oleh Admin',
  }) async {
    final db = await _dbHelper.database;
    final nowIso = DateTime.now().toIso8601String();
    late int count;
    await db.transaction((txn) async {
      count = await txn.update(
        'terminal_sessions',
        {
          'revoked_at': nowIso,
          'revoked_reason': reason,
          'revoked_by': actorName,
        },
        where: "cashier_id = ? AND (revoked_at IS NULL OR revoked_at = '')",
        whereArgs: [cashierId],
      );
      await txn.insert('audit_logs', {
        'timestamp': nowIso,
        'user_id': cashierId,
        'user_name': actorName,
        'user_role': AppRoles.owner,
        'action_type': 'cabut_semua_sesi_akun',
        'module': 'Keamanan & Autentikasi',
        'object_id': 'USER-$cashierId',
        'before_value': 'active_count=$count',
        'after_value': 'revoked_all',
        'details': 'Mencabut $count sesi aktif untuk akun #$cashierId oleh $actorName ($reason).',
      });
    });
    _dbHelper.onMultiDeviceEvent?.call('session_revoked', {
      'cashier_id': cashierId,
      'reason': reason,
    });
    return count;
  }

  Future<void> touchSessionLastSeen(int sessionId) async {
    try {
      final db = await _dbHelper.database;
      await db.update(
        'terminal_sessions',
        {'last_seen_at': DateTime.now().toIso8601String()},
        where: 'id = ?',
        whereArgs: [sessionId],
      );
    } catch (_) {}
  }

  // ==================== CATALOG & CUSTOMERS (SAFE PROJECTION - NO COST_PRICE) ====================

  Future<int> getCatalogSyncVersion() async {
    final raw = await _dbHelper.getSetting('catalog_sync_version', defaultValue: '1');
    return int.tryParse(raw) ?? 1;
  }

  Map<String, dynamic> productToPublicCatalogJson(
    ProductModel p, {
    required String updatedAt,
    required int syncVersion,
  }) {
    return {
      'id': p.id,
      'code': p.code,
      'name': p.name,
      'category': p.category,
      'barcode': p.barcode,
      'is_service': p.isService,
      'track_stock': p.trackStock,
      'base_unit': p.baseUnit,
      'selling_price': p.sellingPrice,
      'stock': p.stock,
      'min_stock_alert': p.minStockAlert,
      'is_active': p.isActive,
      'brand': p.brand,
      'model': p.model,
      'condition_type': p.conditionType,
      'imei_or_sn': p.imeiOrSn,
      'warranty_info': p.warrantyInfo,
      'description': p.description,
      'updated_at': updatedAt,
      'sync_version': syncVersion,
      'units': p.units
          .map((u) => {
                'id': u.id,
                'product_id': u.productId,
                'unit_name': u.unitName,
                'conversion_factor': u.conversionFactor,
                'selling_price': u.sellingPrice,
                'barcode': u.barcode,
              })
          .toList(),
      'tiered_prices': p.tieredPrices
          .map((t) => {
                'id': t.id,
                'product_id': t.productId,
                'min_qty': t.minQty,
                'price': t.price,
              })
          .toList(),
    };
  }

  Future<Map<String, dynamic>> getCatalogProductsPage({
    int sinceVersion = 0,
    int page = 1,
    int pageSize = 100,
  }) async {
    final db = await _dbHelper.database;
    final syncVer = await getCatalogSyncVersion();
    final safePage = page < 1 ? 1 : page;
    final safeSize = pageSize.clamp(1, 200);
    final offset = (safePage - 1) * safeSize;

    final String whereClause = sinceVersion > 0 ? 'sync_version > ?' : 'is_active = 1';
    final List<dynamic> whereArgs = sinceVersion > 0 ? [sinceVersion] : [];

    final countRes = await db.rawQuery(
      'SELECT COUNT(*) as total FROM products WHERE $whereClause',
      whereArgs,
    );
    final total = (countRes.first['total'] as num?)?.toInt() ?? 0;

    final rows = await db.query(
      'products',
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: sinceVersion > 0 ? 'sync_version ASC, id ASC' : 'name ASC, id ASC',
      limit: safeSize,
      offset: offset,
    );

    final items = <Map<String, dynamic>>[];
    for (final row in rows) {
      final hydrated = await _dbHelper.hydrateProductTxn(db, row);
      items.add(
        productToPublicCatalogJson(
          hydrated,
          updatedAt: (row['updated_at'] ?? '').toString(),
          syncVersion: (row['sync_version'] as num?)?.toInt() ?? 1,
        ),
      );
    }

    return {
      'sync_version': syncVer,
      'since_version': sinceVersion,
      'page': safePage,
      'page_size': safeSize,
      'total': total,
      'has_more': (offset + items.length) < total,
      'items': items,
    };
  }

  Future<Map<String, dynamic>?> lookupByBarcodePublic(String barcode) async {
    final match = await _dbHelper.findProductAndUnitByBarcode(barcode);
    if (match == null) return null;
    final db = await _dbHelper.database;
    final rows = await db.query(
      'products',
      columns: ['updated_at', 'sync_version'],
      where: 'id = ?',
      whereArgs: [match.product.id],
      limit: 1,
    );
    final updatedAt = rows.isNotEmpty ? (rows.first['updated_at'] ?? '').toString() : '';
    final syncVer = rows.isNotEmpty ? ((rows.first['sync_version'] as num?)?.toInt() ?? 1) : 1;

    return {
      'product': productToPublicCatalogJson(
        match.product,
        updatedAt: updatedAt,
        syncVersion: syncVer,
      ),
      'matched_unit': match.matchedUnit == null
          ? null
          : {
              'id': match.matchedUnit!.id,
              'product_id': match.matchedUnit!.productId,
              'unit_name': match.matchedUnit!.unitName,
              'conversion_factor': match.matchedUnit!.conversionFactor,
              'selling_price': match.matchedUnit!.sellingPrice,
              'barcode': match.matchedUnit!.barcode,
            },
    };
  }

  Future<List<Map<String, dynamic>>> getActivePromosPublic() async {
    final promos = await _dbHelper.getActivePromos();
    return promos
        .map((p) => {
              'id': p.id,
              'name': p.name,
              'promo_type': p.promoType,
              'min_purchase': p.minPurchase,
              'discount_value': p.discountValue,
              'buy_qty': p.buyQty,
              'get_qty': p.getQty,
              'target_product_id': p.targetProductId,
              'target_product_name': p.targetProductName,
              'start_date': p.startDate.toIso8601String(),
              'end_date': p.endDate.toIso8601String(),
              'is_active': p.isActive,
              'is_running': p.isRunning,
            })
        .toList();
  }

  Future<List<Map<String, dynamic>>> listCustomersSafe({String? query}) async {
    final customers = await _dbHelper.getCustomers(query: query);
    final result = <Map<String, dynamic>>[];
    for (final c in customers) {
      final cid = c.id;
      final balance = cid != null ? await _dbHelper.getCustomerCreditBalance(cid) : 0.0;
      result.add({
        'id': cid,
        'name': c.name,
        'phone': c.phone,
        'address': c.address,
        'points': c.points,
        'credit_balance': balance,
        'is_walk_in': c.name.trim().toLowerCase() == 'pelanggan umum',
      });
    }
    return result;
  }

  Future<Map<String, dynamic>?> getCustomerDetailSafe(int customerId) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'customers',
      where: 'id = ?',
      whereArgs: [customerId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    final balance = await _dbHelper.getCustomerCreditBalance(customerId);
    final debtRows = await db.rawQuery('''
      SELECT COALESCE(SUM(CASE WHEN total_debt > paid_debt THEN (total_debt - paid_debt) ELSE 0 END), 0.0) as active_debt
      FROM customer_debts
      WHERE customer_id = ?
    ''', [customerId]);
    final activeDebt = (debtRows.first['active_debt'] as num?)?.toDouble() ?? 0.0;
    final name = (row['name'] ?? '').toString();
    return {
      'id': (row['id'] as num).toInt(),
      'name': name,
      'phone': (row['phone'] ?? '').toString(),
      'address': (row['address'] ?? '').toString(),
      'points': (row['points'] as num?)?.toInt() ?? 0,
      'credit_balance': balance,
      'active_debt': activeDebt,
      'is_walk_in': name.trim().toLowerCase() == 'pelanggan umum',
    };
  }

  // ==================== SAFE TRANSACTION / RECEIPT PROJECTION ====================

  Map<String, dynamic> transactionToPublicReceiptJson(TransactionModel trx) {
    return {
      'id': trx.id,
      'invoice_number': trx.invoiceNumber,
      'date': trx.date.toIso8601String(),
      'cashier_id': trx.cashierId,
      'cashier_name': trx.cashierName,
      'terminal_id': trx.terminalId,
      'cash_register_id': trx.cashRegisterId,
      'idempotency_key': trx.idempotencyKey,
      'customer_id': trx.customerId,
      'shift_id': trx.shiftId,
      'customer_name': trx.customerName,
      'customer_phone': trx.customerPhone,
      'subtotal': trx.subtotal,
      'discount_total': trx.discountTotal,
      'tax_amount': trx.taxAmount,
      'promo_name': trx.promoName,
      'grand_total': trx.grandTotal,
      'payment_method': trx.paymentMethod,
      'credit_used': trx.creditUsed,
      'amount_paid': trx.amountPaid,
      'change_amount': trx.changeAmount,
      'status': trx.status,
      'qr_code_payload': trx.qrCodePayload,
      'note': trx.note,
      'printer_snapshot': trx.snapshotMap,
      // Explicitly omit `cost_price` from every item pushed over LAN!
      'items': trx.items
          .map((it) => {
                'id': it.id,
                'product_id': it.productId,
                'product_code': it.productCode,
                'product_name': it.productName,
                'unit_name': it.unitName,
                'conversion_factor': it.conversionFactor,
                'qty': it.qty,
                'unit_price': it.unitPrice,
                'discount': it.discount,
                'subtotal': it.subtotal,
                'is_service': it.isService,
              })
          .toList(),
    };
  }

  Future<TransactionModel?> getTransactionById(int id) async {
    final db = await _dbHelper.database;
    final rows = await db.query('transactions', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    final trx = TransactionModel.fromMap(rows.first);
    final itemRows = await db.query('transaction_items', where: 'transaction_id = ?', whereArgs: [id]);
    trx.items = itemRows.map((e) => TransactionItemModel.fromMap(e)).toList();
    return trx;
  }

  Future<TransactionModel?> getTransactionByIdempotencyKey(String idempotencyKey) async {
    final clean = idempotencyKey.trim();
    if (clean.isEmpty) return null;
    final db = await _dbHelper.database;
    final rows = await db.query(
      'transactions',
      where: 'idempotency_key = ?',
      whereArgs: [clean],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final trx = TransactionModel.fromMap(rows.first);
    final itemRows = await db.query('transaction_items', where: 'transaction_id = ?', whereArgs: [trx.id]);
    trx.items = itemRows.map((e) => TransactionItemModel.fromMap(e)).toList();
    return trx;
  }

  Future<List<TransactionModel>> listTerminalTransactions(
    String terminalId, {
    int limit = 30,
  }) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'transactions',
      where: 'terminal_id = ?',
      whereArgs: [terminalId],
      orderBy: 'id DESC',
      limit: limit.clamp(1, 100),
    );
    final out = <TransactionModel>[];
    for (final row in rows) {
      final trx = TransactionModel.fromMap(row);
      final items = await db.query('transaction_items', where: 'transaction_id = ?', whereArgs: [trx.id]);
      trx.items = items.map((e) => TransactionItemModel.fromMap(e)).toList();
      out.add(trx);
    }
    return out;
  }

  // ==================== PRINT JOBS FIFO QUEUE ====================

  Future<PrintJobModel> enqueuePrintJob({
    required String terminalId,
    int? cashierId,
    int? transactionId,
    String invoiceNumber = '',
    int? printerId,
    String jobType = PrintJobType.receipt,
    bool isReprint = false,
    bool openDrawerRequested = false,
    String? idempotencyKey,
    Map<String, dynamic>? payload,
  }) async {
    final db = await _dbHelper.database;
    final cleanIdem = idempotencyKey?.trim();
    return await db.transaction((txn) async {
      if (cleanIdem != null && cleanIdem.isNotEmpty) {
        final existing = await txn.query(
          'print_jobs',
          where: 'idempotency_key = ?',
          whereArgs: [cleanIdem],
          limit: 1,
        );
        if (existing.isNotEmpty) {
          return PrintJobModel.fromMap(existing.first);
        }
      }

      final jobUuid = _uuid.v4();
      final nowIso = DateTime.now().toIso8601String();
      final id = await txn.insert('print_jobs', {
        'job_uuid': jobUuid,
        'terminal_id': terminalId,
        'cashier_id': cashierId,
        'transaction_id': transactionId,
        'invoice_number': invoiceNumber,
        'printer_id': printerId,
        'job_type': jobType,
        'is_reprint': isReprint ? 1 : 0,
        'open_drawer_requested': openDrawerRequested ? 1 : 0,
        'drawer_opened': 0,
        'drawer_pulse_sent': 0,
        'status': PrintJobStatus.queued,
        'attempts': 0,
        'error_message': '',
        if (cleanIdem != null && cleanIdem.isNotEmpty) 'idempotency_key': cleanIdem,
        'payload_json': payload != null ? jsonEncode(payload) : '',
        'created_at': nowIso,
      });
      final rows = await txn.query('print_jobs', where: 'id = ?', whereArgs: [id], limit: 1);
      return PrintJobModel.fromMap(rows.first);
    });
  }

  Future<PrintJobModel?> getPrintJobByUuid(String jobUuid) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'print_jobs',
      where: 'job_uuid = ?',
      whereArgs: [jobUuid.trim()],
      limit: 1,
    );
    return rows.isNotEmpty ? PrintJobModel.fromMap(rows.first) : null;
  }

  Future<List<PrintJobModel>> listPrintJobs({
    int limit = 50,
    String? status,
    String? terminalId,
  }) async {
    final db = await _dbHelper.database;
    final whereParts = <String>[];
    final args = <dynamic>[];
    if (status != null && status.isNotEmpty) {
      whereParts.add('status = ?');
      args.add(status);
    }
    if (terminalId != null && terminalId.isNotEmpty) {
      whereParts.add('terminal_id = ?');
      args.add(terminalId);
    }
    final rows = await db.query(
      'print_jobs',
      where: whereParts.isEmpty ? null : whereParts.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'id DESC',
      limit: limit.clamp(1, 200),
    );
    return rows.map((e) => PrintJobModel.fromMap(e)).toList();
  }

  Future<PrintJobModel?> claimNextQueuedPrintJob({int? printerId}) async {
    final db = await _dbHelper.database;
    return await db.transaction((txn) async {
      final where = printerId != null
          ? "(status = 'queued' OR status = 'retrying') AND (printer_id = ? OR printer_id IS NULL)"
          : "(status = 'queued' OR status = 'retrying')";
      final args = printerId != null ? [printerId] : null;
      final rows = await txn.query(
        'print_jobs',
        where: where,
        whereArgs: args,
        orderBy: 'id ASC',
        limit: 1,
      );
      if (rows.isEmpty) return null;
      final job = PrintJobModel.fromMap(rows.first);
      final updated = await txn.update(
        'print_jobs',
        {
          'status': PrintJobStatus.processing,
          'attempts': job.attempts + 1,
        },
        where: "id = ? AND (status = 'queued' OR status = 'retrying')",
        whereArgs: [job.id],
      );
      if (updated == 0) return null;
      final fresh = await txn.query('print_jobs', where: 'id = ?', whereArgs: [job.id], limit: 1);
      return PrintJobModel.fromMap(fresh.first);
    });
  }

  /// Atomically marks `drawer_pulse_sent = 1` ONCE so retries or multi-copy prints
  /// never emit a duplicate RJ11 kick pulse. Returns true iff this caller won the claim.
  Future<bool> claimOneShotDrawerPulse(int jobId) async {
    final db = await _dbHelper.database;
    final count = await db.update(
      'print_jobs',
      {'drawer_pulse_sent': 1, 'drawer_opened': 1},
      where: 'id = ? AND drawer_pulse_sent = 0',
      whereArgs: [jobId],
    );
    return count > 0;
  }

  Future<PrintJobModel> updatePrintJobState(
    int jobId, {
    required String status,
    String errorMessage = '',
    bool markCompleted = false,
  }) async {
    final db = await _dbHelper.database;
    final updates = <String, dynamic>{
      'status': status,
      'error_message': errorMessage,
      if (markCompleted) 'completed_at': DateTime.now().toIso8601String(),
    };
    await db.update('print_jobs', updates, where: 'id = ?', whereArgs: [jobId]);
    final rows = await db.query('print_jobs', where: 'id = ?', whereArgs: [jobId], limit: 1);
    return PrintJobModel.fromMap(rows.first);
  }

  Future<PrintJobModel> retryPrintJob(String jobUuid) async {
    final db = await _dbHelper.database;
    final rows = await db.query('print_jobs', where: 'job_uuid = ?', whereArgs: [jobUuid], limit: 1);
    if (rows.isEmpty) {
      throw StateError('Job cetak tidak ditemukan.');
    }
    final job = PrintJobModel.fromMap(rows.first);
    // CRITICAL SECURITY/ANTI-FRAUD: retrying a failed print MUST preserve drawer_pulse_sent
    // and never trigger a second automatic cash drawer opening on reprint/retry.
    await db.update(
      'print_jobs',
      {
        'status': PrintJobStatus.queued,
        'error_message': '',
        'completed_at': null,
      },
      where: 'id = ?',
      whereArgs: [job.id],
    );
    final updated = await db.query('print_jobs', where: 'id = ?', whereArgs: [job.id], limit: 1);
    return PrintJobModel.fromMap(updated.first);
  }

  Future<void> cancelPrintJob(String jobUuid) async {
    final db = await _dbHelper.database;
    await db.update(
      'print_jobs',
      {
        'status': PrintJobStatus.cancelled,
        'completed_at': DateTime.now().toIso8601String(),
      },
      where: "job_uuid = ? AND status IN ('queued', 'retrying')",
      whereArgs: [jobUuid],
    );
  }
}
