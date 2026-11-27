import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Lightweight UDP LAN discovery responder for automatic Admin IP rediscovery after
/// router DHCP lease renewal or failover to Admin phone Hotspot.
///
/// SECURITY BOUNDARY: Discovery answers contain ONLY non-sensitive routing hints
/// (`server_id`, listening port, and advertised LAN IPs). Staff MUST still verify
/// TLS certificate SHA-256 fingerprint pinning, server_id equality, HMAC signatures,
/// device token, and session token on HTTPS before accepting any connection.
class LanDiscoveryResponder {
  static const int discoveryPort = 45843;
  static const String probePrefix = 'KASIRTOKO_DISCOVER';
  static const String replyType = 'KASIRTOKO_HERE';

  RawDatagramSocket? _socket;
  String Function() _serverIdProvider = () => '';
  int Function() _portProvider = () => 8443;
  List<String> Function() _ipsProvider = () => const [];
  String Function() _networkModeProvider = () => 'router';

  bool get isListening => _socket != null;
  int get boundPort => _socket?.port ?? discoveryPort;

  Future<void> start({
    required String Function() serverIdProvider,
    required int Function() portProvider,
    required List<String> Function() ipsProvider,
    required String Function() networkModeProvider,
    int udpPort = discoveryPort,
  }) async {
    await stop();
    _serverIdProvider = serverIdProvider;
    _portProvider = portProvider;
    _ipsProvider = ipsProvider;
    _networkModeProvider = networkModeProvider;

    try {
      _socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        udpPort,
        reuseAddress: true,
      );
      _socket!.broadcastEnabled = true;
      _socket!.listen((event) {
        if (event != RawSocketEvent.read) return;
        final dg = _socket?.receive();
        if (dg == null) return;
        _handlePacket(dg);
      }, onError: (_) {});
    } catch (_) {
      // Non-fatal fallback: some OS/sandbox environments restrict UDP broadcast sockets.
      // Staff multi-endpoint HTTPS health probe & manual failover continue to work cleanly.
      _socket = null;
    }
  }

  void _handlePacket(Datagram dg) {
    try {
      final msg = utf8.decode(dg.data).trim();
      if (!msg.startsWith(probePrefix)) return;
      final serverId = _serverIdProvider();
      if (serverId.isEmpty) return;

      final parts = msg.split(':');
      if (parts.length >= 2 && parts[1].trim().isNotEmpty) {
        final requestedId = parts[1].trim();
        if (requestedId != '*' && requestedId != serverId) {
          return;
        }
      }

      final payload = jsonEncode({
        'type': replyType,
        'server_id': serverId,
        'port': _portProvider(),
        'ips': _ipsProvider(),
        'network_mode': _networkModeProvider(),
        'ts': DateTime.now().millisecondsSinceEpoch,
      });
      _socket?.send(utf8.encode(payload), dg.address, dg.port);
    } catch (_) {}
  }

  Future<void> stop() async {
    try {
      _socket?.close();
    } catch (_) {}
    _socket = null;
  }
}
