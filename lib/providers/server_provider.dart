import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../database/db_helper.dart';
import '../database/multi_device_dao.dart';
import '../models/paired_terminal.dart';
import '../models/print_job.dart';
import '../services/server/lan_pos_server.dart';
import '../services/server/tls_certificate_manager.dart';
import '../services/server_lifecycle_bridge.dart';

class ActivePairingBanner {
  final PairingTicket ticket;
  final String qrPayloadJson;
  final List<String> serverIps;
  final int port;
  final String certSha256;
  final String shortPin;

  const ActivePairingBanner({
    required this.ticket,
    required this.qrPayloadJson,
    required this.serverIps,
    required this.port,
    required this.certSha256,
    required this.shortPin,
  });
}

class PosServerProvider extends ChangeNotifier {
  final DatabaseHelper _dbHelper;
  final MultiDeviceDao _dao;
  late final LanPosServer _server;

  bool _isBusy = false;
  int _port = 8443;
  List<String> _localIps = [];
  List<PairedTerminalModel> _terminals = [];
  List<PrintJobModel> _printJobs = [];
  ServerLifecycleStatus _fgsStatus = const ServerLifecycleStatus();
  ActivePairingBanner? _activePairing;
  String? _lastError;
  Timer? _refreshTimer;

  PosServerProvider({
    DatabaseHelper? dbHelper,
    MultiDeviceDao? dao,
    LanPosServer? server,
  })  : _dbHelper = dbHelper ?? DatabaseHelper.instance,
        _dao = dao ?? MultiDeviceDao(dbHelper: dbHelper) {
    _server = server ??
        LanPosServer(
          dbHelper: _dbHelper,
          dao: _dao,
          onConnectionsChanged: _onServerConnectionsChanged,
        );
  }

  bool get isBusy => _isBusy;
  bool get isRunning => _server.isRunning;
  int get port => _server.isRunning ? _server.port : _port;
  List<String> get localIps => _localIps;
  List<PairedTerminalModel> get terminals => _terminals;
  List<PrintJobModel> get printJobs => _printJobs;
  List<ConnectedTerminalSnapshot> get connectedSockets => _server.connectedTerminals;
  ServerLifecycleStatus get fgsStatus => _fgsStatus;
  TlsServerIdentity? get identity => _server.identity;
  ActivePairingBanner? get activePairing => _activePairing;
  String? get lastError => _lastError;
  LanPosServer get server => _server;

  bool isTerminalOnline(String terminalId) =>
      _server.connectedTerminals.any((c) => c.terminalId == terminalId);

  Future<void> initialize() async {
    await refreshStatus();
    if (_fgsStatus.shouldRun && !_server.isRunning) {
      await startServer(port: _port);
    }
  }

  Future<void> refreshStatus() async {
    _localIps = await _collectLocalIpv4Addresses();
    _fgsStatus = await ServerLifecycleBridge.getStatus();
    _terminals = await _dao.listTerminals(includeRevoked: true);
    _printJobs = await _dao.listPrintJobs(limit: 50);
    if (_server.isRunning) {
      final storeName = await _dbHelper.getSetting('store_name', defaultValue: 'KasirToko POS');
      await ServerLifecycleBridge.updateForegroundServerInfo(
        storeName: storeName,
        port: _server.port,
        connectedCount: _server.connectedTerminals.length,
        serverLive: true,
      );
    }
    notifyListeners();
  }

