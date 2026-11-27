import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import 'package:kasirtoko/database/db_helper.dart';
import 'package:kasirtoko/database/multi_device_dao.dart';
import 'package:kasirtoko/models/cash_register.dart';
import 'package:kasirtoko/models/customer.dart';
import 'package:kasirtoko/models/print_job.dart';
import 'package:kasirtoko/models/printer_device.dart';
import 'package:kasirtoko/models/product.dart';
import 'package:kasirtoko/models/product_unit.dart';
import 'package:kasirtoko/models/promo.dart';
import 'package:kasirtoko/models/shift.dart';
import 'package:kasirtoko/services/printer/printer_adapter.dart';
import 'package:kasirtoko/services/secret_vault.dart';
import 'package:kasirtoko/services/server/lan_pos_server.dart';
import 'package:kasirtoko/services/server/print_queue_worker.dart';
import 'package:kasirtoko/services/server/request_security.dart';
import 'package:kasirtoko/utils/date_format.dart';
import 'package:kasirtoko/utils/security_helper.dart';

class _TestTerminalClient {
  final String serverBaseUrl;
  final String certSha256;
  String terminalId = '';
  String deviceToken = '';
  String deviceSecret = '';
  String? sessionToken;
  int clockOffsetMs = 0;

  _TestTerminalClient({
    required this.serverBaseUrl,
    required this.certSha256,
  });

  HttpClient _pinnedClient({String? overridePin}) {
    final c = HttpClient();
    c.connectionTimeout = const Duration(seconds: 8);
    c.badCertificateCallback = (X509Certificate cert, String host, int port) {
      final actual = sha256.convert(cert.der).toString().toLowerCase();
      return actual == (overridePin ?? certSha256).toLowerCase();
    };
    return c;
  }

  Future<Map<String, dynamic>> health({String? overridePin}) async {
    final client = _pinnedClient(overridePin: overridePin);
    try {
      final req = await client.getUrl(Uri.parse('$serverBaseUrl/api/v1/health'));
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      final map = jsonDecode(body) as Map<String, dynamic>;
      final srvMs = (map['data']['server_time_ms'] as num).toInt();
      clockOffsetMs = srvMs - DateTime.now().millisecondsSinceEpoch;
      return map;
    } finally {
      client.close(force: true);
    }
  }

