import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../database/db_helper.dart';
import '../../database/multi_device_dao.dart';
import '../../models/cash_register.dart';
import '../../models/customer.dart';
import '../../models/paired_terminal.dart';
import '../../models/print_job.dart';
import '../../models/printer_device.dart';
import '../../models/receipt_config.dart';
import '../../models/shift.dart';
import '../../models/user.dart';
import '../../utils/security_helper.dart';
import 'authoritative_checkout_service.dart';
import 'print_queue_worker.dart';
import 'request_security.dart';
import 'tls_certificate_manager.dart';

class ConnectedTerminalSnapshot {
  final String terminalId;
  final String terminalName;
  final int? cashierId;
  final String cashierName;
  final DateTime connectedAt;
  final DateTime lastSeenAt;

  const ConnectedTerminalSnapshot({
    required this.terminalId,
    required this.terminalName,
    this.cashierId,
    this.cashierName = '',
    required this.connectedAt,
    required this.lastSeenAt,
  });
}

class _ConnectedWsClient {
  final WebSocket socket;
  final String terminalId;
  final String terminalName;
  int? cashierId;
  String cashierName;
  final DateTime connectedAt;
  DateTime lastSeenAt;

  _ConnectedWsClient({
    required this.socket,
    required this.terminalId,
    required this.terminalName,
    this.cashierId,
    this.cashierName = '',
    required this.connectedAt,
    required this.lastSeenAt,
  });
}

class _AuthenticatedDeviceContext {
  final PairedTerminalModel terminal;
  final String deviceSecret;

  const _AuthenticatedDeviceContext({
    required this.terminal,
    required this.deviceSecret,
  });
}

class LanPosServer {
  static const String protocolVersion = '1.1';
  static const int maxRequestBodyBytes = 512 * 1024;
  static const int heartbeatIntervalSeconds = 4;

  final DatabaseHelper _dbHelper;
  final MultiDeviceDao _dao;
  final TlsCertificateManager _certManager;
  final RequestSecurityValidator _securityValidator;
  final AuthoritativeCheckoutService _checkoutService;
  final PrintQueueWorker _printWorker;
  final String serverId;
  final String appVersion;
  final void Function()? onConnectionsChanged;

  HttpServer? _server;
  TlsServerIdentity? _identity;
  int _boundPort = 0;
  final Map<String, _ConnectedWsClient> _wsClients = {};
  DateTime? _startedAt;

  LanPosServer({
    DatabaseHelper? dbHelper,
    MultiDeviceDao? dao,
    TlsCertificateManager? certManager,
    RequestSecurityValidator? securityValidator,
    AuthoritativeCheckoutService? checkoutService,
    PrintQueueWorker? printWorker,
    this.serverId = 'KASIRTOKO-ADMIN-1',
    this.appVersion = '1.1.0',
    this.onConnectionsChanged,
  })  : _dbHelper = dbHelper ?? DatabaseHelper.instance,
        _dao = dao ?? MultiDeviceDao(dbHelper: dbHelper),
        _certManager = certManager ?? TlsCertificateManager(),
        _securityValidator = securityValidator ?? RequestSecurityValidator(),
        _checkoutService = checkoutService ??
            AuthoritativeCheckoutService(dbHelper: dbHelper, dao: dao),
        _printWorker = printWorker ?? PrintQueueWorker(dbHelper: dbHelper, dao: dao);

  bool get isRunning => _server != null;
  int get port => _boundPort;
  TlsServerIdentity? get identity => _identity;
  DateTime? get startedAt => _startedAt;
  PrintQueueWorker get printWorker => _printWorker;
  AuthoritativeCheckoutService get checkoutService => _checkoutService;

  List<ConnectedTerminalSnapshot> get connectedTerminals => _wsClients.values
      .map((c) => ConnectedTerminalSnapshot(
            terminalId: c.terminalId,
            terminalName: c.terminalName,
            cashierId: c.cashierId,
            cashierName: c.cashierName,
            connectedAt: c.connectedAt,
            lastSeenAt: c.lastSeenAt,
          ))
      .toList();

  Future<void> start({
    InternetAddress? bindAddress,
    int port = 8443,
    List<String> extraIpAddresses = const [],
  }) async {
    if (_server != null) return;
    final storeName = await _dbHelper.getSetting('store_name', defaultValue: 'KasirToko POS');
    _identity = await _certManager.getOrCreateIdentity(
      commonName: storeName,
      extraIpAddresses: extraIpAddresses,
    );

    final ctx = _identity!.toSecurityContext();
    _server = await HttpServer.bindSecure(
      bindAddress ?? InternetAddress.anyIPv4,
      port,
      ctx,
      shared: true,
    );
    _boundPort = _server!.port;
    _startedAt = DateTime.now();

    _dbHelper.onMultiDeviceEvent = _handleDomainEvent;

    _server!.listen(
      (req) {
        unawaited(_handleRequest(req));
      },
      onError: (_) {},
      cancelOnError: false,
    );

    _printWorker.scheduleDrain();
  }

  Future<void> stop() async {
    final srv = _server;
    _server = null;
    _boundPort = 0;
    _startedAt = null;
    if (_dbHelper.onMultiDeviceEvent == _handleDomainEvent) {
      _dbHelper.onMultiDeviceEvent = null;
    }

    if (_wsClients.isNotEmpty) {
      await _broadcastWs('server_stopping', {
        'reason': 'Server POS Admin dimatikan.',
      });
      for (final c in List<_ConnectedWsClient>.from(_wsClients.values)) {
        try {
          await c.socket.close(1001, 'Server stopping');
        } catch (_) {}
      }
      _wsClients.clear();
      onConnectionsChanged?.call();
    }

    try {
      await srv?.close(force: true);
    } catch (_) {}
  }

  Future<TlsServerIdentity> stageCertificateRotation({
    List<String> extraIpAddresses = const [],
  }) async {
    final storeName = await _dbHelper.getSetting('store_name', defaultValue: 'KasirToko POS');
    final next = await _certManager.stageRotation(
      commonName: storeName,
      extraIpAddresses: extraIpAddresses,
    );
    _identity = next;
    await _broadcastWs('settings_changed', {
      'cert_rotation_pending': true,
      'next_cert_sha256': next.nextSha256Hex,
    });
    return next;
  }

  void _handleDomainEvent(String eventType, Map<String, dynamic> data) {
    if (!isRunning) return;
    if (eventType == 'terminal_revoked') {
      final tid = (data['terminal_id'] ?? '').toString();
      unawaited(_sendAndCloseTerminal(tid, eventType, data, closeCode: 4003));
      return;
    }
    if (eventType == 'session_revoked') {
      final cashierId = (data['cashier_id'] as num?)?.toInt();
      if (cashierId != null) {
        for (final client in _wsClients.values.where((c) => c.cashierId == cashierId)) {
          _sendWsFrame(client.socket, eventType, data);
        }
      }
      return;
    }
    unawaited(_broadcastWs(eventType, data));
  }

