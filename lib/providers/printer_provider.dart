import 'package:flutter/foundation.dart';
import '../database/db_helper.dart';
import '../models/printer_device.dart';
import '../services/printer/printer_adapter.dart';
import '../services/printer/printer_manager.dart';

class PrinterProvider extends ChangeNotifier {
  List<PrinterDeviceModel> _printers = [];
  final Map<int, bool> _liveConnectionStatus = {};
  final Map<int, String> _lastStatusMessages = {};
  bool _isLoading = false;

  List<PrinterDeviceModel> get printers => _printers;
  bool get isLoading => _isLoading;

  bool? getLiveStatus(int? printerId) =>
      printerId == null ? null : _liveConnectionStatus[printerId];

  String? getLastMessage(int? printerId) =>
      printerId == null ? null : _lastStatusMessages[printerId];

  PrinterDeviceModel? get defaultPrinter {
    for (final p in _printers) {
      if (p.isDefault) return p;
    }
    return _printers.isNotEmpty ? _printers.first : null;
  }

  PrinterDeviceModel? getPreferredPrinterFor(String category) {
    if (defaultPrinter != null && defaultPrinter!.category == category) {
      return defaultPrinter;
    }
    for (final p in _printers) {
      if (p.category == category) return p;
    }
    return defaultPrinter;
  }

  Future<void> loadPrinters() async {
    _isLoading = true;
    notifyListeners();
    _printers = await DatabaseHelper.instance.getPrinters();
    _isLoading = false;
    notifyListeners();
  }

  Future<void> savePrinter(PrinterDeviceModel printer) async {
    if (printer.id == null) {
      await DatabaseHelper.instance.insertPrinter(printer);
    } else {
      await DatabaseHelper.instance.updatePrinter(printer);
    }
    await loadPrinters();
  }

  Future<void> setDefaultPrinter(int id) async {
    await DatabaseHelper.instance.setDefaultPrinter(id);
    await loadPrinters();
  }

  Future<void> deletePrinter(int id) async {
    await DatabaseHelper.instance.deletePrinter(id);
    _liveConnectionStatus.remove(id);
    _lastStatusMessages.remove(id);
    await loadPrinters();
  }

  Future<PrinterOperationResult> testPrinter(
    PrinterDeviceModel printer, {
    required String storeName,
    bool sendTestPage = false,
  }) async {
    final res = await PrinterManager.testPrinter(
      printer,
      storeName: storeName,
      alsoSendTestPage: sendTestPage,
    );
    if (printer.id != null) {
      _liveConnectionStatus[printer.id!] = res.success;
      _lastStatusMessages[printer.id!] = res.message;
      notifyListeners();
    }
    return res;
  }
}