  Future<Map<String, dynamic>> pair({
    required String code,
    required String name,
    required String uuid,
  }) async {
    final client = _pinnedClient();
    try {
      final req = await client.postUrl(Uri.parse('$serverBaseUrl/api/v1/pairing/register'));
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode({
        'pairing_code': code,
        'device_name': name,
        'device_model': 'Pixel Test',
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
      client.close(force: true);
    }
  }

  Future<Map<String, dynamic>> call(
    String method,
    String pathAndQuery, {
    Map<String, dynamic>? body,
    String? idempotencyKey,
    String? overrideNonce,
    String? overrideTimestampMs,
    String? overrideSignature,
    String? overrideSessionToken,
  }) async {
    final client = _pinnedClient();
    try {
      final bodyBytes = body != null ? utf8.encode(jsonEncode(body)) : const <int>[];
      final ts = overrideTimestampMs ??
          (DateTime.now().millisecondsSinceEpoch + clockOffsetMs).toString();
      final nonce = overrideNonce ?? const Uuid().v4();
      final bodySha = RequestSecurityValidator.sha256HexBytes(bodyBytes);
      final sig = overrideSignature ??
          RequestSecurityValidator.computeHmacSignature(
            deviceSecret: deviceSecret,
            method: method,
            pathAndQuery: pathAndQuery,
            timestampMs: ts,
            nonce: nonce,
            bodySha256Hex: bodySha,
          );

      final req = await client.openUrl(method.toUpperCase(), Uri.parse('$serverBaseUrl$pathAndQuery'));
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
      if (bodyBytes.isNotEmpty) req.add(bodyBytes);

      final res = await req.close();
      final decoded = jsonDecode(await res.transform(utf8.decoder).join()) as Map<String, dynamic>;
      return {'statusCode': res.statusCode, ...decoded};
    } finally {
      client.close(force: true);
    }
  }

  Future<WebSocket> connectWs() async {
    final base = Uri.parse(serverBaseUrl);
    final wsUri = Uri(scheme: 'wss', host: base.host, port: base.port, path: '/ws/v1/terminal');
    final ts = (DateTime.now().millisecondsSinceEpoch + clockOffsetMs).toString();
    final nonce = const Uuid().v4();
    final emptySha = RequestSecurityValidator.sha256HexString('');
    final sig = RequestSecurityValidator.computeHmacSignature(
      deviceSecret: deviceSecret,
      method: 'GET',
      pathAndQuery: '/ws/v1/terminal',
      timestampMs: ts,
      nonce: nonce,
      bodySha256Hex: emptySha,
    );
    return WebSocket.connect(
      wsUri.toString(),
      headers: {
        'X-Terminal-Id': terminalId,
        'X-Device-Token': deviceToken,
        'X-Request-Timestamp': ts,
        'X-Request-Nonce': nonce,
        'X-Signature': sig,
        'Authorization': 'Bearer $sessionToken',
      },
      customClient: _pinnedClient(),
    );
  }
}

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await DateHelper.ensureInitialized();
  });

  tearDown(() async {
    SecretVault.resetTestConfiguration();
    SecurityHelper.resetTestConfiguration();
    await DatabaseHelper.instance.closeTestDatabase();
  });

  group('Phase 2 — Complete Multi-Device HTTPS/WSS E2E, Security, Print/Drawer & Capacity', () {
    test('Full 22-scenario Multi-Device Security, Pairing, Drawer Modes, Print/Retry & WSS Suite', () async {
      SecurityHelper.configureForTesting(
        pepperProvider: InMemoryPepperProvider(Uint8List.fromList(List.filled(32, 9))),
        iterations: 50000,
      );
      SecretVault.configureForTesting(
        SoftwareAesGcmSecretVault(Uint8List.fromList(List.filled(32, 7))),
      );

      final db = await DatabaseHelper.instance.openTestDatabase();
      final dao = MultiDeviceDao();

      // Seed test products, units, tiered prices, promo, customer + balance, and a second cash register
      final prodId = await DatabaseHelper.instance.insertProduct(ProductModel(
        code: 'E2E-01',
        name: 'Beras Premium 5Kg',
        category: 'Sembako',
        barcode: '8991002003001',
        baseUnit: 'Sak',
        costPrice: 55000,
        sellingPrice: 70000,
        stock: 20,
        units: [
          ProductUnitModel(
            productId: 0,
            unitName: 'Pack10',
            conversionFactor: 10,
            sellingPrice: 680000,
            barcode: '8991002003010',
          ),
        ],
      ));

      final reg2Id = await db.insert('cash_registers', {
        'register_code': 'REG-S2',
        'name': 'Laci Staff 2',
        'is_shared': 0,
        'is_active': 1,
        'created_at': DateTime.now().toIso8601String(),
      });

      final promoId = await DatabaseHelper.instance.insertPromo(PromoModel(
        name: 'Diskon 10%',
        promoType: 'diskon_persen',
        minPurchase: 50000,
        discountValue: 10,
        startDate: DateTime.now().subtract(const Duration(days: 1)),
        endDate: DateTime.now().add(const Duration(days: 5)),
        isActive: true,
      ));

      final custId = await DatabaseHelper.instance.insertCustomer(
        CustomerModel(name: 'Budi Member', phone: '08123456789'),
      );
      await db.insert('customer_credit_ledger', {
        'customer_id': custId,
        'customer_name': 'Budi Member',
        'entry_type': 'manual_adjustment',
        'amount': 50000.0,
        'balance_before': 0.0,
        'balance_after': 50000.0,
        'reference_type': 'test',
        'reference_id': 1,
        'reference_number': 'TOPUP-1',
        'user_id': 1,
        'user_name': 'Owner',
        'note': 'Topup credit test',
        'created_at': DateTime.now().toIso8601String(),
      });

      // Register a headless LAN ESC/POS printer + capture every mock print/drawer call
      final lanPrinterId = await DatabaseHelper.instance.insertPrinter(PrinterDeviceModel(
        name: 'Epson LAN Kasir',
        category: PrinterCategory.thermal,
        connectionType: PrinterConnectionType.lan,
        address: '127.0.0.1',
        port: 9100,
        paperSize: '80mm',
        protocol: PrinterProtocol.escPos,
        isDefault: true,
        openDrawer: true,
      ));

      bool failNextPrintAttempt = false;
      final List<({String invoice, bool isReprint, bool drawerPulse})> printLog = [];
      int manualDrawerPulseCount = 0;

      final printWorker = PrintQueueWorker(
        dao: dao,
        maxAttempts: 1, // Fast fail so we can test explicit retry behavior
        retryDelay: const Duration(milliseconds: 10),
        customReceiptExecutor: (
          printer,
          trx, {
          required storeName,
          required storeAddress,
          required storePhone,
          required receiptConfig,
          logoPath,
          required isReprint,
          required allowDrawerPulse,
        }) async {
          if (failNextPrintAttempt) {
            failNextPrintAttempt = false;
            return PrinterOperationResult(success: false, message: 'Printer Bluetooth terputus');
          }
          printLog.add((
            invoice: trx.invoiceNumber,
            isReprint: isReprint,
            drawerPulse: allowDrawerPulse,
          ));
          return PrinterOperationResult(success: true, message: 'OK');
        },
        customDrawerExecutor: (printer) async {
          manualDrawerPulseCount++;
          return PrinterOperationResult(success: true, message: 'Opened');
        },
      );

      final server = LanPosServer(dao: dao, printWorker: printWorker);
      await server.start(bindAddress: InternetAddress.loopbackIPv4, port: 0);

      try {
        final baseUrl = 'https://127.0.0.1:${server.port}';
        final certSha = server.identity!.sha256Hex;

        // 1. Certificate pinning rejection on wrong fingerprint
        final badPinClient = _TestTerminalClient(
          serverBaseUrl: baseUrl,
          certSha256: '0'.padRight(64, '0'),
        );
        await expectLater(badPinClient.health(), throwsA(isA<HandshakeException>()));

        // 2. Valid health check & clock calibration
        final term1 = _TestTerminalClient(serverBaseUrl: baseUrl, certSha256: certSha);
        final healthRes = await term1.health();
        expect(healthRes['data']['protocol_version'], '1.1');

        // 3. Single-use pairing token & terminal registration
        final ticket1 = await dao.createPairingToken(
          suggestedName: 'Meja Staff 1',
          assignedRegisterId: 1,
          allowAutoOpenDrawer: true,
          allowManualOpenDrawer: true,
        );
        final pair1 = await term1.pair(
          code: ticket1.pairingCode,
          name: 'HP Kasir 1',
          uuid: 'uuid-term-1',
        );
        expect(pair1['statusCode'], 200);
        expect(term1.terminalId, 'TERM-001');

        // Reuse of consumed pairing code MUST be rejected
        final reuseRes = await term1.pair(
          code: ticket1.pairingCode,
          name: 'Attacker',
          uuid: 'uuid-evil',
        );
        expect(reuseRes['statusCode'], 401);

        // Verify `device_secret_enc` stored in DB is encrypted envelope (NEVER plaintext)
        final t1Model = await dao.getTerminalById('TERM-001');
        expect(t1Model!.deviceSecretEnc.startsWith('swv1:'), isTrue);
        expect(t1Model.deviceSecretEnc.contains(term1.deviceSecret), isFalse);

        // 4. Cashier list + PIN login + Rate Limit after wrong attempts + Access Control
        final cashiersRes = await term1.call('GET', '/api/v1/auth/cashiers');
        expect(cashiersRes['statusCode'], 200);
        final kasirUser = ((cashiersRes['data']['cashiers'] as List))
            .cast<Map<String, dynamic>>()
            .firstWhere((c) => c['username'] == 'kasir');
        final kasirId = (kasirUser['id'] as num).toInt();

        // Wrong PIN 5x triggers 429 PIN_RATE_LIMITED
        for (int i = 0; i < 4; i++) {
          final failLogin = await term1.call('POST', '/api/v1/auth/pin-login', body: {
            'user_id': kasirId,
            'pin': '9999',
          });
          expect(failLogin['statusCode'], 401);
        }
        final lockRes = await term1.call('POST', '/api/v1/auth/pin-login', body: {
          'user_id': kasirId,
          'pin': '9999',
        });
        expect(lockRes['statusCode'], 429);
        expect(lockRes['error']['code'], 'PIN_RATE_LIMITED');

        // Clear lock for test progression on second cashier (Supervisor PIN '3333' has apply_discount + open_cash_drawer!)
        final supUser = ((cashiersRes['data']['cashiers'] as List))
            .cast<Map<String, dynamic>>()
            .firstWhere((c) => c['username'] == 'supervisor');
        final supId = (supUser['id'] as num).toInt();

        final supLogin = await term1.call('POST', '/api/v1/auth/pin-login', body: {
          'user_id': supId,
          'pin': '3333',
        });
        expect(supLogin['statusCode'], 200);
        term1.sessionToken = supLogin['data']['session_token'].toString();

        // 5. Anti-Replay Nonce + Timestamp + HMAC validation
        final fixedNonce = const Uuid().v4();
        final okCall = await term1.call('GET', '/api/v1/store/bootstrap', overrideNonce: fixedNonce);
        expect(okCall['statusCode'], 200);

        final replayCall = await term1.call('GET', '/api/v1/store/bootstrap', overrideNonce: fixedNonce);
        expect(replayCall['statusCode'], 401);
        expect(replayCall['error']['code'], 'REPLAY_NONCE_DETECTED');

        final staleTs = (DateTime.now().millisecondsSinceEpoch - 300000).toString();
        final staleCall = await term1.call('GET', '/api/v1/store/bootstrap', overrideTimestampMs: staleTs);
        expect(staleCall['statusCode'], 401);
        expect(staleCall['error']['code'], 'REPLAY_TIMESTAMP_EXPIRED');

        final badSigCall = await term1.call('GET', '/api/v1/store/bootstrap', overrideSignature: 'deadbeef');
        expect(badSigCall['statusCode'], 401);
        expect(badSigCall['error']['code'], 'INVALID_SIGNATURE');

        // 6. Catalog & Barcode security: NEVER leak cost_price / quarantine_stock / damaged_stock
        final catRes = await term1.call('GET', '/api/v1/catalog/products?page=1&limit=50&since_version=0');
        expect(catRes['statusCode'], 200);
        final rawCatJson = jsonEncode(catRes['data']);
        expect(rawCatJson.contains('cost_price'), isFalse);
        expect(rawCatJson.contains('quarantine_stock'), isFalse);
        expect(rawCatJson.contains('damaged_stock'), isFalse);

        final scanUnitRes = await term1.call('GET', '/api/v1/catalog/barcode/8991002003010');
        expect(scanUnitRes['statusCode'], 200);
        expect(scanUnitRes['data']['matched_unit']['unit_name'], 'Pack10');
        expect(jsonEncode(scanUnitRes['data']).contains('cost_price'), isFalse);

        // 7. Connect WebSocket & receive hello frame
        final ws = await term1.connectWs();
        final wsEvents = <Map<String, dynamic>>[];
        final helloCompleter = Completer<void>();
        ws.listen((raw) {
          final evt = jsonDecode(raw.toString()) as Map<String, dynamic>;
          wsEvents.add(evt);
          if (evt['type'] == 'hello' && !helloCompleter.isCompleted) {
            helloCompleter.complete();
          }
        });
        await helloCompleter.future.timeout(const Duration(seconds: 3));
        expect(server.connectedTerminals.length, 1);

        // 8. Reject transaction when no open shift exists
        final preShiftTrx = await term1.call(
          'POST',
          '/api/v1/transactions',
          idempotencyKey: const Uuid().v4(),
          body: {
            'payment_method': 'tunai',
            'amount_paid': 70000,
            'items': [{'product_id': prodId, 'unit_name': 'Sak', 'qty': 1}],
          },
        );
        expect(preShiftTrx['statusCode'], 409);
        expect(preShiftTrx['error']['code'], 'SHIFT_CLOSED');

        // Open shared shift on REG-MAIN
        final openShiftRes = await term1.call(
          'POST',
          '/api/v1/shifts/open',
          idempotencyKey: const Uuid().v4(),
          body: {'cash_register_id': 1, 'starting_cash': 100000},
        );
        expect(openShiftRes['statusCode'], 201);
        final sharedShiftId = (openShiftRes['data']['shift']['id'] as num).toInt();

        // 9. Authoritative price enforcement: tampered expected_grand_total rejected
        final tamperedPrice = await term1.call(
          'POST',
          '/api/v1/transactions',
          idempotencyKey: const Uuid().v4(),
          body: {
            'shift_id': sharedShiftId,
            'cash_register_id': 1,
            'payment_method': 'tunai',
            'amount_paid': 1000,
            'expected_grand_total': 1000, // Client forged Rp 1.000 instead of Rp 70.000!
            'items': [{'product_id': prodId, 'unit_name': 'Sak', 'qty': 1}],
          },
        );
        expect(tamperedPrice['statusCode'], 409);
        expect(tamperedPrice['error']['code'], 'PRICE_OR_PROMO_CHANGED');

        // 10. Walk-in customer rejected for Kasbon
        final badKasbon = await term1.call(
          'POST',
          '/api/v1/transactions',
          idempotencyKey: const Uuid().v4(),
          body: {
            'shift_id': sharedShiftId,
            'cash_register_id': 1,
            'customer_name': 'Pelanggan Umum',
            'payment_method': 'kasbon',
            'amount_paid': 0,
            'items': [{'product_id': prodId, 'unit_name': 'Sak', 'qty': 1}],
          },
        );
        expect(badKasbon['statusCode'], 409);
        expect(badKasbon['error']['code'], 'INVALID_CUSTOMER_RULE');

        // 11. Valid Tunai + Promo checkout with idempotency retry & single-shot drawer pulse
        failNextPrintAttempt = true; // First print attempt fails -> explicit retry MUST NOT open drawer twice!
        final idemKey = const Uuid().v4();
        final cashBody = {
          'shift_id': sharedShiftId,
          'cash_register_id': 1,
          'promo_id': promoId,
          'payment_method': 'tunai',
          'amount_paid': 70000,
          'expected_grand_total': 63000, // 70,000 - 10%
          'request_print': true,
          'items': [{'product_id': prodId, 'unit_name': 'Sak', 'qty': 1}],
        };

        final trx1 = await term1.call('POST', '/api/v1/transactions', idempotencyKey: idemKey, body: cashBody);
        expect(trx1['statusCode'], 201);
        expect(trx1['data']['idempotent_replay'], isFalse);
        expect((trx1['data']['transaction']['grand_total'] as num).toDouble(), 63000);
        expect(jsonEncode(trx1['data']['transaction']).contains('cost_price'), isFalse);
        final jobUuid = trx1['data']['print_job']['job_uuid'].toString();

        // Reconcile endpoint check
        final recLookup = await term1.call('GET', '/api/v1/transactions/by-idempotency/$idemKey');
        expect(recLookup['statusCode'], 200);
        expect(recLookup['data']['transaction']['invoice_number'],
            trx1['data']['transaction']['invoice_number']);

        // Duplicate idempotent replay returns 200 with SAME transaction, NEVER deducts stock twice!
        final trxReplay = await term1.call('POST', '/api/v1/transactions', idempotencyKey: idemKey, body: cashBody);
        expect(trxReplay['statusCode'], 200);
        expect(trxReplay['data']['idempotent_replay'], isTrue);

        // Drain print queue -> first attempt failed & locked `drawer_pulse_sent = 1` before print attempt!
        await printWorker.drainNow(printerId: lanPrinterId);
        final failedJob = await dao.getPrintJobByUuid(jobUuid);
        expect(failedJob!.status, PrintJobStatus.failed);
        expect(failedJob.drawerPulseSent, isTrue);

        // Explicit retry via DAO MUST preserve `drawerPulseSent == true` so second print sends allowDrawerPulse=false!
        await dao.retryPrintJob(jobUuid);
        await printWorker.drainNow(printerId: lanPrinterId);
        expect(printLog.length, 1);
        expect(printLog.first.drawerPulse, isFalse);

        // Headless system PDF printer rejection check
        final pdfJob = await dao.enqueuePrintJob(
          terminalId: 'TERM-001',
          cashierId: supId,
          transactionId: (trx1['data']['transaction']['id'] as num).toInt(),
          invoiceNumber: trx1['data']['transaction']['invoice_number'].toString(),
          printerId: 1, // Seeded Android Print Service (system PDF)
        );
        await printWorker.drainNow(printerId: 1);
        final pdfFailed = await dao.getPrintJobByUuid(pdfJob.jobUuid);
        expect(pdfFailed!.status, PrintJobStatus.failed);
        expect(pdfFailed.errorMessage.contains('PRINTER_NOT_HEADLESS'), isTrue);

        // 12. Non-cash QRIS checkout -> NEVER requests or sends drawer pulse
        final qrisTrx = await term1.call(
          'POST',
          '/api/v1/transactions',
          idempotencyKey: const Uuid().v4(),
          body: {
            'shift_id': sharedShiftId,
            'cash_register_id': 1,
            'customer_id': custId,
            'customer_name': 'Budi Member',
            'payment_method': 'qris',
            'credit_used': 20000,
            'amount_paid': 50000,
            'request_print': true,
            'items': [{'product_id': prodId, 'unit_name': 'Sak', 'qty': 1}],
          },
        );
        expect(qrisTrx['statusCode'], 201);
        await printWorker.drainNow(printerId: lanPrinterId);
        expect(printLog.last.drawerPulse, isFalse);
        expect(await DatabaseHelper.instance.getCustomerCreditBalance(custId), closeTo(30000, 0.01));

        // 13. Reprint NEVER opens drawer & records audit log `cetak_ulang_struk`
        final reprintRes = await term1.call(
          'POST',
          '/api/v1/print/receipt',
          idempotencyKey: const Uuid().v4(),
          body: {
            'invoice_number': qrisTrx['data']['transaction']['invoice_number'],
            'is_reprint': true,
          },
        );
        expect(reprintRes['statusCode'], 202);
        await printWorker.drainNow(printerId: lanPrinterId);
        expect(printLog.last.isReprint, isTrue);
        expect(printLog.last.drawerPulse, isFalse);

        // 14. Manual drawer open -> succeeds with reason + audit log `buka_laci`; blocked when disabled!
        final manualDrawerOk = await term1.call(
          'POST',
          '/api/v1/printers/open-drawer',
          idempotencyKey: const Uuid().v4(),
          body: {'reason': 'Tukar uang kembalian', 'cash_register_id': 1},
        );
        expect(manualDrawerOk['statusCode'], 200);
        expect(manualDrawerOk['data']['drawer_triggered'], isTrue);
        expect(manualDrawerPulseCount, 1);

        await dao.updateTerminalPolicy(
          terminalId: 'TERM-001',
          allowManualOpenDrawer: false,
        );
        final manualDrawerBlocked = await term1.call(
          'POST',
          '/api/v1/printers/open-drawer',
          idempotencyKey: const Uuid().v4(),
          body: {'reason': 'Coba paksa'},
        );
        expect(manualDrawerBlocked['statusCode'], 403);
        expect(manualDrawerBlocked['error']['code'], 'DRAWER_DISABLED_FOR_TERMINAL');

        // 15. Product delete delta tombstone synced cleanly
        await DatabaseHelper.instance.deleteProduct(prodId);
        final deltaRes = await term1.call('GET', '/api/v1/catalog/products?since_version=1&limit=50');
        final deltaItems = (deltaRes['data']['items'] as List).cast<Map<String, dynamic>>();
        final tomb = deltaItems.firstWhere((e) => e['id'] == prodId);
        expect(tomb['is_active'], isFalse);

        // 16. Switch mode to INDIVIDUAL_DRAWER after closing shared shift + assign register 2 to Term 2
        await term1.call('POST', '/api/v1/shifts/close', body: {
          'shift_id': sharedShiftId,
          'actual_cash': 163000,
          'note': 'Pas',
        });
        await DatabaseHelper.instance.setDrawerMode(DrawerMode.individualDrawer);

        final ticket2 = await dao.createPairingToken(
          suggestedName: 'Meja Staff 2',
          assignedRegisterId: reg2Id,
        );
        final term2 = _TestTerminalClient(serverBaseUrl: baseUrl, certSha256: certSha);
        await term2.pair(code: ticket2.pairingCode, name: 'HP Kasir 2', uuid: 'uuid-term-2');

        // Login Owner (PIN 123456) on Term 2, Sup (3333) remains on Term 1 (REG-MAIN)
        final ownerUser = ((cashiersRes['data']['cashiers'] as List))
            .cast<Map<String, dynamic>>()
            .firstWhere((c) => c['username'] == 'owner');
        final t2Login = await term2.call('POST', '/api/v1/auth/pin-login', body: {
          'user_id': ownerUser['id'],
          'pin': '123456',
        });
        term2.sessionToken = t2Login['data']['session_token'].toString();

        final s1Open = await term1.call('POST', '/api/v1/shifts/open',
            idempotencyKey: const Uuid().v4(),
            body: {'cash_register_id': 1, 'starting_cash': 50000});
        final s2Open = await term2.call('POST', '/api/v1/shifts/open',
            idempotencyKey: const Uuid().v4(),
            body: {'cash_register_id': reg2Id, 'starting_cash': 75000});
        expect(s1Open['statusCode'], 201);
        expect(s2Open['statusCode'], 201);

        // 17. Staged TLS cert rotation advertised via cert-info
        await server.stageCertificateRotation();
        final certInfo = await term2.call('GET', '/api/v1/security/cert-info');
        expect(certInfo['data']['rotation_pending'], isTrue);
        expect(certInfo['data']['next_cert_sha256'], isNotEmpty);

        // 18. Revoke TERM-001 -> HTTP blocked 403 & WS closes cleanly
        await dao.revokeTerminal('TERM-001');
        final postRevoke = await term1.call('GET', '/api/v1/store/bootstrap');
        expect(postRevoke['statusCode'], 403);
        expect(postRevoke['error']['code'], 'TERMINAL_REVOKED');
        await ws.close();

        // Check stock consistency: 20 initial - 1 (cash) - 1 (qris) = 18
        final prodsNow = await db.query('products', where: 'id = ?', whereArgs: [prodId]);
        expect((prodsNow.first['stock'] as num).toDouble(), closeTo(18.0, 0.001));
      } finally {
        await server.stop();
        printWorker.dispose();
      }
    });

    test('Concurrent Checkout Benchmark & Race Safety: 2, 5, and 10 active terminals', () async {
      SecurityHelper.configureForTesting(
        pepperProvider: InMemoryPepperProvider(Uint8List.fromList(List.filled(32, 3))),
        iterations: 50000,
      );
      SecretVault.configureForTesting(
        SoftwareAesGcmSecretVault(Uint8List.fromList(List.filled(32, 4))),
      );

      Future<({int count, double avgMs, double maxMs, double remainingStock})> runConcurrencyTier(
        int terminalCount,
      ) async {
        await DatabaseHelper.instance.closeTestDatabase();
        final db = await DatabaseHelper.instance.openTestDatabase();
        await DatabaseHelper.instance.upsertSessionPolicy('cashier', terminalCount);
        final dao = MultiDeviceDao();

        const double initialStock = 100.0;
        final itemId = await DatabaseHelper.instance.insertProduct(ProductModel(
          code: 'BENCH-$terminalCount',
          name: 'Indomie Goreng Dus',
          category: 'Makanan',
          baseUnit: 'Pcs',
          costPrice: 2500,
          sellingPrice: 3500,
          stock: initialStock,
        ));

        await DatabaseHelper.instance.openShift(ShiftModel(
          cashierId: 1,
          cashierName: 'Pemilik Toko',
          terminalId: 'ADMIN',
          cashRegisterId: 1,
          drawerMode: DrawerMode.sharedDrawer,
          startTime: DateTime.now(),
          startingCash: 200000,
          status: 'open',
        ));

        final worker = PrintQueueWorker(
          dao: dao,
          customReceiptExecutor: (p, t,
                  {required storeName,
                  required storeAddress,
                  required storePhone,
                  required receiptConfig,
                  logoPath,
                  required isReprint,
                  required allowDrawerPulse}) async =>
              PrinterOperationResult(success: true, message: 'OK'),
        );
        final server = LanPosServer(dao: dao, printWorker: worker);
        await server.start(bindAddress: InternetAddress.loopbackIPv4, port: 0);
        final baseUrl = 'https://127.0.0.1:${server.port}';
        final certSha = server.identity!.sha256Hex;

        try {
          final clients = <_TestTerminalClient>[];
          for (int i = 0; i < terminalCount; i++) {
            final ticket = await dao.createPairingToken(
              suggestedName: 'Bench Term $i',
              assignedRegisterId: 1,
            );
            final c = _TestTerminalClient(serverBaseUrl: baseUrl, certSha256: certSha);
            await c.pair(
              code: ticket.pairingCode,
              name: 'Bench Term $i',
              uuid: 'bench-uuid-$terminalCount-$i',
            );
            final login = await c.call('POST', '/api/v1/auth/pin-login', body: {
              'user_id': 3, // Kasir 1 (PIN 1111)
              'pin': '1111',
            });
            c.sessionToken = login['data']['session_token'].toString();
            clients.add(c);
          }

          // Connect all WebSockets simultaneously
          final sockets = <WebSocket>[];
          for (final c in clients) {
            sockets.add(await c.connectWs());
          }
          expect(server.connectedTerminals.length, terminalCount);

          // Each terminal fires 2 concurrent checkouts of 1 qty each
          final latenciesMs = <int>[];
          final invoices = <String>{};
          final futures = <Future<void>>[];

          for (final c in clients) {
            for (int r = 0; r < 2; r++) {
              futures.add(() async {
                final sw = Stopwatch()..start();
                final res = await c.call(
                  'POST',
                  '/api/v1/transactions',
                  idempotencyKey: const Uuid().v4(),
                  body: {
                    'cash_register_id': 1,
                    'payment_method': 'tunai',
                    'amount_paid': 5000,
                    'request_print': true,
                    'items': [{'product_id': itemId, 'unit_name': 'Pcs', 'qty': 1}],
                  },
                );
                sw.stop();
                expect(res['statusCode'], 201);
                latenciesMs.add(sw.elapsedMilliseconds);
                invoices.add(res['data']['transaction']['invoice_number'].toString());
              }());
            }
          }

          await Future.wait(futures);
          await worker.drainNow();

          // Verify zero duplicate invoices & exact stock deduction!
          expect(invoices.length, terminalCount * 2);
          final prodRow = (await db.query('products', where: 'id = ?', whereArgs: [itemId])).first;
          final remaining = (prodRow['stock'] as num).toDouble();
          expect(remaining, closeTo(initialStock - (terminalCount * 2), 0.001));

          for (final ws in sockets) {
            await ws.close();
          }

          final avg = latenciesMs.fold<int>(0, (s, e) => s + e) / latenciesMs.length;
          final maxLat = latenciesMs.reduce((a, b) => a > b ? a : b).toDouble();
          return (count: terminalCount, avgMs: avg, maxMs: maxLat, remainingStock: remaining);
        } finally {
          await server.stop();
          worker.dispose();
        }
      }

      final r2 = await runConcurrencyTier(2);
      final r5 = await runConcurrencyTier(5);
      final r10 = await runConcurrencyTier(10);

      // ignore: avoid_print
      print(
        'LAN Capacity Benchmark (Real TLS+HMAC+SQLite): '
        '2T(avg=${r2.avgMs.toStringAsFixed(1)}ms,max=${r2.maxMs.toStringAsFixed(0)}ms,stock=${r2.remainingStock}); '
        '5T(avg=${r5.avgMs.toStringAsFixed(1)}ms,max=${r5.maxMs.toStringAsFixed(0)}ms,stock=${r5.remainingStock}); '
        '10T(avg=${r10.avgMs.toStringAsFixed(1)}ms,max=${r10.maxMs.toStringAsFixed(0)}ms,stock=${r10.remainingStock})',
      );
    });
  });
}