  Future<void> _sendAndCloseTerminal(
    String terminalId,
    String eventType,
    Map<String, dynamic> data, {
    int closeCode = 4003,
  }) async {
    final matching = _wsClients.entries.where((e) => e.value.terminalId == terminalId).toList();
    for (final entry in matching) {
      _sendWsFrame(entry.value.socket, eventType, data);
      try {
        await entry.value.socket.close(closeCode, 'Terminal revoked');
      } catch (_) {}
      _wsClients.remove(entry.key);
    }
    if (matching.isNotEmpty) onConnectionsChanged?.call();
  }

  Future<void> _broadcastWs(String type, Map<String, dynamic> data) async {
    if (_wsClients.isEmpty) return;
    final syncVer = await _dao.getCatalogSyncVersion();
    final deadKeys = <String>[];
    for (final entry in _wsClients.entries) {
      final ok = _sendWsFrame(entry.value.socket, type, {
        ...data,
        'sync_version': syncVer,
      });
      if (!ok) deadKeys.add(entry.key);
    }
    for (final k in deadKeys) {
      _wsClients.remove(k);
    }
    if (deadKeys.isNotEmpty) onConnectionsChanged?.call();
  }

  bool _sendWsFrame(WebSocket socket, String type, Map<String, dynamic> data) {
    try {
      socket.add(jsonEncode({
        'type': type,
        'server_time_ms': DateTime.now().millisecondsSinceEpoch,
        'data': data,
      }));
      return true;
    } catch (_) {
      return false;
    }
  }

  // ==================== HTTP / WS ROUTING & SECURITY ====================

  Future<void> _handleRequest(HttpRequest req) async {
    try {
      final apiVer = req.headers.value('X-API-Version');
      if (apiVer != null && apiVer.isNotEmpty && !apiVer.startsWith('1.')) {
        await _sendError(
          req,
          426,
          'UNSUPPORTED_API_VERSION',
          'Versi API $apiVer tidak didukung server (harapkan 1.x).',
        );
        return;
      }

      if (req.uri.path == '/ws/v1/terminal') {
        await _handleWsUpgrade(req);
        return;
      }

      final rawBodyBytes = await _readBodyWithLimit(req);
      if (rawBodyBytes == null) {
        await _sendError(req, 413, 'PAYLOAD_TOO_LARGE', 'Ukuran payload melebihi batas 512 KB.');
        return;
      }
      final bodyText = utf8.decode(rawBodyBytes);
      final bodySha256 = RequestSecurityValidator.sha256HexBytes(rawBodyBytes);
      final path = req.uri.path;
      final method = req.method.toUpperCase();

      // 1. Public LAN Discovery & Pairing Exchange
      if (method == 'GET' && path == '/api/v1/health') {
        await _handleHealth(req);
        return;
      }
      if (method == 'POST' && path == '/api/v1/pairing/register') {
        await _handlePairingRegister(req, bodyText);
        return;
      }

      // 2. Device + HMAC + Anti-Replay Middleware
      final deviceCtx = await _authenticateDevice(req, bodySha256);
      if (deviceCtx == null) return; // Error response already sent

      // Un-authenticated-cashier device endpoints
      if (method == 'POST' && path == '/api/v1/pairing/verify') {
        await _handlePairingVerify(req, deviceCtx.terminal);
        return;
      }
      if (method == 'POST' && path == '/api/v1/pairing/rotate-secret') {
        await _handleRotateSecret(req, deviceCtx.terminal);
        return;
      }
      if (method == 'GET' && path == '/api/v1/security/cert-info') {
        await _handleCertInfo(req);
        return;
      }
      if (method == 'POST' && path == '/api/v1/pairing/unpair') {
        await _dao.revokeTerminal(deviceCtx.terminal.terminalId, actorName: 'Staff Unpair');
        await _sendOk(req, {'unpaired': true});
        return;
      }
      if (method == 'GET' && path == '/api/v1/auth/cashiers') {
        await _handleAuthCashiers(req);
        return;
      }
      if (method == 'POST' && path == '/api/v1/auth/pin-login') {
        await _handlePinLogin(req, deviceCtx.terminal, bodyText);
        return;
      }

      // 3. Cashier Session Middleware (Device + Session + HMAC)
      final sessionCtx = await _authenticateSession(req, deviceCtx.terminal);
      if (sessionCtx == null) return; // Error already sent

      if (method == 'POST' && path == '/api/v1/auth/pin-logout') {
        final rawBearer = _extractBearer(req);
        if (rawBearer != null) await _dao.revokeSessionByRawToken(rawBearer);
        await _sendOk(req, {'logged_out': true});
        return;
      }
      if (method == 'GET' && path == '/api/v1/auth/me') {
        await _handleAuthMe(req, deviceCtx.terminal, sessionCtx);
        return;
      }
      if (method == 'GET' && path == '/api/v1/store/bootstrap') {
        await _handleStoreBootstrap(req, deviceCtx.terminal);
        return;
      }
      if (method == 'GET' && path == '/api/v1/cash-registers') {
        await _handleListCashRegisters(req, deviceCtx.terminal, sessionCtx.cashier);
        return;
      }
      if (method == 'GET' && path == '/api/v1/shifts/current') {
        await _handleGetCurrentShift(req, deviceCtx.terminal, sessionCtx.cashier);
        return;
      }
      if (method == 'POST' && path == '/api/v1/shifts/open') {
        await _handleOpenShift(req, deviceCtx.terminal, sessionCtx.cashier, bodyText);
        return;
      }
      if (method == 'POST' && path == '/api/v1/shifts/close') {
        await _handleCloseShift(req, deviceCtx.terminal, sessionCtx.cashier, bodyText);
        return;
      }
      if (method == 'GET' && path == '/api/v1/catalog/products') {
        await _handleCatalogProducts(req);
        return;
      }
      if (method == 'GET' && path.startsWith('/api/v1/catalog/barcode/')) {
        final code = Uri.decodeComponent(path.substring('/api/v1/catalog/barcode/'.length));
        await _handleBarcodeLookup(req, code);
        return;
      }
      if (method == 'GET' && path == '/api/v1/catalog/promos') {
        final promos = await _dao.getActivePromosPublic();
        await _sendOk(req, {'promos': promos});
        return;
      }
      if (method == 'GET' && path == '/api/v1/customers') {
        await _handleListCustomers(req);
        return;
      }
      if (method == 'POST' && path == '/api/v1/customers') {
        await _handleCreateCustomer(req, sessionCtx.cashier, bodyText);
        return;
      }
      if (method == 'GET' &&
          path.startsWith('/api/v1/customers/') &&
          path.endsWith('/credit-balance')) {
        await _handleCustomerCreditBalance(req, path);
        return;
      }
      if (method == 'POST' && path == '/api/v1/transactions') {
        await _handleCreateTransaction(req, deviceCtx.terminal, sessionCtx.cashier, bodyText);
        return;
      }
      if (method == 'GET' && path.startsWith('/api/v1/transactions/by-idempotency/')) {
        final key = Uri.decodeComponent(path.substring('/api/v1/transactions/by-idempotency/'.length));
        await _handleGetByIdempotency(req, key);
        return;
      }
      if (method == 'GET' && path == '/api/v1/transactions') {
        await _handleListTerminalTransactions(req, deviceCtx.terminal);
        return;
      }
      if (method == 'GET' && path == '/api/v1/printers/status') {
        await _handlePrinterStatus(req, deviceCtx.terminal, sessionCtx.cashier);
        return;
      }
      if (method == 'POST' && path == '/api/v1/print/receipt') {
        await _handlePrintReceipt(req, deviceCtx.terminal, sessionCtx.cashier, bodyText);
        return;
      }
      if (method == 'GET' && path.startsWith('/api/v1/print/jobs/')) {
        final jobId = Uri.decodeComponent(path.substring('/api/v1/print/jobs/'.length));
        await _handleGetPrintJob(req, jobId);
        return;
      }
      if (method == 'POST' && path == '/api/v1/printers/open-drawer') {
        await _handleOpenDrawerManual(req, deviceCtx.terminal, sessionCtx.cashier, bodyText);
        return;
      }

      await _sendError(req, 404, 'NOT_FOUND', 'Endpoint $method $path tidak ditemukan.');
    } catch (e) {
      try {
        await _sendError(req, 500, 'INTERNAL_ERROR', 'Kesalahan server internal.');
      } catch (_) {}
    }
  }

