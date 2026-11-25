import 'dart:io';
import 'package:flutter/services.dart';

class PairedBluetoothDevice {
  final String name;
  final String address;

  PairedBluetoothDevice({required this.name, required this.address});
}

class ConnectedUsbDevice {
  final String deviceName;
  final String productName;
  final String manufacturerName;
  final int vendorId;
  final int productId;
  final bool hasPermission;

  ConnectedUsbDevice({
    required this.deviceName,
    required this.productName,
    required this.manufacturerName,
    required this.vendorId,
    required this.productId,
    required this.hasPermission,
  });
}

class HardwareResult {
  final bool success;
  final String message;

  HardwareResult({required this.success, required this.message});
}

class HardwareBridge {
  static const MethodChannel _channel = MethodChannel('com.kasirtoko.app/hardware');

  static Future<void> playBeep({int durationMs = 120}) async {
    try {
      await _channel.invokeMethod('playBeep', {'durationMs': durationMs});
    } catch (_) {}
  }

  static Future<List<PairedBluetoothDevice>> getPairedBluetoothDevices() async {
    try {
      final res = await _channel.invokeMethod<List<dynamic>>('getPairedBluetoothDevices');
      if (res == null) return [];
      return res.map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        return PairedBluetoothDevice(
          name: (m['name'] ?? 'Printer Bluetooth').toString(),
          address: (m['address'] ?? '').toString(),
        );
      }).toList();
    } on PlatformException catch (e) {
      throw Exception(e.message ?? 'Gagal membaca daftar perangkat Bluetooth');
    }
  }

  static Future<HardwareResult> testBluetoothConnection(String address) async {
    try {
      final res = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'testBluetoothConnection',
        {'address': address},
      );
      return HardwareResult(
        success: res?['connected'] == true,
        message: (res?['message'] ?? 'Bluetooth terhubung').toString(),
      );
    } on PlatformException catch (e) {
      return HardwareResult(
        success: false,
        message: e.message ?? 'Gagal menghubungkan ke printer Bluetooth',
      );
    } catch (e) {
      return HardwareResult(success: false, message: 'Error Bluetooth: $e');
    }
  }

  static Future<HardwareResult> printBluetoothBytes(String address, Uint8List bytes) async {
    try {
      await _channel.invokeMethod('printBluetoothBytes', {
        'address': address,
        'bytes': bytes,
      });
      return HardwareResult(success: true, message: 'Data terkirim ke printer Bluetooth');
    } on PlatformException catch (e) {
      return HardwareResult(
        success: false,
        message: e.message ?? 'Gagal mencetak melalui Bluetooth',
      );
    } catch (e) {
      return HardwareResult(success: false, message: 'Error cetak Bluetooth: $e');
    }
  }

  static Future<List<ConnectedUsbDevice>> getUsbDevices() async {
    try {
      final res = await _channel.invokeMethod<List<dynamic>>('getUsbDevices');
      if (res == null) return [];
      return res.map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        return ConnectedUsbDevice(
          deviceName: (m['deviceName'] ?? '').toString(),
          productName: (m['productName'] ?? 'USB Printer').toString(),
          manufacturerName: (m['manufacturerName'] ?? '').toString(),
          vendorId: (m['vendorId'] as num?)?.toInt() ?? 0,
          productId: (m['productId'] as num?)?.toInt() ?? 0,
          hasPermission: m['hasPermission'] == true,
        );
      }).toList();
    } on PlatformException catch (e) {
      throw Exception(e.message ?? 'Gagal mendeteksi perangkat USB OTG');
    }
  }

  static Future<HardwareResult> testUsbConnection(String deviceName) async {
    try {
      final res = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'testUsbConnection',
        {'deviceName': deviceName},
      );
      return HardwareResult(
        success: res?['connected'] == true,
        message: (res?['message'] ?? 'USB OTG siap digunakan').toString(),
      );
    } on PlatformException catch (e) {
      return HardwareResult(
        success: false,
        message: e.message ?? 'Gagal mengecek printer USB OTG',
      );
    } catch (e) {
      return HardwareResult(success: false, message: 'Error USB: $e');
    }
  }

  static Future<HardwareResult> printUsbBytes(String deviceName, Uint8List bytes) async {
    try {
      await _channel.invokeMethod('printUsbBytes', {
        'deviceName': deviceName,
        'bytes': bytes,
      });
      return HardwareResult(success: true, message: 'Data terkirim ke printer USB OTG');
    } on PlatformException catch (e) {
      return HardwareResult(
        success: false,
        message: e.message ?? 'Gagal mencetak melalui USB OTG',
      );
    } catch (e) {
      return HardwareResult(success: false, message: 'Error cetak USB: $e');
    }
  }

  static Future<HardwareResult> testTcpConnection(String host, int port) async {
    if (host.trim().isEmpty) {
      return HardwareResult(success: false, message: 'Alamat IP printer LAN/Wi-Fi kosong.');
    }
    try {
      final socket = await Socket.connect(
        host.trim(),
        port,
        timeout: const Duration(seconds: 3),
      );
      await socket.close();
      return HardwareResult(
        success: true,
        message: 'Terhubung ke printer jaringan ${host.trim()}:$port',
      );
    } catch (e) {
      return HardwareResult(
        success: false,
        message: 'Tidak dapat terhubung ke ${host.trim()}:$port ($e)',
      );
    }
  }

  static Future<HardwareResult> printTcpBytes(String host, int port, Uint8List bytes) async {
    if (host.trim().isEmpty) {
      return HardwareResult(success: false, message: 'Alamat IP printer LAN/Wi-Fi kosong.');
    }
    Socket? socket;
    try {
      socket = await Socket.connect(
        host.trim(),
        port,
        timeout: const Duration(seconds: 4),
      );
      socket.add(bytes);
      await socket.flush();
      await socket.close();
      return HardwareResult(
        success: true,
        message: 'Data terkirim ke printer LAN ${host.trim()}:$port',
      );
    } catch (e) {
      try {
        await socket?.close();
      } catch (_) {}
      return HardwareResult(
        success: false,
        message: 'Gagal mengirim data ke ${host.trim()}:$port ($e)',
      );
    }
  }
}
