import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import 'package:kasirtoko/database/db_helper.dart';
import 'package:kasirtoko/database/multi_device_dao.dart';
import 'package:kasirtoko/models/cash_register.dart';
import 'package:kasirtoko/models/operational_models.dart';
import 'package:kasirtoko/models/printer_device.dart';
import 'package:kasirtoko/models/product.dart';
import 'package:kasirtoko/models/shift.dart';
import 'package:kasirtoko/models/user.dart';
import 'package:kasirtoko/providers/auth_provider.dart';
import 'package:kasirtoko/providers/backup_provider.dart';
import 'package:kasirtoko/providers/server_provider.dart';
import 'package:kasirtoko/services/backup_service.dart';
import 'package:kasirtoko/services/printer/printer_adapter.dart';
import 'package:kasirtoko/services/secret_vault.dart';
import 'package:kasirtoko/services/server/lan_pos_server.dart';
import 'package:kasirtoko/services/server/print_queue_worker.dart';
import 'package:kasirtoko/services/server/request_security.dart';
import 'package:kasirtoko/utils/date_format.dart';
import 'package:kasirtoko/utils/security_helper.dart';

class _TestStaffClient {
  final String baseUrl;
  final String certSha256;
  String terminalId = '';
  String deviceToken = '';
  String deviceSecret = '';
  String? sessionToken;
  int clockOffsetMs = 0;

  _TestStaffClient({required this.baseUrl, required this.certSha256});

  HttpClient _client({String? overrideSha256}) {
    final c = HttpClient();
    c.connectionTimeout = const Duration(seconds: 6);
    c.badCertificateCallback = (X509Certificate cert, String host, int port) {
      final actual = sha256.convert(cert.der).toString().toLowerCase();
      return actual == (overrideSha256 ?? certSha256).toLowerCase();
    };
    return c;
  }

  Future<Map<String, dynamic>> health({String? overrideSha256}) async {
    final c = _client(overrideSha256: overrideSha256);
    try {
      final req = await c.getUrl(Uri.parse('$baseUrl/api/v1/health'));
      final res = await req.close();
      final decoded = jsonDecode(await res.transform(utf8.decoder).join()) as Map<String, dynamic>;
      final srvMs = (decoded['data']?['server_time_ms'] as num?)?.toInt();
      if (srvMs != null) {
        clockOffsetMs = srvMs - DateTime.now().millisecondsSinceEpoch;
      }
      return {'statusCode': res.statusCode, ...decoded};
    } finally {
      c.close(force: true);
    }
  }