  Future<List<int>?> _readBodyWithLimit(HttpRequest req) async {
    final chunks = <int>[];
    await for (final chunk in req) {
      chunks.addAll(chunk);
      if (chunks.length > maxRequestBodyBytes) {
        return null;
      }
    }
    return chunks;
  }

  Future<_AuthenticatedDeviceContext?> _authenticateDevice(
    HttpRequest req,
    String bodySha256Hex,
  ) async {
    final terminalId = (req.headers.value('X-Terminal-Id') ?? '').trim();
    final deviceToken = (req.headers.value('X-Device-Token') ?? '').trim();
    final tsHeader = req.headers.value('X-Request-Timestamp') ?? '';
    final nonceHeader = req.headers.value('X-Request-Nonce') ?? '';
    final sigHeader = req.headers.value('X-Signature') ?? '';

    if (terminalId.isEmpty || deviceToken.isEmpty) {
      await _sendError(req, 401, 'UNAUTHORIZED_DEVICE', 'Kredensial terminal tidak lengkap.');
      return null;
    }
    if (!_securityValidator.allowRateLimit(terminalId)) {
      await _sendError(req, 429, 'RATE_LIMITED', 'Terlalu banyak permintaan dari terminal ini.');
      return null;
    }

    final terminal = await _dao.getTerminalById(terminalId);
    if (terminal == null) {
      await _sendError(req, 401, 'UNAUTHORIZED_DEVICE', 'Terminal tidak terdaftar.');
      return null;
    }
    if (terminal.isRevoked) {
      await _sendError(req, 403, 'TERMINAL_REVOKED', 'Akses terminal telah dicabut Admin.');
      return null;
    }

    final tokenDigest = MultiDeviceDao.sha256Hex(deviceToken);
    if (!SecurityHelper.constantTimeEquals(terminal.deviceTokenHash, tokenDigest)) {
      await _sendError(req, 401, 'UNAUTHORIZED_DEVICE', 'Device token terminal tidak valid.');
      return null;
    }

    final replay = _securityValidator.validateTimestampAndNonce(
      terminalId: terminalId,
      timestampHeader: tsHeader,
      nonceHeader: nonceHeader,
    );
    if (!replay.valid) {
      await _sendError(req, 401, replay.errorCode, replay.message);
      return null;
    }

    final deviceSecret = await _dao.unwrapTerminalSecret(terminal);
    if (deviceSecret == null || deviceSecret.isEmpty) {
      await _sendError(req, 401, 'UNAUTHORIZED_DEVICE', 'Secret terminal tidak tersedia.');
      return null;
    }

    final pathAndQuery = req.uri.hasQuery ? '${req.uri.path}?${req.uri.query}' : req.uri.path;
    final sigOk = RequestSecurityValidator.verifyHmacSignature(
      deviceSecret: deviceSecret,
      method: req.method,
      pathAndQuery: pathAndQuery,
      timestampMs: tsHeader,
      nonce: nonceHeader,
      bodySha256Hex: bodySha256Hex,
      providedSignature: sigHeader,
    );
    if (!sigOk) {
      await _sendError(req, 401, 'INVALID_SIGNATURE', 'Tanda tangan HMAC request tidak valid.');
      return null;
    }

    unawaited(_dao.touchTerminalLastSeen(terminal.terminalId));
    return _AuthenticatedDeviceContext(terminal: terminal, deviceSecret: deviceSecret);
  }

  Future<ValidatedSession?> _authenticateSession(
    HttpRequest req,
    PairedTerminalModel terminal,
  ) async {
    final token = _extractBearer(req);
    if (token == null || token.isEmpty) {
      await _sendError(req, 401, 'UNAUTHORIZED_SESSION', 'Token sesi kasir diperlukan.');
      return null;
    }
    final res = await _dao.validateSession(
      rawSessionToken: token,
      terminalId: terminal.terminalId,
    );
    if (res.failure != null) {
      await _sendError(req, 401, res.failure!.errorCode, res.failure!.message);
      return null;
    }
    return res.ok;
  }

  String? _extractBearer(HttpRequest req) {
    final auth = (req.headers.value(HttpHeaders.authorizationHeader) ?? '').trim();
    if (auth.toLowerCase().startsWith('bearer ')) {
      return auth.substring(7).trim();
    }
    return null;
  }

  // ==================== WEBSOCKET HANDLER ====================