  Future<bool> startServer({int port = 8443}) async {
    if (_isBusy) return _server.isRunning;
    _isBusy = true;
    _lastError = null;
    notifyListeners();

    try {
      _port = port;
      _localIps = await _collectLocalIpv4Addresses();
      final storeName = await _dbHelper.getSetting('store_name', defaultValue: 'KasirToko POS');
      _fgsStatus = await ServerLifecycleBridge.startForegroundServerShell(
        storeName: storeName,
        port: port,
      );
      await _server.start(port: port, extraIpAddresses: _localIps);
      await ServerLifecycleBridge.updateForegroundServerInfo(
        storeName: storeName,
        port: _server.port,
        connectedCount: _server.connectedTerminals.length,
        serverLive: true,
      );

      _refreshTimer?.cancel();
      _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        unawaited(refreshStatus());
      });
      await refreshStatus();
      return true;
    } catch (e) {
      _lastError = 'Gagal menjalankan server POS: $e';
      notifyListeners();
      return false;
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  Future<void> stopServer() async {
    if (_isBusy) return;
    _isBusy = true;
    _lastError = null;
    notifyListeners();
    try {
      _refreshTimer?.cancel();
      _refreshTimer = null;
      _activePairing = null;
      await _server.stop();
      _fgsStatus = await ServerLifecycleBridge.stopForegroundServerShell();
      await refreshStatus();
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  Future<ActivePairingBanner> createPairingBanner({
    String suggestedName = '',
    int? assignedRegisterId,
    bool allowAutoOpenDrawer = false,
    bool allowManualOpenDrawer = false,
    String actorName = 'Admin',
  }) async {
    if (!_server.isRunning) {
      await startServer(port: _port);
    }
    _localIps = await _collectLocalIpv4Addresses();
    final ticket = await _dao.createPairingToken(
      suggestedName: suggestedName,
      assignedRegisterId: assignedRegisterId,
      allowAutoOpenDrawer: allowAutoOpenDrawer,
      allowManualOpenDrawer: allowManualOpenDrawer,
      actorName: actorName,
    );
    final storeName = await _dbHelper.getSetting('store_name', defaultValue: 'KasirToko POS');
    final certSha = _server.identity?.sha256Hex ?? '';
    final shortPin = _server.identity?.shortPin ?? '';
    final payload = {
      'v': 1,
      'store_name': storeName,
      'ips': _localIps,
      'port': _server.port,
      'pairing_code': ticket.pairingCode,
      'cert_sha256': certSha,
      'short_pin': shortPin,
      'expires_at': ticket.expiresAt,
    };

    _activePairing = ActivePairingBanner(
      ticket: ticket,
      qrPayloadJson: jsonEncode(payload),
      serverIps: _localIps,
      port: _server.port,
      certSha256: certSha,
      shortPin: shortPin,
    );
    notifyListeners();
    return _activePairing!;
  }

  void clearActivePairing() {
    _activePairing = null;
    notifyListeners();
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
    await _dao.updateTerminalPolicy(
      terminalId: terminalId,
      terminalName: terminalName,
      assignedRegisterId: assignedRegisterId,
      clearAssignedRegister: clearAssignedRegister,
      defaultPrinterId: defaultPrinterId,
      clearDefaultPrinter: clearDefaultPrinter,
      allowAutoOpenDrawer: allowAutoOpenDrawer,
      allowManualOpenDrawer: allowManualOpenDrawer,
      actorName: actorName,
    );
    await refreshStatus();
  }

  Future<void> revokeTerminal(String terminalId, {String actorName = 'Admin'}) async {
    await _dao.revokeTerminal(terminalId, actorName: actorName);
    await refreshStatus();
  }

  Future<void> stageCertificateRotation() async {
    await _server.stageCertificateRotation(extraIpAddresses: _localIps);
    await refreshStatus();
  }

  Future<void> retryPrintJob(String jobUuid) async {
    final job = await _dao.retryPrintJob(jobUuid);
    _server.printWorker.scheduleDrain(printerId: job.printerId);
    await refreshStatus();
  }

  Future<void> cancelPrintJob(String jobUuid) async {
    await _dao.cancelPrintJob(jobUuid);
    await refreshStatus();
  }

  void _onServerConnectionsChanged() {
    unawaited(refreshStatus());
  }

  Future<List<String>> _collectLocalIpv4Addresses() async {
    final ips = <String>[];
    try {
      final fgsIps = await ServerLifecycleBridge.getActiveLocalIps();
      if (fgsIps.isNotEmpty &&
          !fgsIps.contains('Menunggu') &&
          !fgsIps.contains('Tidak tersedia')) {
        for (final part in fgsIps.split(',')) {
          final clean = part.trim();
          if (clean.isNotEmpty && !ips.contains(clean)) {
            ips.add(clean);
          }
        }
      }
    } catch (_) {}

    if (ips.isEmpty) {
      try {
        final interfaces = await NetworkInterface.list(
          type: InternetAddressType.IPv4,
          includeLinkLocal: false,
          includeLoopback: false,
        );
        for (final intf in interfaces) {
          for (final addr in intf.addresses) {
            if (!addr.isLoopback && !ips.contains(addr.address)) {
              ips.add(addr.address);
            }
          }
        }
      } catch (_) {}
    }

    if (ips.isEmpty) {
      ips.add('127.0.0.1');
    }
    return ips;
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _server.printWorker.dispose();
    super.dispose();
  }
}