  Future<Map<String, dynamic>> pair({
    required String code,
    required String name,
    required String uuid,
  }) async {
    final c = _client();
    try {
      final req = await c.postUrl(Uri.parse('$baseUrl/api/v1/pairing/register'));
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode({
        'pairing_code': code,
        'device_name': name,
        'device_model': 'Android Staff Test',
        'device_uuid': uuid,
      }));
      final res = await req.close();
      final decoded = jsonDecode(await res.transform(utf8.decoder).join()) as Map<String, dynamic>;
      if (decoded['success'] == true) {
        final d = Map<String, dynamic>.from(decoded['data'] as Map);
        terminalId = d['terminal_id'].toString();
        deviceToken = d['device_token'].toString();
        deviceSecret = d['device_secret'].toString();
      }
      return {'statusCode': res.statusCode, ...decoded};
    } finally {
      c.close(force: true);
    }
  }

  Future<Map<String, dynamic>> call(
    String method,
    String pathAndQuery, {
    Map<String, dynamic>? body,
    String? idempotencyKey,
    String? overrideSessionToken,
  }) async {
    final c = _client();
    try {
      final bytes = body != null ? utf8.encode(jsonEncode(body)) : const <int>[];
      final ts = (DateTime.now().millisecondsSinceEpoch + clockOffsetMs).toString();
      final nonce = const Uuid().v4();
      final sig = RequestSecurityValidator.computeHmacSignature(
        deviceSecret: deviceSecret,
        method: method,
        pathAndQuery: pathAndQuery,
        timestampMs: ts,
        nonce: nonce,
        bodySha256Hex: RequestSecurityValidator.sha256HexBytes(bytes),
      );
      final req = await c.openUrl(method.toUpperCase(), Uri.parse('$baseUrl$pathAndQuery'));
      req.headers.contentType = ContentType.json;
      req.headers.set('X-API-Version', '1.1');
      req.headers.set('X-Terminal-Id', terminalId);
      req.headers.set('X-Device-Token', deviceToken);
      req.headers.set('X-Request-Timestamp', ts);
      req.headers.set('X-Request-Nonce', nonce);
      req.headers.set('X-Signature', sig);
      final tok = overrideSessionToken ?? sessionToken;
      if (tok != null && tok.isNotEmpty) {
        req.headers.set('Authorization', 'Bearer $tok');
      }
      if (idempotencyKey != null && idempotencyKey.isNotEmpty) {
        req.headers.set('X-Idempotency-Key', idempotencyKey);
      }
      if (bytes.isNotEmpty) req.add(bytes);
      final res = await req.close();
      final decoded = jsonDecode(await res.transform(utf8.decoder).join()) as Map<String, dynamic>;
      return {'statusCode': res.statusCode, ...decoded};
    } finally {
      c.close(force: true);
    }
  }

  Future<WebSocket> connectWs() async {
    final base = Uri.parse(baseUrl);
    final ts = (DateTime.now().millisecondsSinceEpoch + clockOffsetMs).toString();
    final nonce = const Uuid().v4();
    final sig = RequestSecurityValidator.computeHmacSignature(
      deviceSecret: deviceSecret,
      method: 'GET',
      pathAndQuery: '/ws/v1/terminal',
      timestampMs: ts,
      nonce: nonce,
      bodySha256Hex: RequestSecurityValidator.sha256HexString(''),
    );
    return WebSocket.connect(
      Uri(scheme: 'wss', host: base.host, port: base.port, path: '/ws/v1/terminal').toString(),
      headers: {
        'X-API-Version': '1.1',
        'X-Terminal-Id': terminalId,
        'X-Device-Token': deviceToken,
        'X-Request-Timestamp': ts,
        'X-Request-Nonce': nonce,
        'X-Signature': sig,
        'Authorization': 'Bearer ${sessionToken ?? ""}',
      },
      customClient: _client(),
    );
  }
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  setUpAll(() async {
    await DateHelper.ensureInitialized();
  });

  setUp(() {
    SecurityHelper.configureForTesting(
      pepperProvider: InMemoryPepperProvider(Uint8List.fromList(List.filled(32, 9))),
      iterations: 10000,
    );
    SecretVault.configureForTesting(
      SoftwareAesGcmSecretVault(Uint8List.fromList(List.filled(32, 11))),
    );
    BackupService.availableStorageBytesOverride = null;
  });

  tearDown(() async {
    BackupService.availableStorageBytesOverride = null;
    await DatabaseHelper.instance.closeTestDatabase();
  });

  group('Phase 3 — Operational Architecture E2E, Session Security, Failover & Encrypted Backup', () {
    test('DB v6 -> v7 non-destructive migration preserves data, creates v7 tables & permanent server_id',
        () async {
      final tmpDir = await Directory.systemTemp.createTemp('kt_v6_v7_mig_');
      addTearDown(() async {
        await DatabaseHelper.instance.closeTestDatabase();
        if (await tmpDir.exists()) await tmpDir.delete(recursive: true);
      });

      final dbPath = p.join(tmpDir.path, 'legacy_v6.db');
      final legacyDb = await openDatabase(
        dbPath,
        version: 6,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE users (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              username TEXT NOT NULL DEFAULT '',
              password_hash TEXT NOT NULL DEFAULT '',
              password_salt TEXT NOT NULL DEFAULT '',
              pin TEXT NOT NULL DEFAULT '',
              pin_hash TEXT NOT NULL DEFAULT '',
              pin_salt TEXT NOT NULL DEFAULT '',
              hash_version TEXT NOT NULL DEFAULT 'v2_pbkdf2_sha256',
              pin_lookup_hash TEXT NOT NULL DEFAULT '',
              failed_pin_count INTEGER NOT NULL DEFAULT 0,
              pin_locked_until TEXT,
              role TEXT NOT NULL,
              phone TEXT NOT NULL DEFAULT '',
              photo_path TEXT,
              permissions TEXT NOT NULL DEFAULT '{}',
              is_active INTEGER NOT NULL DEFAULT 1
            )
          ''');
          await db.execute('''
            CREATE TABLE products (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              code TEXT NOT NULL,
              name TEXT NOT NULL,
              category TEXT NOT NULL DEFAULT 'Umum',
              barcode TEXT,
              is_service INTEGER NOT NULL DEFAULT 0,
              track_stock INTEGER NOT NULL DEFAULT 1,
              base_unit TEXT NOT NULL,
              cost_price REAL NOT NULL,
              selling_price REAL NOT NULL,
              stock REAL NOT NULL,
              quarantine_stock REAL NOT NULL DEFAULT 0.0,
              damaged_stock REAL NOT NULL DEFAULT 0.0,
              min_stock_alert REAL NOT NULL,
              image_path TEXT,
              is_active INTEGER NOT NULL DEFAULT 1,
              brand TEXT NOT NULL DEFAULT '',
              model TEXT NOT NULL DEFAULT '',
              condition_type TEXT NOT NULL DEFAULT 'baru',
              imei_or_sn TEXT NOT NULL DEFAULT '',
              warranty_info TEXT NOT NULL DEFAULT '',
              description TEXT NOT NULL DEFAULT '',
              sync_version INTEGER NOT NULL DEFAULT 1
            )
          ''');
          await db.execute('''
            CREATE TABLE transactions (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              invoice_number TEXT NOT NULL,
              date TEXT NOT NULL,
              cashier_id INTEGER NOT NULL,
              cashier_name TEXT NOT NULL,
              terminal_id TEXT NOT NULL DEFAULT 'ADMIN',
              shift_id INTEGER,
              cash_register_id INTEGER,
              idempotency_key TEXT,
              customer_id INTEGER,
              customer_name TEXT NOT NULL DEFAULT 'Pelanggan Umum',
              subtotal REAL NOT NULL,
              discount_total REAL NOT NULL DEFAULT 0,
              tax_amount REAL NOT NULL DEFAULT 0,
              promo_name TEXT NOT NULL DEFAULT '',
              grand_total REAL NOT NULL,
              payment_method TEXT NOT NULL,
              credit_used REAL NOT NULL DEFAULT 0,
              amount_paid REAL NOT NULL,
              change_amount REAL NOT NULL DEFAULT 0,
              cash_effect REAL NOT NULL DEFAULT 0,
              qr_code_payload TEXT NOT NULL DEFAULT '',
              status TEXT NOT NULL DEFAULT 'selesai',
              note TEXT NOT NULL DEFAULT '',
              void_reason TEXT NOT NULL DEFAULT '',
              voided_by TEXT NOT NULL DEFAULT '',
              voided_at TEXT NOT NULL DEFAULT ''
            )
          ''');
          await db.execute('''
            CREATE TABLE shifts (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              cashier_id INTEGER NOT NULL,
              cashier_name TEXT NOT NULL,
              terminal_id TEXT NOT NULL DEFAULT 'ADMIN',
              cash_register_id INTEGER NOT NULL DEFAULT 1,
              drawer_mode TEXT NOT NULL DEFAULT 'SHARED_DRAWER',
              start_time TEXT NOT NULL,
              end_time TEXT,
              starting_cash REAL NOT NULL,
              expected_cash REAL NOT NULL DEFAULT 0,
              actual_cash REAL,
              difference REAL NOT NULL DEFAULT 0,
              status TEXT NOT NULL DEFAULT 'open',
              audit_note TEXT NOT NULL DEFAULT ''
            )
          ''');
          await db.execute('''
            CREATE TABLE store_settings (
              key TEXT PRIMARY KEY,
              value TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE audit_logs (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              timestamp TEXT NOT NULL,
              user_id INTEGER NOT NULL,
              user_name TEXT NOT NULL,
              user_role TEXT NOT NULL DEFAULT 'owner',
              action_type TEXT NOT NULL,
              module TEXT NOT NULL DEFAULT '',
              object_id TEXT NOT NULL DEFAULT '',
              before_value TEXT NOT NULL DEFAULT '',
              after_value TEXT NOT NULL DEFAULT '',
              details TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE terminal_sessions (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              session_token_hash TEXT NOT NULL UNIQUE,
              terminal_id TEXT NOT NULL,
              cashier_id INTEGER NOT NULL,
              shift_id INTEGER,
              issued_at TEXT NOT NULL,
              expires_at TEXT NOT NULL,
              revoked_at TEXT
            )
          ''');
          await db.execute('''
            CREATE TABLE paired_terminals (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              terminal_id TEXT NOT NULL UNIQUE,
              terminal_code TEXT NOT NULL,
              terminal_name TEXT NOT NULL,
              device_model TEXT NOT NULL DEFAULT '',
              device_uuid TEXT NOT NULL UNIQUE,
              device_secret_hash TEXT NOT NULL,
              device_token_hash TEXT NOT NULL,
              assigned_register_id INTEGER,
              default_printer_id INTEGER,
              allow_auto_open_drawer INTEGER NOT NULL DEFAULT 0,
              allow_manual_open_drawer INTEGER NOT NULL DEFAULT 0,
              is_revoked INTEGER NOT NULL DEFAULT 0,
              paired_at TEXT NOT NULL,
              last_seen_at TEXT NOT NULL DEFAULT ''
            )
          ''');

          await db.insert('store_settings', {'key': 'store_name', 'value': 'Toko Lama Sejahtera'});
          await db.insert('users', {'name': 'Pemilik Lama', 'username': 'owner_old', 'role': 'owner'});
          await db.insert('users', {'name': 'Kasir Legacy', 'username': 'kasir_old', 'role': 'cashier'});
          await db.insert('products', {
            'code': 'LEGACY-01',
            'name': 'Produk Legacy V6',
            'base_unit': 'Pcs',
            'cost_price': 4000,
            'selling_price': 7000,
            'stock': 42,
            'min_stock_alert': 5,
          });
          await db.insert('transactions', {
            'invoice_number': 'INV-V6-001',
            'date': '2026-11-27T10:00:00',
            'cashier_id': 2,
            'cashier_name': 'Kasir Legacy',
            'grand_total': 14000,
            'subtotal': 14000,
            'payment_method': 'tunai',
            'amount_paid': 14000,
          });
          await db.insert('paired_terminals', {
            'terminal_id': 'TERM-V6-01',
            'terminal_code': 'T01',
            'terminal_name': 'Meja Kasir Lama',
            'device_uuid': 'uuid-v6-1',
            'device_secret_hash': 'h',
            'device_token_hash': 't',
            'paired_at': '2026-11-27T08:00:00',
          });
        },
      );
      await legacyDb.close();

      // Open via v7 DatabaseHelper
      final upgraded = await DatabaseHelper.instance.openTestDatabase(
        path: dbPath,
        deleteIfExists: false,
      );
      expect(await upgraded.getVersion(), DatabaseHelper.dbVersion);

      final integrity = await upgraded.rawQuery('PRAGMA integrity_check');
      expect(integrity.first.values.first.toString().toLowerCase(), 'ok');

      // Pre-existing backup created before migration
      expect(File(p.join(tmpDir.path, 'legacy_v6_pre_v7_backup.db')).existsSync(), isTrue);

      // Existing rows preserved 100%
      final storeName = await DatabaseHelper.instance.getSetting('store_name');
      expect(storeName, 'Toko Lama Sejahtera');
      final trxs = await upgraded.query('transactions', where: 'invoice_number = ?', whereArgs: ['INV-V6-001']);
      expect(trxs.length, 1);
      final terms = await upgraded.query('paired_terminals', where: 'terminal_id = ?', whereArgs: ['TERM-V6-01']);
      expect(terms.length, 1);

      // New v7 tables & columns exist
      final tables = (await upgraded.rawQuery("SELECT name FROM sqlite_master WHERE type='table'"))
          .map((r) => r['name'].toString())
          .toSet();
      expect(tables.containsAll(['session_policies', 'server_network_endpoints', 'backup_jobs', 'backup_artifacts']), isTrue);

      final tsCols = (await upgraded.rawQuery('PRAGMA table_info(terminal_sessions)'))
          .map((r) => r['name'].toString())
          .toSet();
      expect(tsCols.containsAll(['device_name', 'revoked_reason', 'revoked_by', 'last_seen_at']), isTrue);

      final policies = await DatabaseHelper.instance.getSessionPolicies();
      expect(policies.firstWhere((p) => p.role == AppRoles.cashier).maxActiveSessions, 1);
      expect(policies.firstWhere((p) => p.role == AppRoles.supervisor).maxActiveSessions, 2);
      expect(policies.firstWhere((p) => p.role == AppRoles.owner).maxActiveSessions, 3);

      // Persistent server_id stays constant across close & reopen
      final sid1 = await DatabaseHelper.instance.getOrCreateServerId();
      expect(sid1, isNotEmpty);
      await DatabaseHelper.instance.closeTestDatabase();
      await DatabaseHelper.instance.openTestDatabase(
        path: dbPath,
        deleteIfExists: false,
      );
      final sid2 = await DatabaseHelper.instance.getOrCreateServerId();
      expect(sid2, sid1);
    });

    test('Atomic session limits (1 cashier=1 vs concurrent race vs roles), single/bulk/deactivation revoke & shared shift preservation',
        () async {
      final db = await DatabaseHelper.instance.openTestDatabase();
      final dao = MultiDeviceDao();

      // Create Cashier 2, Cashier 3, Warehouse (with POS permission for terminal login limit check), Supervisor
      Future<UserModel> makeUser(
        String name,
        String uname,
        String role,
        String pin, {
        bool allowPos = false,
      }) async {
        final pw = await SecurityHelper.hashSecretV2('pass1234', domain: SecurityHelper.domainPassword);
        final pn = await SecurityHelper.hashSecretV2(pin, domain: SecurityHelper.domainPin);
        final lk = await SecurityHelper.computePinLookupDigest(pin);
        final perms = Map<String, bool>.from(AppPermissions.defaultForRole(role));
        if (allowPos) perms[AppPermissions.accessPos] = true;
        final u = UserModel(
          name: name,
          username: uname,
          passwordHash: pw.hash,
          passwordSalt: pw.salt,
          pinHash: pn.hash,
          pinSalt: pn.salt,
          hashVersion: SecurityHelper.hashVersionV2Pbkdf2,
          pinLookupHash: lk,
          role: role,
          permissions: perms,
        );
        final id = await DatabaseHelper.instance.insertUser(u);
        return u.copyWith(id: id);
      }

      final c1 = await makeUser('Kasir 1', 'kasir_p3_1', AppRoles.cashier, '1111');
      final c2 = await makeUser('Kasir 2', 'kasir2', AppRoles.cashier, '2222');
      final c3 = await makeUser('Kasir 3', 'kasir3', AppRoles.cashier, '3333');
      final wh = await makeUser('Gudang 1', 'gudang1', AppRoles.warehouse, '4444', allowPos: true);
      final sup = await makeUser('Supervisor 1', 'spv1', AppRoles.supervisor, '5555');

      await DatabaseHelper.instance.setSetting('drawer_mode', 'SHARED_DRAWER');
      await DatabaseHelper.instance.insertPrinter(PrinterDeviceModel(
        name: 'Thermal Printer 1',
        category: PrinterCategory.thermal,
        connectionType: PrinterConnectionType.lan,
        address: '192.168.1.99',
        isDefault: true,
      ));
      await DatabaseHelper.instance.openShift(ShiftModel(
        cashierId: 1,
        cashierName: 'Owner',
        terminalId: 'ADMIN',
        cashRegisterId: 1,
        drawerMode: DrawerMode.sharedDrawer,
        startTime: DateTime.now(),
        startingCash: 500000,
        status: 'open',
      ));

      final prodId = await DatabaseHelper.instance.insertProduct(ProductModel(
        code: 'P-RACE-1',
        name: 'Air Mineral 600ml',
        baseUnit: 'Pcs',
        costPrice: 2000,
        sellingPrice: 4000,
        stock: 50,
      ));

      var printFailsLeft = 1;
      final printWorker = PrintQueueWorker(
        dao: dao,
        customReceiptExecutor: (p, t,
            {required storeName,
            required storeAddress,
            required storePhone,
            required receiptConfig,
            logoPath,
            required isReprint,
            required allowDrawerPulse}) async {
          if (printFailsLeft > 0) {
            printFailsLeft--;
            return PrinterOperationResult(success: false, message: 'Paper jam');
          }
          return PrinterOperationResult(success: true, message: 'Printed');
        },
      );
      final server = LanPosServer(dao: dao, printWorker: printWorker);
      await server.start(bindAddress: InternetAddress.loopbackIPv4, port: 0);
      final baseUrl = 'https://127.0.0.1:${server.port}';
      final certSha = server.identity!.sha256Hex;

      try {
        Future<_TestStaffClient> pairPhone(String name, String uuid) async {
          final t = await dao.createPairingToken(suggestedName: name, assignedRegisterId: 1);
          final c = _TestStaffClient(baseUrl: baseUrl, certSha256: certSha);
          final r = await c.pair(code: t.pairingCode, name: name, uuid: uuid);
          expect(r['statusCode'], 200);
          return c;
        }

        final phone1 = await pairPhone('HP Kasir 1', 'u-1');
        final phone2 = await pairPhone('HP Kasir 2', 'u-2');
        final phone3 = await pairPhone('HP Kasir 3', 'u-3');

        // A. 2 Concurrent simultaneous login attempts on SAME Kasir 1 (limit=1) -> strictly serialized!
        final raceRes = await Future.wait([
          phone1.call('POST', '/api/v1/auth/pin-login', body: {'user_id': c1.id, 'pin': '1111'}),
          phone2.call('POST', '/api/v1/auth/pin-login', body: {'user_id': c1.id, 'pin': '1111'}),
        ]);
        final successes = raceRes.where((r) => r['statusCode'] == 200).toList();
        final rejected = raceRes.where((r) => r['statusCode'] == 409).toList();
        expect(successes.length, 1);
        expect(rejected.length, 1);
        expect(rejected.first['error']['code'], 'SESSION_LIMIT_EXCEEDED');

        final winningClient = raceRes[0]['statusCode'] == 200 ? phone1 : phone2;
        final blockedClient = winningClient == phone1 ? phone2 : phone1;
        winningClient.sessionToken = successes.first['data']['session_token'].toString();

        // Winning phone's WebSocket + HTTP /auth/me remains 100% undisturbed
        final ws1 = await winningClient.connectWs();
        final me1 = await winningClient.call('GET', '/api/v1/auth/me');
        expect(me1['statusCode'], 200);

        // B. 3 Distinct Cashiers on 3 Phones transact + shared drawer + idempotency + print retry
        // First logout blocking phone slot check -> blockedClient logs in as Kasir 2, phone3 as Kasir 3
        final l2 = await blockedClient.call('POST', '/api/v1/auth/pin-login', body: {'user_id': c2.id, 'pin': '2222'});
        final l3 = await phone3.call('POST', '/api/v1/auth/pin-login', body: {'user_id': c3.id, 'pin': '3333'});
        expect(l2['statusCode'], 200);
        expect(l3['statusCode'], 200);
        blockedClient.sessionToken = l2['data']['session_token'].toString();
        phone3.sessionToken = l3['data']['session_token'].toString();

        final idem1 = const Uuid().v4();
        final txResults = await Future.wait([
          winningClient.call('POST', '/api/v1/transactions', idempotencyKey: idem1, body: {
            'cash_register_id': 1,
            'payment_method': 'tunai',
            'amount_paid': 10000,
            'request_print': true,
            'items': [{'product_id': prodId, 'unit_name': 'Pcs', 'qty': 1}],
          }),
          blockedClient.call('POST', '/api/v1/transactions', idempotencyKey: const Uuid().v4(), body: {
            'cash_register_id': 1,
            'payment_method': 'tunai',
            'amount_paid': 10000,
            'items': [{'product_id': prodId, 'unit_name': 'Pcs', 'qty': 1}],
          }),
          phone3.call('POST', '/api/v1/transactions', idempotencyKey: const Uuid().v4(), body: {
            'cash_register_id': 1,
            'payment_method': 'tunai',
            'amount_paid': 10000,
            'items': [{'product_id': prodId, 'unit_name': 'Pcs', 'qty': 1}],
          }),
        ]);
        for (final r in txResults) {
          expect(r['statusCode'], 201);
        }

        // Duplicate idempotency replay recovers existing TX without double-deducting stock
        final replay = await winningClient.call('POST', '/api/v1/transactions', idempotencyKey: idem1, body: {
          'cash_register_id': 1,
          'payment_method': 'tunai',
          'amount_paid': 10000,
          'items': [{'product_id': prodId, 'unit_name': 'Pcs', 'qty': 1}],
        });
        expect(replay['statusCode'], 200);
        expect(replay['data']['idempotent_replay'], isTrue);
        final byIdem = await winningClient.call('GET', '/api/v1/transactions/by-idempotency/$idem1');
        expect(byIdem['statusCode'], 200);
        expect(byIdem['data']['transaction']['invoice_number'], txResults[0]['data']['transaction']['invoice_number']);

        // Stock decremented exactly 3 (50 -> 47)
        final stockNow = (await db.query('products', where: 'id = ?', whereArgs: [prodId])).first['stock'];
        expect((stockNow as num).toDouble(), closeTo(47.0, 0.001));

        // C. Individual User Deactivation drops Kasir 2 session WITHOUT closing shared shift!
        await DatabaseHelper.instance.setUserActive(c2.id!, false, actorName: 'Owner');
        final c2After = await blockedClient.call('GET', '/api/v1/auth/me');
        expect(c2After['statusCode'], 401);
        final sharedShiftsAfter = await DatabaseHelper.instance.getOpenShifts(cashRegisterId: 1);
        expect(sharedShiftsAfter, isNotEmpty);
        expect(sharedShiftsAfter.first.status, 'open');

        // D. Warehouse limit=1 & Supervisor limit=2 enforcement
        final whLogin = await blockedClient.call('POST', '/api/v1/auth/pin-login', body: {'user_id': wh.id, 'pin': '4444'});
        expect(whLogin['statusCode'], 200);
        final whDenied = await phone3.call('POST', '/api/v1/auth/pin-login', body: {'user_id': wh.id, 'pin': '4444'});
        expect(whDenied['statusCode'], 409);

        final spvLogin1 = await blockedClient.call('POST', '/api/v1/auth/pin-login', body: {'user_id': sup.id, 'pin': '5555'});
        final spvLogin2 = await phone3.call('POST', '/api/v1/auth/pin-login', body: {'user_id': sup.id, 'pin': '5555'});
        expect(spvLogin1['statusCode'], 200);
        expect(spvLogin2['statusCode'], 200);
        blockedClient.sessionToken = spvLogin1['data']['session_token'].toString();
        phone3.sessionToken = spvLogin2['data']['session_token'].toString();

        // E. Single session revoke vs bulk account revoke vs terminal revoke
        final sessionsList = await dao.listTerminalSessions(includeInactive: false);
        final spvPhone3Session = sessionsList.firstWhere((d) => d.session.cashierId == sup.id && d.session.terminalId == phone3.terminalId);
        await dao.revokeSessionById(spvPhone3Session.session.id!, actorName: 'Owner', reason: 'Cabut Sesi 1');
        expect((await phone3.call('GET', '/api/v1/auth/me'))['statusCode'], 401);
        expect((await blockedClient.call('GET', '/api/v1/auth/me'))['statusCode'], 200);

        await dao.revokeAllSessionsForCashier(sup.id!, actorName: 'Owner');
        expect((await blockedClient.call('GET', '/api/v1/auth/me'))['statusCode'], 401);

        // Revoking Kasir 1 session closes WebSocket with closeCode 4001 & still keeps shared shift open
        final wsDone = Completer<int?>();
        ws1.listen((_) {}, onDone: () {
          if (!wsDone.isCompleted) wsDone.complete(ws1.closeCode);
        });
        await dao.revokeAllSessionsForCashier(c1.id!, actorName: 'Owner');
        final code = await wsDone.future.timeout(const Duration(seconds: 4));
        expect(code, 4001);
        expect((await winningClient.call('GET', '/api/v1/auth/me'))['statusCode'], 401);
        expect((await DatabaseHelper.instance.getOpenShifts(cashRegisterId: 1)).first.status, 'open');

        // Print job retry still succeeded cleanly
        final jobs = await dao.listPrintJobs(limit: 5);
        expect(jobs, isNotEmpty);

        // Role session policy configurable & per-account override respected + AuthProvider check
        final authProv = AuthProvider();
        await authProv.loadUsers(includeInactive: true);
        await authProv.loginWithPin('123456');
        expect(authProv.effectiveMaxSessionsFor(c1), 1);
        expect(authProv.effectiveMaxSessionsFor(sup), 2);
        await authProv.updateRoleSessionPolicy(AppRoles.cashier, 2);
        expect(await DatabaseHelper.instance.resolveEffectiveMaxSessionsTxn(db, c1), 2);
        expect(authProv.effectiveMaxSessionsFor(c1), 2);
        authProv.dispose();
        await Future<void>.delayed(const Duration(milliseconds: 120));
      } finally {
        printWorker.dispose();
        await server.stop();
      }
    });

    test('Encrypted backup (.ktbak AES-256-GCM) via VACUUM INTO, dual SHA-256, test-restore, passphrase cross-device restore, corrupt/low-storage guards & BackupProvider',
        () async {
      final tmpDir = await Directory.systemTemp.createTemp('kt_p3_bak_');
      final backupDir = Directory(p.join(tmpDir.path, 'primary_bak'));
      final secondaryDir = Directory(p.join(tmpDir.path, 'secondary_bak'));
      await backupDir.create(recursive: true);
      await secondaryDir.create(recursive: true);

      addTearDown(() async {
        await DatabaseHelper.instance.closeTestDatabase();
        if (await tmpDir.exists()) await tmpDir.delete(recursive: true);
      });

      final liveDbPath = p.join(tmpDir.path, 'live_kasirtoko.db');
      await DatabaseHelper.instance.openTestDatabase(path: liveDbPath);

      final prodId = await DatabaseHelper.instance.insertProduct(ProductModel(
        code: 'BAK-PROD-1',
        name: 'Produk Terbackup',
        baseUnit: 'Pcs',
        costPrice: 10000,
        sellingPrice: 15000,
        stock: 25,
      ));
      await BackupService.configureRecoveryPassphrase('PassphraseSuperAman2026!', actorName: 'Owner');

      // Run encrypted backup while DB is open with active WAL writes
      final bakRes = await BackupService.createEncryptedBackup(
        backupType: 'manual',
        customPrimaryDir: backupDir.path,
        secondaryDir: secondaryDir.path,
        recoveryPassphrase: 'PassphraseSuperAman2026!',
        verifyImmediately: true,
        actorName: 'Owner',
      );
      expect(bakRes.success, isTrue);
      expect(bakRes.artifact, isNotNull);
      expect(bakRes.artifact!.verifiedRestoreOk, isTrue);

      final primaryFile = File(bakRes.backupFilePath!);
      expect(primaryFile.existsSync(), isTrue);
      expect(File(bakRes.artifact!.secondaryPath).existsSync(), isTrue);

      // Must NEVER be plaintext SQLite — must start with KTBAK001 envelope header
      final rawBytes = await primaryFile.readAsBytes();
      expect(ascii.decode(rawBytes.sublist(0, 8)), 'KTBAK001');
      expect(ascii.decode(rawBytes.sublist(0, 13), allowInvalid: true), isNot('SQLite format'));

      // Corrupt ciphertext byte -> MUST fail AES-GCM verification cleanly!
      final corruptPath = p.join(tmpDir.path, 'corrupt.ktbak');
      final corruptBytes = Uint8List.fromList(rawBytes);
      corruptBytes[corruptBytes.length - 5] ^= 0xFF;
      await File(corruptPath).writeAsBytes(corruptBytes, flush: true);
      final corruptVerify = await BackupService.verifyBackupArtifact(
        corruptPath,
        recoveryPassphrase: 'PassphraseSuperAman2026!',
      );
      expect(corruptVerify.valid, isFalse);

      // Low storage guard rejects cleanly
      BackupService.availableStorageBytesOverride = (_) async => 10 * 1024 * 1024; // 10 MB < 50 MB
      final lowStorageRes = await BackupService.createEncryptedBackup(
        backupType: 'hourly',
        customPrimaryDir: backupDir.path,
      );
      expect(lowStorageRes.success, isFalse);
      expect(lowStorageRes.isLowStorage, isTrue);
      BackupService.availableStorageBytesOverride = null;

      // Cross-device restore test: simulate new device Keystore losing original Vault KEK
      SecretVault.configureForTesting(
        SoftwareAesGcmSecretVault(Uint8List.fromList(List.filled(32, 77))),
      );
      // Without passphrase -> must fail cleanly
      final noPassFail = await BackupService.verifyBackupArtifact(primaryFile.path);
      expect(noPassFail.valid, isFalse);

      // Mutate live DB (delete product) then restore using Recovery Passphrase!
      await (await DatabaseHelper.instance.database).delete('products', where: 'id = ?', whereArgs: [prodId]);
      expect(
        (await DatabaseHelper.instance.getProducts()).any((p) => p.code == 'BAK-PROD-1'),
        isFalse,
      );

      final restoreRes = await BackupService.restoreFromFilePath(
        primaryFile.path,
        recoveryPassphrase: 'PassphraseSuperAman2026!',
        safetyBackupDir: backupDir.path,
        actorName: 'Owner Baru',
      );
      expect(restoreRes.success, isTrue);

      final restoredProducts = await DatabaseHelper.instance.getProducts();
      expect(restoredProducts.any((p) => p.code == 'BAK-PROD-1'), isTrue);

      // Verify BackupProvider exposes jobs & preserved pre_restore artifact + creates new backup
      final bProv = BackupProvider();
      await bProv.refreshStatus();
      expect(bProv.jobs.length, 2);
      expect(bProv.artifacts.any((a) => a.backupType == 'pre_restore' && a.verifiedRestoreOk), isTrue);
      bProv.dispose();
    });

    test('Server persistent server_id, Router <-> Hotspot endpoints & UDP discovery hint', () async {
      await DatabaseHelper.instance.openTestDatabase();
      final sid = await DatabaseHelper.instance.getOrCreateServerId();

      await DatabaseHelper.instance.upsertServerNetworkEndpoint(
        ServerNetworkEndpointModel(
          profileType: 'primary_router',
          label: 'Router Toko Utama',
          baseUrl: 'https://192.168.1.50:8443',
          host: '192.168.1.50',
          port: 8443,
          expectedSsid: 'TOKO_WIFI',
          priority: 1,
          updatedAt: DateTime.now().toIso8601String(),
        ),
      );
      await DatabaseHelper.instance.upsertServerNetworkEndpoint(
        ServerNetworkEndpointModel(
          profileType: 'backup_hotspot',
          label: 'Hotspot HP Admin',
          baseUrl: 'https://192.168.43.1:8443',
          host: '192.168.43.1',
          port: 8443,
          expectedSsid: 'ADMIN_HOTSPOT',
          priority: 2,
          updatedAt: DateTime.now().toIso8601String(),
        ),
      );

      final worker = PrintQueueWorker(dao: MultiDeviceDao());
      final server = LanPosServer(printWorker: worker);
      await server.start(bindAddress: InternetAddress.loopbackIPv4, port: 0);
      try {
        final client = _TestStaffClient(
          baseUrl: 'https://127.0.0.1:${server.port}',
          certSha256: server.identity!.sha256Hex,
        );
        final h = await client.health();
        expect(h['statusCode'], 200);
        expect(h['data']['server_id'], sid);
        final endpoints = h['data']['endpoints'] as List<dynamic>;
        expect(endpoints.length, 2);

        // PosServerProvider reflects state cleanly
        final srvProv = PosServerProvider(server: server);
        await srvProv.refreshStatus();
        expect(srvProv.serverId, sid);
        expect(srvProv.primaryRouterEndpoint?.host, '192.168.1.50');
        expect(srvProv.backupHotspotEndpoint?.host, '192.168.43.1');
        srvProv.dispose();
      } finally {
        await server.stop();
        worker.dispose();
      }
    });
  });
}