  Future<void> _handleWsUpgrade(HttpRequest req) async {
    final emptyBodySha = RequestSecurityValidator.sha256HexString('');
    final deviceCtx = await _authenticateDevice(req, emptyBodySha);
    if (deviceCtx == null) return;
    final sessionCtx = await _authenticateSession(req, deviceCtx.terminal);
    if (sessionCtx == null) return;

    final socket = await WebSocketTransformer.upgrade(req);
    final connKey = '${deviceCtx.terminal.terminalId}#${DateTime.now().microsecondsSinceEpoch}';
    final client = _ConnectedWsClient(
      socket: socket,
      terminalId: deviceCtx.terminal.terminalId,
      terminalName: deviceCtx.terminal.terminalName,
      cashierId: sessionCtx.cashier.id,
      cashierName: sessionCtx.cashier.name,
      connectedAt: DateTime.now(),
      lastSeenAt: DateTime.now(),
    );
    _wsClients[connKey] = client;
    onConnectionsChanged?.call();

    // Immediate hello frame for delta catch-up
    final settings = await _dbHelper.getAllSettings();
    final syncVer = await _dao.getCatalogSyncVersion();
    final shift = await _dbHelper.getCurrentOpenShift(
      cashierId: sessionCtx.cashier.id,
      terminalId: deviceCtx.terminal.terminalId,
    );
    _sendWsFrame(socket, 'hello', {
      'protocol_version': protocolVersion,
      'sync_version': syncVer,
      'drawer_mode': DrawerMode.normalize(settings['drawer_mode']),
      'heartbeat_interval_sec': heartbeatIntervalSeconds,
      'current_shift': shift != null ? _shiftToJson(shift) : null,
    });

    socket.listen(
      (rawMsg) async {
        client.lastSeenAt = DateTime.now();
        try {
          final decoded = jsonDecode(rawMsg.toString());
          if (decoded is Map && decoded['type'] == 'ping') {
            final curSync = await _dao.getCatalogSyncVersion();
            final curSettings = await _dbHelper.getAllSettings();
            final curShift = await _dbHelper.getCurrentOpenShift(
              cashierId: client.cashierId,
              terminalId: client.terminalId,
            );
            _sendWsFrame(socket, 'pong', {
              'ts': decoded['ts'],
              'sync_version': curSync,
              'drawer_mode': DrawerMode.normalize(curSettings['drawer_mode']),
              'shift_open': curShift?.isOpen ?? false,
            });
          }
        } catch (_) {}
      },
      onDone: () {
        _wsClients.remove(connKey);
        onConnectionsChanged?.call();
      },
      onError: (_) {
        _wsClients.remove(connKey);
        onConnectionsChanged?.call();
      },
      cancelOnError: true,
    );
  }

  // ==================== HANDLERS ====================

  Future<void> _handleHealth(HttpRequest req) async {
    final settings = await _dbHelper.getAllSettings();
    final now = DateTime.now();
    await _sendOk(req, {
      'status': 'ok',
      'server_id': serverId,
      'app_version': appVersion,
      'protocol_version': protocolVersion,
      'store_name': settings['store_name'] ?? 'KasirToko',
      'drawer_mode': DrawerMode.normalize(settings['drawer_mode']),
      'cert_pin_short': _identity?.shortPin ?? '',
      'server_time': now.toIso8601String(),
      'server_time_ms': now.millisecondsSinceEpoch,
    });
  }

  Future<void> _handlePairingRegister(HttpRequest req, String bodyText) async {
    final json = _tryDecodeMap(bodyText);
    if (json == null) {
      await _sendError(req, 400, 'VALIDATION_ERROR', 'Body JSON pairing tidak valid.');
      return;
    }
    try {
      final res = await _dao.completePairing(
        pairingCode: (json['pairing_code'] ?? '').toString(),
        terminalName: (json['device_name'] ?? json['terminal_name'] ?? 'HP Kasir').toString(),
        deviceModel: (json['device_model'] ?? '').toString(),
        deviceUuid: (json['device_uuid'] ?? '').toString(),
      );
      final settings = await _dbHelper.getAllSettings();
      await _sendOk(req, {
        'terminal_id': res.terminal.terminalId,
        'terminal_code': res.terminal.terminalCode,
        'terminal_name': res.terminal.terminalName,
        'device_token': res.deviceToken,
        'device_secret': res.deviceSecret,
        'store_name': settings['store_name'] ?? 'KasirToko',
        'drawer_mode': DrawerMode.normalize(settings['drawer_mode']),
        'assigned_cash_register_id': res.terminal.assignedRegisterId,
        'assigned_register': res.assignedRegister?.toMap(),
        'allow_auto_open_drawer': res.terminal.allowAutoOpenDrawer,
        'allow_manual_open_drawer': res.terminal.allowManualOpenDrawer,
        'heartbeat_interval_sec': heartbeatIntervalSeconds,
        'cert_sha256': _identity?.sha256Hex ?? '',
      });
    } on StateError catch (e) {
      await _sendError(req, 401, 'PAIRING_FAILED', e.message);
    }
  }

  Future<void> _handlePairingVerify(HttpRequest req, PairedTerminalModel t) async {
    final settings = await _dbHelper.getAllSettings();
    await _sendOk(req, {
      'verified': true,
      'terminal': t.toPublicJson(),
      'drawer_mode': DrawerMode.normalize(settings['drawer_mode']),
      'cert_rotation_pending': _identity?.nextSha256Hex != null,
      'next_cert_sha256': _identity?.nextSha256Hex,
    });
  }

  Future<void> _handleRotateSecret(HttpRequest req, PairedTerminalModel t) async {
    final rotated = await _dao.rotateTerminalCredentials(
      t.terminalId,
      actorName: 'Self-Rotation ${t.terminalId}',
    );
    await _sendOk(req, rotated);
  }

  Future<void> _handleCertInfo(HttpRequest req) async {
    await _sendOk(req, {
      'current_cert_sha256': _identity?.sha256Hex ?? '',
      'short_pin': _identity?.shortPin ?? '',
      'created_at': _identity?.createdAt ?? '',
      'expires_at': _identity?.expiresAt ?? '',
      'next_cert_sha256': _identity?.nextSha256Hex,
      'rotation_pending': _identity?.nextSha256Hex != null,
    });
  }

  Future<void> _handleAuthCashiers(HttpRequest req) async {
    final users = await _dbHelper.getUsers();
    final cashiers = users
        .where((u) => u.isActive && u.hasPermission(AppPermissions.accessPos))
        .map((u) => {
              'id': u.id,
              'name': u.name,
              'username': u.username,
              'role': u.role,
              'role_label': AppRoles.displayName(u.role),
            })
        .toList();
    await _sendOk(req, {'cashiers': cashiers});
  }

