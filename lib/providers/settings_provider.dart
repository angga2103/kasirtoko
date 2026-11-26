import 'dart:math';
import 'package:flutter/foundation.dart';
import '../database/db_helper.dart';
import '../models/cash_register.dart';
import '../models/receipt_config.dart';
import '../models/store_profile.dart';
import '../models/user.dart';
import '../utils/currency_format.dart';

class SettingsProvider extends ChangeNotifier {
  String _storeName = 'TOKO BERKAH JAYA';
  String _storeAddress = 'Jl. Ahmad Yani No. 88, Kota';
  String _storePhone = '081234567890';
  String _storeEmail = '';
  String _ownerName = 'Pemilik Toko';
  String _ownerPhone = '081234567890';
  String _businessIdentity = 'Universal Retail & Service POS';
  String _branchName = 'Cabang Utama';
  String _logoPath = '';
  BusinessType _businessType = BusinessType.general;
  String _currencySymbol = 'Rp ';
  String _invoicePrefix = 'INV';
  String _invoiceFormat = '{PREFIX}-{YYYYMMDD}-{RAND}';
  bool _taxEnabled = false;
  double _taxRate = 11.0;

  String _receiptFooter = 'Terima kasih atas kunjungan Anda!';
  String _printerPaperSize = '58mm';
  String _shiftStartHour = '08:00';
  ReceiptConfigModel _receiptConfig = const ReceiptConfigModel();
  String _drawerMode = DrawerMode.sharedDrawer;
  List<CashRegisterModel> _cashRegisters = [];
  List<CashRegisterAssignmentModel> _assignments = [];

  String get storeName => _storeName;
  String get storeAddress => _storeAddress;
  String get storePhone => _storePhone;
  String get storeEmail => _storeEmail;
  String get ownerName => _ownerName;
  String get ownerPhone => _ownerPhone;
  String get businessIdentity => _businessIdentity;
  String get branchName => _branchName;
  String get logoPath => _logoPath;
  BusinessType get businessType => _businessType;
  String get currencySymbol => _currencySymbol;
  String get invoicePrefix => _invoicePrefix;
  String get invoiceFormat => _invoiceFormat;
  bool get taxEnabled => _taxEnabled;
  double get taxRate => _taxRate;

  String get receiptFooter => _receiptConfig.footerText.isNotEmpty ? _receiptConfig.footerText : _receiptFooter;
  String get printerPaperSize => _receiptConfig.paperSize.isNotEmpty ? _receiptConfig.paperSize : _printerPaperSize;
  String get shiftStartHour => _shiftStartHour;
  ReceiptConfigModel get receiptConfig => _receiptConfig;
  String get drawerMode => _drawerMode;
  List<CashRegisterModel> get cashRegisters => _cashRegisters;
  List<CashRegisterAssignmentModel> get assignments => _assignments;

  Future<void> loadSettings() async {
    final settings = await DatabaseHelper.instance.getAllSettings();
    _storeName = settings['store_name'] ?? _storeName;
    _storeAddress = settings['store_address'] ?? _storeAddress;
    _storePhone = settings['store_phone'] ?? _storePhone;
    _storeEmail = settings['store_email'] ?? _storeEmail;
    _ownerName = settings['owner_name'] ?? _ownerName;
    _ownerPhone = settings['owner_phone'] ?? _ownerPhone;
    _businessIdentity = settings['business_identity'] ?? _businessIdentity;
    _branchName = settings['branch_name'] ?? _branchName;
    _logoPath = settings['logo_path'] ?? '';
    _businessType = BusinessType.fromCode(settings['business_type'] ?? 'general');
    _currencySymbol = settings['currency_symbol'] ?? 'Rp ';
    _invoicePrefix = settings['invoice_prefix'] ?? 'INV';
    _invoiceFormat = settings['invoice_format'] ?? '{PREFIX}-{YYYYMMDD}-{RAND}';
    _taxEnabled = (settings['tax_enabled'] ?? '0') == '1';
    _taxRate = double.tryParse(settings['tax_rate'] ?? '11') ?? 11.0;

    _receiptFooter = settings['receipt_footer'] ?? _receiptFooter;
    _printerPaperSize = settings['printer_paper_size'] ?? _printerPaperSize;
    _shiftStartHour = settings['shift_start_hour'] ?? _shiftStartHour;
    _drawerMode = DrawerMode.normalize(settings['drawer_mode']);

    final rawReceiptJson = settings['receipt_config_json'] ?? '';
    if (rawReceiptJson.isNotEmpty) {
      _receiptConfig = ReceiptConfigModel.fromJson(rawReceiptJson);
    } else {
      _receiptConfig = ReceiptConfigModel(
        paperSize: _printerPaperSize,
        footerText: _receiptFooter,
      );
    }

    _cashRegisters = await DatabaseHelper.instance.getCashRegisters(includeInactive: true);
    _assignments = await DatabaseHelper.instance.getCashRegisterAssignments();

    CurrencyHelper.setCurrencySymbol(_currencySymbol);
    notifyListeners();
  }

