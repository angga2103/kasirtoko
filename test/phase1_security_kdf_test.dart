import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:kasirtoko/database/db_helper.dart';
import 'package:kasirtoko/models/user.dart';
import 'package:kasirtoko/providers/auth_provider.dart';
import 'package:kasirtoko/utils/date_format.dart';
import 'package:kasirtoko/utils/security_helper.dart';

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await DateHelper.ensureInitialized();
  });

  tearDown(() async {
    SecurityHelper.resetTestConfiguration();
    await DatabaseHelper.instance.closeTestDatabase();
  });

  group('Phase 1 — SecurityHelper KDF v2 (PBKDF2-HMAC-SHA256)', () {
    test('uses tested PointyCastle PBKDF2-HMAC-SHA256 with deterministic RFC vector parity', () {
      // Known RFC / NIST PBKDF2-HMAC-SHA256 check (1-iteration block parity + multi-iteration determinism)
      final dk1 = SecurityHelper.derivePbkdf2PointyCastle(
        inputBytes: Uint8List.fromList(utf8.encode('password')),
        saltBytes: Uint8List.fromList(utf8.encode('salt')),
        iterations: 1,
        keyLength: 32,
      );
      // RFC/standard PBKDF2-HMAC-SHA256("password", "salt", 1, 32) = 120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b
      final hex1 = dk1.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      expect(hex1, '120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b');

      final dk2 = SecurityHelper.derivePbkdf2PointyCastle(
        inputBytes: Uint8List.fromList(utf8.encode('password')),
        saltBytes: Uint8List.fromList(utf8.encode('salt')),
        iterations: 2,
        keyLength: 32,
      );
      // PBKDF2-HMAC-SHA256("password", "salt", 2, 32) = ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43
      final hex2 = dk2.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      expect(hex2, 'ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43');
    });

    test('produces versioned PHC v2 hashes with 600,000 iterations, Keystore pepper & domain separation',
        timeout: const Timeout(Duration(minutes: 2)), () async {
      final pepperA = InMemoryPepperProvider(Uint8List.fromList(List.generate(32, (i) => i + 1)));
      final pepperB = InMemoryPepperProvider(Uint8List.fromList(List.generate(32, (i) => i + 99)));

      SecurityHelper.configureForTesting(
        pepperProvider: pepperA,
        iterations: SecurityHelper.defaultPbkdf2Iterations,
      );

      final pinRes = await SecurityHelper.hashSecretV2(
        '4829',
        domain: SecurityHelper.domainPin,
      );
      final pwRes = await SecurityHelper.hashSecretV2(
        '4829',
        domain: SecurityHelper.domainPassword,
      );

      expect(SecurityHelper.isV2PhcHash(pinRes.hash), isTrue);
      expect(pinRes.salt, isNot(equals(pwRes.salt)));
      expect(pinRes.hash, isNot(equals(pwRes.hash)));

      final parsed = SecurityHelper.parseV2Hash(pinRes.hash)!;
      expect(parsed.algorithm, 'pbkdf2-sha256');
      expect(parsed.version, 2);
      expect(parsed.iterations, 600000);
      expect(parsed.keyLength, 32);
      expect(parsed.domain, SecurityHelper.domainPin);
      expect(parsed.peppered, isTrue);

      expect(
        await SecurityHelper.verifySecretV2(
          '4829',
          pinRes.hash,
          expectedDomain: SecurityHelper.domainPin,
        ),
        isTrue,
      );
      // Domain separation prevents PIN hash verifying in password domain and vice versa
      expect(
        await SecurityHelper.verifySecretV2(
          '4829',
          pinRes.hash,
          expectedDomain: SecurityHelper.domainPassword,
        ),
        isFalse,
      );
      expect(
        await SecurityHelper.verifySecretV2(
          '0000',
          pinRes.hash,
          expectedDomain: SecurityHelper.domainPin,
        ),
        isFalse,
      );

      // Rotating Keystore pepper invalidates old pepper-bound verification unless verified with original pepper
      SecurityHelper.configureForTesting(
        pepperProvider: pepperB,
        iterations: SecurityHelper.defaultPbkdf2Iterations,
      );
      expect(
        await SecurityHelper.verifySecretV2(
          '4829',
          pinRes.hash,
          expectedDomain: SecurityHelper.domainPin,
        ),
        isFalse,
      );
    });

    test('transparently migrates legacy_v1 accounts to KDF v2 with separated PIN/password salts + audit log',
        timeout: const Timeout(Duration(minutes: 2)), () async {
      final dbDir = await databaseFactoryFfi.getDatabasesPath();
      final dbPath = '$dbDir/test_kdf_migration.db';
      SecurityHelper.configureForTesting(
        pepperProvider: InMemoryPepperProvider(Uint8List.fromList(List.filled(32, 7))),
        iterations: 600000,
      );
      final db = await DatabaseHelper.instance.openTestDatabase(path: dbPath);

      final legacySalt = SecurityHelper.generateSalt();
      final legacyPinHash = SecurityHelper.hashLegacyV1Secret('7788', legacySalt);
      final legacyPwHash = SecurityHelper.hashLegacyV1Secret('rahasia99', legacySalt);

      final legacyId = await db.insert('users', {
        'name': 'Kasir Legacy',
        'username': 'kasir_legacy',
        'password_hash': legacyPwHash,
        'password_salt': legacySalt,
        'pin': '',
        'pin_hash': legacyPinHash,
        'pin_salt': '',
        'hash_version': SecurityHelper.hashVersionLegacyV1,
        'pin_lookup_hash': '',
        'role': AppRoles.cashier,
        'is_active': 1,
      });

      final pinRes = await DatabaseHelper.instance.authenticateWithPin('7788', terminalId: 'ADMIN');
      expect(pinRes.isSuccess, isTrue);
      final afterPinLogin = pinRes.user!;
      expect(afterPinLogin.id, legacyId);
      expect(SecurityHelper.isV2PhcHash(afterPinLogin.pinHash), isTrue);
      expect(afterPinLogin.pinSalt, isNotEmpty);
      expect(afterPinLogin.pinSalt, isNot(equals(afterPinLogin.passwordSalt)));
      expect(afterPinLogin.pinLookupHash, isNotEmpty);
      expect(afterPinLogin.pin, '');
      // Password was not supplied yet so pinHash is v2 while passwordHash still verifies legacy_v1
      expect(SecurityHelper.isV2PhcHash(afterPinLogin.passwordHash), isFalse);

      // Now log in with password -> password hash also migrates to v2 and account becomes fully v2_pbkdf2_sha256
      final pwRes = await DatabaseHelper.instance.authenticateWithPassword(
        'kasir_legacy',
        'rahasia99',
        terminalId: 'ADMIN',
      );
      expect(pwRes.isSuccess, isTrue);
      final afterPwLogin = pwRes.user!;
      expect(SecurityHelper.isV2PhcHash(afterPwLogin.passwordHash), isTrue);
      expect(afterPwLogin.passwordSalt, isNot(equals(afterPwLogin.pinSalt)));
      expect(afterPwLogin.hashVersion, SecurityHelper.hashVersionV2Pbkdf2);

      final migLogs = await DatabaseHelper.instance.getAuditLogsFiltered(actionType: 'migrasi_kdf_akun');
      expect(migLogs.length, 2);
      expect(migLogs.every((l) => l.objectId == 'USER-$legacyId'), isTrue);
    });

    test('enforces progressive rate limit, lockout, audit trail, and separate PIN salt via AuthProvider', () async {
      final dbDir = await databaseFactoryFfi.getDatabasesPath();
      SecurityHelper.configureForTesting(
        pepperProvider: InMemoryPepperProvider(Uint8List.fromList(List.filled(32, 11))),
        iterations: 50000, // Fast test iteration count for multi-attempt lockout flow
      );
      final db = await DatabaseHelper.instance.openTestDatabase(path: '$dbDir/test_rate_limit.db');

      final kasirRow = (await db.query('users', where: "username = 'kasir'", limit: 1)).first;
      final kasirId = kasirRow['id'] as int;

      // 4 failed attempts -> invalidCredentials
      for (int i = 0; i < 4; i++) {
        final r = await DatabaseHelper.instance.authenticateWithPin(
          '9999',
          userId: kasirId,
          terminalId: 'STAFF-99',
        );
        expect(r.status, AuthAttemptStatus.invalidCredentials);
      }

      // 5th failed attempt -> triggers lockout (60s)
      final fifth = await DatabaseHelper.instance.authenticateWithPin(
        '9999',
        userId: kasirId,
        terminalId: 'STAFF-99',
      );
      expect(fifth.status, AuthAttemptStatus.lockedOut);
      expect(fifth.retryAfterSeconds, greaterThan(0));

      // Even the correct PIN MUST be rejected while account/terminal is locked!
      final blockedEvenCorrect = await DatabaseHelper.instance.authenticateWithPin(
        '1111',
        userId: kasirId,
        terminalId: 'STAFF-99',
      );
      expect(blockedEvenCorrect.status, AuthAttemptStatus.lockedOut);

      final failLogs = await DatabaseHelper.instance.getAuditLogsFiltered(actionType: 'login_gagal');
      final lockLogs = await DatabaseHelper.instance.getAuditLogsFiltered(actionType: 'pin_lockout');
      expect(failLogs.length, 4);
      expect(lockLogs.length, 1);

      // AuthProvider employee creation enforces duplicate PIN guard + separate pin_salt & password_salt
      final authProv = AuthProvider();
      await authProv.loginWithPin('123456');
      await authProv.loadUsers();

      final dupPinErr = await authProv.saveEmployee(
        name: 'Kasir Duplikat',
        username: 'kasir_dup',
        role: AppRoles.cashier,
        phone: '08111',
        newPassword: 'password1',
        newPin: '1111',
        permissions: AppPermissions.defaultForRole(AppRoles.cashier),
      );
      expect(dupPinErr, isNotNull);

      final okErr = await authProv.saveEmployee(
        name: 'Kasir Dua',
        username: 'kasir2',
        role: AppRoles.cashier,
        phone: '081234',
        newPassword: 'password2',
        newPin: '5656',
        permissions: AppPermissions.defaultForRole(AppRoles.cashier),
      );
      expect(okErr, isNull);
      final kasir2 = authProv.users.firstWhere((u) => u.username == 'kasir2');
      expect(kasir2.pinSalt, isNotEmpty);
      expect(kasir2.passwordSalt, isNotEmpty);
      expect(kasir2.pinSalt, isNot(equals(kasir2.passwordSalt)));
      expect(kasir2.hashVersion, SecurityHelper.hashVersionV2Pbkdf2);
    });

    test('benchmarks PBKDF2-HMAC-SHA256 at 600,000 iterations on current runtime', () async {
      SecurityHelper.configureForTesting(
        pepperProvider: InMemoryPepperProvider(Uint8List.fromList(List.filled(32, 3))),
        iterations: 600000,
      );
      final bench = await SecurityHelper.benchmarkPbkdf2(iterations: 600000);
      // ignore: avoid_print
      print('PBKDF2-HMAC-SHA256 Benchmark (${bench.engine}): ${bench.iterations} iters = ${bench.elapsedMs} ms');
      expect(bench.iterations, 600000);
      expect(bench.elapsedMs, greaterThan(0));
    });
  });
}