  Future<void> _handlePinLogin(
    HttpRequest req,
    PairedTerminalModel terminal,
    String bodyText,
  ) async {
    final json = _tryDecodeMap(bodyText);
    if (json == null) {
      await _sendError(req, 400, 'VALIDATION_ERROR', 'Body JSON login tidak valid.');
      return;
    }
    final userId = (json['user_id'] as num?)?.toInt();
    final pin = (json['pin'] ?? '').toString().trim();
    if (userId == null || pin.isEmpty) {
      await _sendError(req, 400, 'VALIDATION_ERROR', 'user_id dan pin wajib diisi.');
      return;
    }

    final attempt = await _dbHelper.authenticateWithPin(
      pin,
      userId: userId,
      terminalId: terminal.terminalId,
    );
    if (attempt.status == AuthAttemptStatus.lockedOut) {
      await _sendError(
        req,
        429,
        'PIN_RATE_LIMITED',
        attempt.message,
        details: {'retry_after_seconds': attempt.retryAfterSeconds},
      );
      return;
    }
    if (attempt.status == AuthAttemptStatus.inactive) {
      await _sendError(req, 403, 'CASHIER_INACTIVE', attempt.message);
      return;
    }
    if (!attempt.isSuccess || attempt.user == null) {
      await _sendError(req, 401, 'INVALID_CREDENTIALS', attempt.message);
      return;
    }

    final cashier = attempt.user!;
    if (!cashier.hasPermission(AppPermissions.accessPos)) {
      await _sendError(
        req,
        403,
        'PERMISSION_DENIED',
        'Akun "${cashier.name}" tidak memiliki hak akses Kasir (POS).',
      );
      return;
    }

    final shift = await _dbHelper.getCurrentOpenShift(
      cashierId: cashier.id,
      terminalId: terminal.terminalId,
    );
    final issued = await _dao.issueSession(
      terminalId: terminal.terminalId,
      cashier: cashier,
      shiftId: shift?.id,
    );
    final settings = await _dbHelper.getAllSettings();

    await _sendOk(req, {
      'session_token': issued['session_token'],
      'expires_at': issued['expires_at'],
      'issued_at': issued['issued_at'],
      'cashier': _cashierToSafeJson(cashier),
      'drawer_mode': DrawerMode.normalize(settings['drawer_mode']),
      'terminal': terminal.toPublicJson(),
      'current_shift': shift != null ? _shiftToJson(shift) : null,
    });
  }

  Future<void> _handleAuthMe(
    HttpRequest req,
    PairedTerminalModel terminal,
    ValidatedSession session,
  ) async {
    final settings = await _dbHelper.getAllSettings();
    final shift = await _dbHelper.getCurrentOpenShift(
      cashierId: session.cashier.id,
      terminalId: terminal.terminalId,
    );
    await _sendOk(req, {
      'cashier': _cashierToSafeJson(session.cashier),
      'expires_at': session.session.expiresAt,
      'terminal': terminal.toPublicJson(),
      'drawer_mode': DrawerMode.normalize(settings['drawer_mode']),
      'current_shift': shift != null ? _shiftToJson(shift) : null,
    });
  }

  Future<void> _handleStoreBootstrap(
    HttpRequest req,
    PairedTerminalModel terminal,
  ) async {
    final settings = await _dbHelper.getAllSettings();
    final rawRc = settings['receipt_config_json'] ?? '';
    final rc = rawRc.isNotEmpty
        ? ReceiptConfigModel.fromJson(rawRc)
        : ReceiptConfigModel(
            paperSize: settings['printer_paper_size'] ?? '58mm',
            footerText: settings['receipt_footer'] ?? 'Terima kasih!',
          );
    await _sendOk(req, {
      'store_name': settings['store_name'] ?? 'KasirToko',
      'store_address': settings['store_address'] ?? '',
      'store_phone': settings['store_phone'] ?? '',
      'business_type': settings['business_type'] ?? 'general',
      'currency_symbol': settings['currency_symbol'] ?? 'Rp ',
      'tax_enabled': (settings['tax_enabled'] ?? '0') == '1',
      'tax_rate': double.tryParse(settings['tax_rate'] ?? '0') ?? 0.0,
      'drawer_mode': DrawerMode.normalize(settings['drawer_mode']),
      'receipt_config': rc.toMap(),
      'allow_auto_open_drawer': terminal.allowAutoOpenDrawer,
      'allow_manual_open_drawer': terminal.allowManualOpenDrawer,
      'auto_print_staff_transactions':
          (settings['auto_print_staff_transactions'] ?? '1') == '1',
      'heartbeat_interval_sec': heartbeatIntervalSeconds,
    });
  }

  Future<void> _handleListCashRegisters(
    HttpRequest req,
    PairedTerminalModel terminal,
    UserModel cashier,
  ) async {
    final registers = await _dbHelper.getCashRegisters(includeInactive: false);
    final openShifts = await _dbHelper.getOpenShifts();
    CashRegisterModel? authorized;
    try {
      authorized = await _dbHelper.resolveAuthorizedCashRegister(
        cashierId: cashier.id!,
        terminalId: terminal.terminalId,
      );
    } catch (_) {}

    final list = registers.map((r) {
      ShiftModel? openOnReg;
      for (final s in openShifts) {
        if (s.cashRegisterId == r.id) {
          openOnReg = s;
          break;
        }
      }
      return {
        'id': r.id,
        'register_code': r.registerCode,
        'name': r.name,
        'printer_id': r.printerId,
        'is_shared': r.isShared,
        'is_authorized': authorized?.id == r.id,
        'open_shift': openOnReg != null ? _shiftToJson(openOnReg) : null,
      };
    }).toList();
    await _sendOk(req, {
      'authorized_register_id': authorized?.id,
      'cash_registers': list,
    });
  }

  Future<void> _handleGetCurrentShift(
    HttpRequest req,
    PairedTerminalModel terminal,
    UserModel cashier,
  ) async {
    final settings = await _dbHelper.getAllSettings();
    final mode = DrawerMode.normalize(settings['drawer_mode']);
    CashRegisterModel? authorized;
    try {
      authorized = await _dbHelper.resolveAuthorizedCashRegister(
        cashierId: cashier.id!,
        terminalId: terminal.terminalId,
      );
    } catch (_) {}

    final shift = await _dbHelper.getCurrentOpenShift(
      cashierId: cashier.id,
      terminalId: terminal.terminalId,
      cashRegisterId: authorized?.id,
    );
    await _sendOk(req, {
      'drawer_mode': mode,
      'is_open': shift?.isOpen ?? false,
      'cash_register': authorized == null
          ? null
          : {
              'id': authorized.id,
              'register_code': authorized.registerCode,
              'name': authorized.name,
              'is_shared': authorized.isShared,
            },
      'shift': shift != null ? _shiftToJson(shift) : null,
    });
  }

