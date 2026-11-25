import 'dart:typed_data';
import '../../models/printer_device.dart';

class PrinterOperationResult {
  final bool success;
  final String message;

  PrinterOperationResult({required this.success, required this.message});
}

abstract class PrinterAdapter {
  PrinterDeviceModel get device;

  Future<PrinterOperationResult> testConnection();

  Future<PrinterOperationResult> printRawBytes(Uint8List bytes);

  Future<PrinterOperationResult> openCashDrawer();
}