  Future<void> refreshRegistersAndAssignments() async {
    _cashRegisters = await DatabaseHelper.instance.getCashRegisters(includeInactive: true);
    _assignments = await DatabaseHelper.instance.getCashRegisterAssignments();
    notifyListeners();
  }

  Future<void> updateDrawerMode(String mode, {UserModel? actor}) async {
    await DatabaseHelper.instance.setDrawerMode(mode, actor: actor);
    _drawerMode = DrawerMode.normalize(mode);
    notifyListeners();
  }

  String generateTransactionNumber() {
    final now = DateTime.now();
    final dateStr =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final rand = (Random().nextInt(9000) + 1000).toString();
    final timeStr = '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';

    String formatted = _invoiceFormat
        .replaceAll('{PREFIX}', _invoicePrefix.isEmpty ? 'INV' : _invoicePrefix)
        .replaceAll('{YYYYMMDD}', dateStr)
        .replaceAll('{HHMM}', timeStr)
        .replaceAll('{RAND}', rand);

    if (formatted.isEmpty) {
      formatted = 'INV-$dateStr-$rand';
    }
    return formatted;
  }

  Future<void> updateSettings({
    required String name,
    required String address,
    required String phone,
    String? email,
    String? ownerName,
    required String ownerPhone,
    String? businessIdentity,
    String? branchName,
    String? logoPath,
    BusinessType? businessType,
    String? currencySymbol,
    String? invoicePrefix,
    String? invoiceFormat,
    bool? taxEnabled,
    double? taxRate,
    required String footer,
    required String paperSize,
    required String startHour,
  }) async {
    _storeName = name;
    _storeAddress = address;
    _storePhone = phone;
    if (email != null) _storeEmail = email;
    if (ownerName != null) _ownerName = ownerName;
    _ownerPhone = ownerPhone;
    if (businessIdentity != null) _businessIdentity = businessIdentity;
    if (branchName != null) _branchName = branchName;
    if (logoPath != null) _logoPath = logoPath;
    if (businessType != null) _businessType = businessType;
    if (currencySymbol != null && currencySymbol.isNotEmpty) {
      _currencySymbol = currencySymbol;
      CurrencyHelper.setCurrencySymbol(_currencySymbol);
    }
    if (invoicePrefix != null && invoicePrefix.isNotEmpty) _invoicePrefix = invoicePrefix;
    if (invoiceFormat != null && invoiceFormat.isNotEmpty) _invoiceFormat = invoiceFormat;
    if (taxEnabled != null) _taxEnabled = taxEnabled;
    if (taxRate != null) _taxRate = taxRate;

    _receiptFooter = footer;
    _printerPaperSize = paperSize;
    _shiftStartHour = startHour;
    _receiptConfig = _receiptConfig.copyWith(
      paperSize: paperSize,
      footerText: footer,
    );

    final db = DatabaseHelper.instance;
    await db.setSetting('store_name', _storeName);
    await db.setSetting('store_address', _storeAddress);
    await db.setSetting('store_phone', _storePhone);
    await db.setSetting('store_email', _storeEmail);
    await db.setSetting('owner_name', _ownerName);
    await db.setSetting('owner_phone', _ownerPhone);
    await db.setSetting('business_identity', _businessIdentity);
    await db.setSetting('branch_name', _branchName);
    await db.setSetting('logo_path', _logoPath);
    await db.setSetting('business_type', _businessType.code);
    await db.setSetting('currency_symbol', _currencySymbol);
    await db.setSetting('invoice_prefix', _invoicePrefix);
    await db.setSetting('invoice_format', _invoiceFormat);
    await db.setSetting('tax_enabled', _taxEnabled ? '1' : '0');
    await db.setSetting('tax_rate', _taxRate.toString());
    await db.setSetting('receipt_footer', _receiptFooter);
    await db.setSetting('printer_paper_size', _printerPaperSize);
    await db.setSetting('shift_start_hour', _shiftStartHour);
    await db.setSetting('receipt_config_json', _receiptConfig.toJson());

    notifyListeners();
  }

  Future<void> updateLogoPath(String path) async {
    _logoPath = path;
    await DatabaseHelper.instance.setSetting('logo_path', path);
    notifyListeners();
  }

  Future<void> updateBusinessType(BusinessType type) async {
    _businessType = type;
    await DatabaseHelper.instance.setSetting('business_type', type.code);
    notifyListeners();
  }

  Future<void> updateReceiptConfig(ReceiptConfigModel config) async {
    _receiptConfig = config;
    _receiptFooter = config.footerText;
    _printerPaperSize = config.paperSize;
    await DatabaseHelper.instance.setSetting('receipt_config_json', config.toJson());
    await DatabaseHelper.instance.setSetting('receipt_footer', config.footerText);
    await DatabaseHelper.instance.setSetting('printer_paper_size', config.paperSize);
    notifyListeners();
  }
}