  Future<void> _handleOpenShift(
    HttpRequest req,
    PairedTerminalModel terminal,
    UserModel cashier,
    String bodyText,
  ) async {
    final json = _tryDecodeMap(bodyText);
    if (json == null) {
      await _sendError(req, 400, 'VALIDATION_ERROR', 'Body JSON shift tidak valid.');
      return;
    }
    final startingCash = (json['starting_cash'] as num?)?.toDouble() ?? -1;
    final reqRegId = (json['cash_register_id'] as num?)?.toInt();
    if (startingCash < 0) {
      await _sendError(req, 400, 'VALIDATION_ERROR', 'Modal awal shift tidak boleh negatif.');
      return;
    }

    try {
      final reg = await _dbHelper.resolveAuthorizedCashRegister(
        cashierId: cashier.id!,
        terminalId: terminal.terminalId,
        requestedRegisterId: reqRegId,
      );
      final mode = DrawerMode.normalize(
        await _dbHelper.getSetting('drawer_mode', defaultValue: DrawerMode.sharedDrawer),
      );
      final newShift = ShiftModel(
        cashierId: cashier.id!,
        cashierName: cashier.name,
        terminalId: terminal.terminalId,
        cashRegisterId: reg.id ?? 1,
        drawerMode: mode,
        startTime: DateTime.now(),
        startingCash: startingCash,
        status: 'open',
      );
      final shiftId = await _dbHelper.openShift(newShift);
      final opened = await _dbHelper.getCurrentOpenShift(
        cashierId: cashier.id,
        terminalId: terminal.terminalId,
        cashRegisterId: reg.id,
      );
      unawaited(_broadcastWs('shift_changed', {
        'shift_id': shiftId,
        'status': 'open',
        'cash_register_id': reg.id,
        'cashier_id': cashier.id,
      }));
      await _sendOk(req, {
        'shift': opened != null ? _shiftToJson(opened) : {'id': shiftId},
        'cash_register': {
          'id': reg.id,
          'register_code': reg.registerCode,
          'name': reg.name,
        },
      }, statusCode: 201);
    } on StateError catch (e) {
      await _sendError(req, 409, 'SHIFT_CONFLICT', e.message);
    }
  }

  Future<void> _handleCloseShift(
    HttpRequest req,
    PairedTerminalModel terminal,
    UserModel cashier,
    String bodyText,
  ) async {
    final json = _tryDecodeMap(bodyText);
    if (json == null) {
      await _sendError(req, 400, 'VALIDATION_ERROR', 'Body JSON tutup shift tidak valid.');
      return;
    }
    final shiftId = (json['shift_id'] as num?)?.toInt();
    final actualCash = (json['actual_cash'] as num?)?.toDouble();
    final note = (json['note'] ?? '').toString();
    if (shiftId == null || actualCash == null || actualCash < 0) {
      await _sendError(req, 400, 'VALIDATION_ERROR', 'shift_id dan actual_cash (>= 0) wajib diisi.');
      return;
    }

    final openShifts = await _dbHelper.getOpenShifts();
    ShiftModel? target;
    for (final s in openShifts) {
      if (s.id == shiftId) {
        target = s;
        break;
      }
    }
    if (target == null) {
      await _sendError(req, 404, 'NOT_FOUND', 'Shift aktif #$shiftId tidak ditemukan.');
      return;
    }
    if (target.drawerMode == DrawerMode.individualDrawer &&
        target.cashierId != cashier.id &&
        !cashier.isOwnerOrAdmin) {
      await _sendError(
        req,
        403,
        'PERMISSION_DENIED',
        'Tidak boleh menutup shift individu milik kasir lain.',
      );
      return;
    }

    try {
      await _dbHelper.closeShift(
        shiftId,
        actualCash,
        actualCash - target.expectedCash,
        note,
      );
      await _sendOk(req, {
        'closed': true,
        'shift_id': shiftId,
        'expected_cash': target.expectedCash,
        'actual_cash': actualCash,
        'difference': actualCash - target.expectedCash,
      });
    } on StateError catch (e) {
      await _sendError(req, 409, 'SHIFT_CLOSE_ERROR', e.message);
    }
  }

  Future<void> _handleCatalogProducts(HttpRequest req) async {
    final qp = req.uri.queryParameters;
    final page = int.tryParse(qp['page'] ?? '1') ?? 1;
    final limit = int.tryParse(qp['limit'] ?? '150') ?? 150;
    final sinceVersion = int.tryParse(qp['since_version'] ?? '0') ?? 0;

    final result = await _dao.getCatalogProductsPage(
      sinceVersion: sinceVersion,
      page: page,
      pageSize: limit,
    );
    await _sendOk(req, {
      'items': result['items'],
      'pagination': {
        'page': result['page'],
        'limit': result['page_size'],
        'total': result['total'],
        'has_more': result['has_more'],
      },
      'sync_version': result['sync_version'],
    });
  }

  Future<void> _handleBarcodeLookup(HttpRequest req, String code) async {
    final res = await _dao.lookupByBarcodePublic(code);
    if (res == null) {
      await _sendError(req, 404, 'NOT_FOUND', 'Barcode "$code" tidak ditemukan.');
      return;
    }
    await _sendOk(req, res);
  }

  Future<void> _handleListCustomers(HttpRequest req) async {
    final q = req.uri.queryParameters['query'];
    final page = int.tryParse(req.uri.queryParameters['page'] ?? '1') ?? 1;
    final limit = int.tryParse(req.uri.queryParameters['limit'] ?? '100') ?? 100;
    final all = await _dao.listCustomersSafe(query: q);
    final safePage = page < 1 ? 1 : page;
    final safeLimit = limit.clamp(1, 200);
    final start = (safePage - 1) * safeLimit;
    final paged = start >= all.length
        ? <Map<String, dynamic>>[]
        : all.sublist(start, (start + safeLimit).clamp(0, all.length));
    await _sendOk(req, {
      'customers': paged,
      'pagination': {
        'page': safePage,
        'limit': safeLimit,
        'total': all.length,
        'has_more': (start + paged.length) < all.length,
      },
    });
  }

  Future<void> _handleCreateCustomer(
    HttpRequest req,
    UserModel cashier,
    String bodyText,
  ) async {
    if (!cashier.hasPermission(AppPermissions.manageCustomers)) {
      await _sendError(
        req,
        403,
        'PERMISSION_DENIED',
        'Akun Anda tidak memiliki izin menambah pelanggan.',
      );
      return;
    }
    final json = _tryDecodeMap(bodyText);
    if (json == null || (json['name'] ?? '').toString().trim().isEmpty) {
      await _sendError(req, 400, 'VALIDATION_ERROR', 'Nama pelanggan wajib diisi.');
      return;
    }
    final cust = CustomerModel(
      name: (json['name'] ?? '').toString().trim(),
      phone: (json['phone'] ?? '').toString().trim(),
      address: (json['address'] ?? '').toString().trim(),
      email: (json['email'] ?? '').toString().trim(),
      notes: (json['notes'] ?? '').toString().trim(),
    );
    final id = await _dbHelper.insertCustomer(cust);
    final created = await _dao.getCustomerDetailSafe(id);
    await _sendOk(req, {'customer': created}, statusCode: 201);
  }

