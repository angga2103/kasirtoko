import 'package:flutter/foundation.dart';
import '../database/db_helper.dart';

class SettingsProvider extends ChangeNotifier {
  String _storeName = 'TOKO BERKAH JAYA';
  String _storeAddress = 'Jl. Ahmad Yani No. 88, Kota';
  String _storePhone = '081234567890';
  String _ownerPhone = '081234567890';
  String _receiptFooter = 'Terima kasih atas kunjungan Anda!';
  String _printerPaperSize = '58mm';
  String _shiftStartHour = '08:00';

  String get storeName => _storeName;
  String get storeAddress => _storeAddress;
  String get storePhone => _storePhone;
  String get ownerPhone => _ownerPhone;
  String get receiptFooter => _receiptFooter;
  String get printerPaperSize => _printerPaperSize;
  String get shiftStartHour => _shiftStartHour;

  Future<void> loadSettings() async {
    final settings = await DatabaseHelper.instance.getAllSettings();
    _storeName = settings['store_name'] ?? _storeName;
    _storeAddress = settings['store_address'] ?? _storeAddress;
    _storePhone = settings['store_phone'] ?? _storePhone;
    _ownerPhone = settings['owner_phone'] ?? _ownerPhone;
    _receiptFooter = settings['receipt_footer'] ?? _receiptFooter;
    _printerPaperSize = settings['printer_paper_size'] ?? _printerPaperSize;
    _shiftStartHour = settings['shift_start_hour'] ?? _shiftStartHour;
    notifyListeners();
  }

  Future<void> updateSettings({
    required String name,
    required String address,
    required String phone,
    required String ownerPhone,
    required String footer,
    required String paperSize,
    required String startHour,
  }) async {
    _storeName = name;
    _storeAddress = address;
    _storePhone = phone;
    _ownerPhone = ownerPhone;
    _receiptFooter = footer;
    _printerPaperSize = paperSize;
    _shiftStartHour = startHour;

    await DatabaseHelper.instance.setSetting('store_name', name);
    await DatabaseHelper.instance.setSetting('store_address', address);
    await DatabaseHelper.instance.setSetting('store_phone', phone);
    await DatabaseHelper.instance.setSetting('owner_phone', ownerPhone);
    await DatabaseHelper.instance.setSetting('receipt_footer', footer);
    await DatabaseHelper.instance.setSetting('printer_paper_size', paperSize);
    await DatabaseHelper.instance.setSetting('shift_start_hour', startHour);

    notifyListeners();
  }
}
