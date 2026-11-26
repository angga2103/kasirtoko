import 'dart:io';
import 'package:flutter/services.dart';

class ServerLifecycleStatus {
  final bool shouldRun;
  final bool isRunning;
  final bool wasInterrupted;
  final String ipSummary;
  final int lastStartedAtMs;
  final bool ignoringBatteryOptimizations;
  final int sdkInt;

  const ServerLifecycleStatus({
    this.shouldRun = false,
    this.isRunning = false,
    this.wasInterrupted = false,
    this.ipSummary = '',
    this.lastStartedAtMs = 0,
    this.ignoringBatteryOptimizations = true,
    this.sdkInt = 0,
  });

  factory ServerLifecycleStatus.fromMap(Map<dynamic, dynamic>? map) {
    if (map == null) return const ServerLifecycleStatus();
    return ServerLifecycleStatus(
      shouldRun: map['shouldRun'] == true,
      isRunning: map['isRunning'] == true,
      wasInterrupted: map['wasInterrupted'] == true,
      ipSummary: (map['ipSummary'] ?? '').toString(),
      lastStartedAtMs: (map['lastStartedAtMs'] as num?)?.toInt() ?? 0,
      ignoringBatteryOptimizations: map['ignoringBatteryOptimizations'] != false,
      sdkInt: (map['sdkInt'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Phase 1 bridge for the Android `specialUse` Foreground Service lifecycle foundation.
/// NOTE: Phase 1 does NOT open any LAN HTTP/WebSocket sockets; this bridge manages
/// foreground service readiness, reboot recovery status, battery optimization checks,
/// and local Wi-Fi/Hotspot IP observation.
class ServerLifecycleBridge {
  static const MethodChannel _channel = MethodChannel('com.kasirtoko.app/server_lifecycle');

  static Future<ServerLifecycleStatus> startForegroundServerShell({
    required String storeName,
    int port = 8443,
  }) async {
    if (!Platform.isAndroid) return const ServerLifecycleStatus();
    try {
      final res = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'startForegroundServerShell',
        {'storeName': storeName, 'port': port},
      );
      return ServerLifecycleStatus.fromMap(res);
    } on MissingPluginException {
      return const ServerLifecycleStatus();
    }
  }

  static Future<ServerLifecycleStatus> updateForegroundServerInfo({
    required String storeName,
    int port = 8443,
    int connectedCount = 0,
    bool serverLive = false,
  }) async {
    if (!Platform.isAndroid) return const ServerLifecycleStatus();
    try {
      final res = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'updateForegroundServerInfo',
        {
          'storeName': storeName,
          'port': port,
          'connectedCount': connectedCount,
          'serverLive': serverLive,
        },
      );
      return ServerLifecycleStatus.fromMap(res);
    } on MissingPluginException {
      return const ServerLifecycleStatus();
    }
  }

  static Future<ServerLifecycleStatus> stopForegroundServerShell() async {
    if (!Platform.isAndroid) return const ServerLifecycleStatus();
    try {
      final res = await _channel.invokeMethod<Map<dynamic, dynamic>>('stopForegroundServerShell');
      return ServerLifecycleStatus.fromMap(res);
    } on MissingPluginException {
      return const ServerLifecycleStatus();
    }
  }

  static Future<ServerLifecycleStatus> getStatus() async {
    if (!Platform.isAndroid) return const ServerLifecycleStatus();
    try {
      final res = await _channel.invokeMethod<Map<dynamic, dynamic>>('getForegroundServerStatus');
      return ServerLifecycleStatus.fromMap(res);
    } on MissingPluginException {
      return const ServerLifecycleStatus();
    }
  }

  static Future<bool> isIgnoringBatteryOptimizations() async {
    if (!Platform.isAndroid) return true;
    try {
      return await _channel.invokeMethod<bool>('isIgnoringBatteryOptimizations') ?? true;
    } on MissingPluginException {
      return true;
    }
  }

  static Future<bool> requestIgnoreBatteryOptimizations() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('requestIgnoreBatteryOptimizations') ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  static Future<String> getActiveLocalIps() async {
    if (!Platform.isAndroid) return '';
    try {
      return await _channel.invokeMethod<String>('getActiveLocalIps') ?? '';
    } on MissingPluginException {
      return '';
    }
  }
}