  Future<void> _handleCustomerCreditBalance(HttpRequest req, String path) async {
    final trimmed = path.substring('/api/v1/customers/'.length);
    final idPart = trimmed.split('/').first;
    final id = int.tryParse(idPart);
    if (id == null) {
      await _sendError(req, 400, 'VALIDATION_ERROR', 'ID pelanggan tidak valid.');
      return;
    }
    final detail = await _dao.getCustomerDetailSafe(id);
    if (detail == null) {
      await _sendError(req, 404, 'NOT_FOUND', 'Pelanggan tidak ditemukan.');
      return;
    }
    await _sendOk(req, detail);
  }

  Future<void> _handleCreateTransaction(
    HttpRequest req,
    PairedTerminalModel terminal,
    UserModel cashier,
    String bodyText,
  ) async {
    final json = _tryDecodeMap(bodyText);
    if (json == null) {
      await _sendError(req, 400, 'VALIDATION_ERROR', 'Payload JSON transaksi tidak valid.');
      return;
    }
    final headerKey = (req.headers.value('X-Idempotency-Key') ?? '').trim();
    final bodyKey = (json['idempotency_key'] ?? '').toString().trim();
    final idemKey = headerKey.isNotEmpty ? headerKey : bodyKey;

    try {
      final result = await _checkoutService.executeStaffCheckout(
        terminal: terminal,
        cashier: cashier,
        idempotencyKey: idemKey,
        payload: json,
      );
      if (result.printJob != null && !result.idempotentReplay) {
        _printWorker.scheduleDrain(printerId: result.printJob!.printerId);
      }
      await _sendOk(
        req,
        {
          'idempotent_replay': result.idempotentReplay,
          'transaction': _dao.transactionToPublicReceiptJson(result.transaction),
          'print_job': result.printJob?.toApiJson(),
        },
        statusCode: result.idempotentReplay ? 200 : 201,
      );
    } on CheckoutDomainException catch (e) {
      await _sendError(req, e.httpStatus, e.errorCode, e.message, details: e.details);
    }
  }

  Future<void> _handleGetByIdempotency(HttpRequest req, String key) async {
    final trx = await _dao.getTransactionByIdempotencyKey(key);
    if (trx == null) {
      await _sendError(
        req,
        404,
        'NOT_FOUND',
        'Transaksi untuk idempotency_key tersebut belum tercatat di Admin.',
      );
      return;
    }
    await _sendOk(req, {
      'found': true,
      'transaction': _dao.transactionToPublicReceiptJson(trx),
    });
  }

  Future<void> _handleListTerminalTransactions(
    HttpRequest req,
    PairedTerminalModel terminal,
  ) async {
    final page = int.tryParse(req.uri.queryParameters['page'] ?? '1') ?? 1;
    final limit = int.tryParse(req.uri.queryParameters['limit'] ?? '30') ?? 30;
    final all = await _dao.listTerminalTransactions(terminal.terminalId, limit: 100);
    final safePage = page < 1 ? 1 : page;
    final safeLimit = limit.clamp(1, 50);
    final start = (safePage - 1) * safeLimit;
    final paged = start >= all.length
        ? <Map<String, dynamic>>[]
        : all
            .sublist(start, (start + safeLimit).clamp(0, all.length))
            .map(_dao.transactionToPublicReceiptJson)
            .toList();
    await _sendOk(req, {
      'transactions': paged,
      'pagination': {
        'page': safePage,
        'limit': safeLimit,
        'total': all.length,
        'has_more': (start + paged.length) < all.length,
      },
    });
  }

  Future<void> _handlePrinterStatus(
    HttpRequest req,
    PairedTerminalModel terminal,
    UserModel cashier,
  ) async {
    final printers = await _dbHelper.getPrinters();
    PrinterDeviceModel? selected;
    if (terminal.defaultPrinterId != null) {
      for (final p in printers) {
        if (p.id == terminal.defaultPrinterId) {
          selected = p;
          break;
        }
      }
    }
    selected ??= printers.where((p) => p.isDefault).firstOrNull ?? printers.firstOrNull;
    final isSystemOnly = selected == null ||
        selected.connectionType == PrinterConnectionType.system ||
        selected.protocol == PrinterProtocol.pdf;

    await _sendOk(req, {
      'printer': selected == null
          ? null
          : {
              'id': selected.id,
              'name': selected.name,
              'category': selected.category,
              'connection_type': selected.connectionType,
              'paper_size': selected.paperSize,
              'protocol': selected.protocol,
              'open_drawer_hardware': selected.openDrawer,
            },
      'headless_supported': !isSystemOnly,
      'allow_auto_open_drawer': terminal.allowAutoOpenDrawer,
      'allow_manual_open_drawer':
          terminal.allowManualOpenDrawer && cashier.hasPermission(AppPermissions.openCashDrawer),
      'has_open_drawer_permission': cashier.hasPermission(AppPermissions.openCashDrawer),
    });
  }

  Future<void> _handlePrintReceipt(
    HttpRequest req,
    PairedTerminalModel terminal,
    UserModel cashier,
    String bodyText,
  ) async {
    final json = _tryDecodeMap(bodyText);
    if (json == null) {
      await _sendError(req, 400, 'VALIDATION_ERROR', 'Body JSON cetak struk tidak valid.');
      return;
    }
    final invoice = (json['invoice_number'] ?? '').toString().trim();
    final isReprint = json['is_reprint'] != false;
    final headerKey = (req.headers.value('X-Idempotency-Key') ?? '').trim();
    if (invoice.isEmpty) {
      await _sendError(req, 400, 'VALIDATION_ERROR', 'invoice_number wajib diisi.');
      return;
    }
    final trx = await _dbHelper.getTransactionByInvoice(invoice);
    if (trx == null) {
      await _sendError(req, 404, 'NOT_FOUND', 'Nota $invoice tidak ditemukan.');
      return;
    }

    // Hard rule: reprint NEVER sends drawer pulse!
    final canPulse = !isReprint &&
        trx.paymentMethod == 'tunai' &&
        terminal.allowAutoOpenDrawer;
    final job = await _dao.enqueuePrintJob(
      terminalId: terminal.terminalId,
      cashierId: cashier.id,
      transactionId: trx.id,
      invoiceNumber: trx.invoiceNumber,
      printerId: terminal.defaultPrinterId,
      jobType: isReprint ? PrintJobType.reprint : PrintJobType.receipt,
      isReprint: isReprint,
      openDrawerRequested: canPulse,
      idempotencyKey: headerKey.isNotEmpty ? headerKey : null,
    );

    if (isReprint) {
      final db = await _dbHelper.database;
      await db.insert('audit_logs', {
        'timestamp': DateTime.now().toIso8601String(),
        'user_id': cashier.id ?? 0,
        'user_name': cashier.name,
        'user_role': cashier.role,
        'action_type': 'cetak_ulang_struk',
        'module': 'Printer & Struk',
        'object_id': trx.invoiceNumber,
        'before_value': '',
        'after_value': 'terminal=${terminal.terminalId}, job=${job.jobUuid}',
        'details':
            'Cetak ulang struk ${trx.invoiceNumber} dari ${terminal.terminalName} oleh ${cashier.name} (laci terkunci).',
      });
    }

    _printWorker.scheduleDrain(printerId: job.printerId);
    await _sendOk(req, {'print_job': job.toApiJson()}, statusCode: 202);
  }

  Future<void> _handleGetPrintJob(HttpRequest req, String jobUuid) async {
    final job = await _dao.getPrintJobByUuid(jobUuid);
    if (job == null) {
      await _sendError(req, 404, 'NOT_FOUND', 'Print job tidak ditemukan.');
      return;
    }
    await _sendOk(req, {'print_job': job.toApiJson()});
  }

  Future<void> _handleOpenDrawerManual(
    HttpRequest req,
    PairedTerminalModel terminal,
    UserModel cashier,
    String bodyText,
  ) async {
    if (!terminal.allowManualOpenDrawer) {
      await _sendError(
        req,
        403,
        'DRAWER_DISABLED_FOR_TERMINAL',
        'Buka laci manual dinonaktifkan Admin untuk terminal ${terminal.terminalName}.',
      );
      return;
    }
    if (!cashier.hasPermission(AppPermissions.openCashDrawer)) {
      await _sendError(
        req,
        403,
        'PERMISSION_DENIED',
        'Akun "${cashier.name}" tidak memiliki izin buka laci kasir manual.',
      );
      return;
    }
    final json = _tryDecodeMap(bodyText);
    final reason = (json?['reason'] ?? '').toString().trim();
    if (reason.isEmpty) {
      await _sendError(
        req,
        400,
        'VALIDATION_ERROR',
        'Alasan pembukaan laci manual wajib diisi untuk log audit.',
      );
      return;
    }

    final reqRegId = (json?['cash_register_id'] as num?)?.toInt();
    late final CashRegisterModel authReg;
    try {
      authReg = await _dbHelper.resolveAuthorizedCashRegister(
        cashierId: cashier.id!,
        terminalId: terminal.terminalId,
        requestedRegisterId: reqRegId,
      );
    } catch (e) {
      await _sendError(req, 409, 'REGISTER_UNAUTHORIZED', e.toString());
      return;
    }

    final shift = await _dbHelper.getCurrentOpenShift(
      cashierId: cashier.id,
      terminalId: terminal.terminalId,
      cashRegisterId: authReg.id,
    );
    if (shift == null || !shift.isOpen) {
      await _sendError(
        req,
        409,
        'SHIFT_CLOSED',
        'Tidak ada shift aktif terbuka untuk membuka laci kas.',
      );
      return;
    }

    final db = await _dbHelper.database;
    await db.insert('audit_logs', {
      'timestamp': DateTime.now().toIso8601String(),
      'user_id': cashier.id ?? 0,
      'user_name': cashier.name,
      'user_role': cashier.role,
      'action_type': 'buka_laci',
      'module': 'Keamanan & Laci Kas',
      'object_id': 'REG-${authReg.id}',
      'before_value': '',
      'after_value': 'terminal=${terminal.terminalId}, shift=${shift.id}, reason=$reason',
      'details':
          'Pembukaan laci manual dari ${terminal.terminalName} oleh ${cashier.name} (${authReg.name}): $reason',
    });

    final headerKey = (req.headers.value('X-Idempotency-Key') ?? '').trim();
    final job = await _dao.enqueuePrintJob(
      terminalId: terminal.terminalId,
      cashierId: cashier.id,
      printerId: terminal.defaultPrinterId ?? authReg.printerId,
      jobType: PrintJobType.manualDrawer,
      isReprint: false,
      openDrawerRequested: true,
      idempotencyKey: headerKey.isNotEmpty ? headerKey : null,
      payload: {'reason': reason, 'cash_register_id': authReg.id, 'shift_id': shift.id},
    );
    await _printWorker.drainNow(printerId: job.printerId);
    final refreshed = await _dao.getPrintJobByUuid(job.jobUuid) ?? job;
    await _sendOk(req, {
      'drawer_triggered': refreshed.drawerPulseSent,
      'print_job': refreshed.toApiJson(),
    });
  }

  // ==================== HELPERS ====================

  Map<String, dynamic> _cashierToSafeJson(UserModel u) => {
        'id': u.id,
        'name': u.name,
        'username': u.username,
        'role': u.role,
        'role_label': AppRoles.displayName(u.role),
        'permissions': u.permissions,
      };

  Map<String, dynamic> _shiftToJson(ShiftModel s) => {
        'id': s.id,
        'cashier_id': s.cashierId,
        'cashier_name': s.cashierName,
        'terminal_id': s.terminalId,
        'cash_register_id': s.cashRegisterId,
        'drawer_mode': s.drawerMode,
        'start_time': s.startTime.toIso8601String(),
        'starting_cash': s.startingCash,
        'status': s.status,
      };

  Map<String, dynamic>? _tryDecodeMap(String body) {
    if (body.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _sendOk(
    HttpRequest req,
    Map<String, dynamic> data, {
    int statusCode = 200,
  }) async {
    final syncVer = await _dao.getCatalogSyncVersion();
    final body = jsonEncode({
      'success': true,
      'data': data,
      'meta': {
        'server_time': DateTime.now().toIso8601String(),
        'protocol_version': protocolVersion,
        'sync_version': syncVer,
      },
    });
    req.response.statusCode = statusCode;
    req.response.headers.contentType = ContentType.json;
    req.response.headers.set('X-API-Version', protocolVersion);
    req.response.write(body);
    await req.response.close();
  }

  Future<void> _sendError(
    HttpRequest req,
    int statusCode,
    String code,
    String message, {
    Map<String, dynamic> details = const {},
  }) async {
    final body = jsonEncode({
      'success': false,
      'error': {
        'code': code,
        'message': message,
        'details': details,
      },
      'meta': {
        'server_time': DateTime.now().toIso8601String(),
        'protocol_version': protocolVersion,
      },
    });
    req.response.statusCode = statusCode;
    req.response.headers.contentType = ContentType.json;
    req.response.headers.set('X-API-Version', protocolVersion);
    req.response.write(body);
    await req.response.close();
  }
}
