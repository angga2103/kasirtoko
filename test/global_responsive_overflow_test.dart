import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:kasirtoko/database/db_helper.dart';
import 'package:kasirtoko/models/cash_register.dart';
import 'package:kasirtoko/models/customer.dart';
import 'package:kasirtoko/models/paired_terminal.dart';
import 'package:kasirtoko/models/print_job.dart';
import 'package:kasirtoko/models/printer_device.dart';
import 'package:kasirtoko/models/product.dart';
import 'package:kasirtoko/models/promo.dart';
import 'package:kasirtoko/models/transaction.dart';
import 'package:kasirtoko/models/transaction_item.dart';
import 'package:kasirtoko/providers/attendance_provider.dart';
import 'package:kasirtoko/providers/auth_provider.dart';
import 'package:kasirtoko/providers/cash_flow_provider.dart';
import 'package:kasirtoko/providers/customer_provider.dart';
import 'package:kasirtoko/providers/debt_provider.dart';
import 'package:kasirtoko/providers/pos_provider.dart';
import 'package:kasirtoko/providers/printer_provider.dart';
import 'package:kasirtoko/providers/product_provider.dart';
import 'package:kasirtoko/providers/purchase_provider.dart';
import 'package:kasirtoko/providers/server_provider.dart';
import 'package:kasirtoko/providers/service_order_provider.dart';
import 'package:kasirtoko/providers/settings_provider.dart';
import 'package:kasirtoko/screens/attendance/attendance_history_screen.dart';
import 'package:kasirtoko/screens/cash_flow/cash_flow_screen.dart';
import 'package:kasirtoko/screens/cash_flow/shift_screen.dart';
import 'package:kasirtoko/screens/customers/customer_list_screen.dart';
import 'package:kasirtoko/screens/debts/debt_list_screen.dart';
import 'package:kasirtoko/screens/employees/employee_management_screen.dart';
import 'package:kasirtoko/screens/home_screen.dart';
import 'package:kasirtoko/screens/login_screen.dart';
import 'package:kasirtoko/screens/pos/held_orders_dialog.dart';
import 'package:kasirtoko/screens/pos/payment_dialog.dart';
import 'package:kasirtoko/screens/pos/pos_screen.dart';
import 'package:kasirtoko/screens/pos/receipt_dialog.dart';
import 'package:kasirtoko/screens/products/barcode_generator_screen.dart';
import 'package:kasirtoko/screens/products/product_form_screen.dart';
import 'package:kasirtoko/screens/promo/promo_screen.dart';
import 'package:kasirtoko/screens/purchases/purchase_list_screen.dart';
import 'package:kasirtoko/screens/reports/daily_report_screen.dart';
import 'package:kasirtoko/screens/returns/return_screen.dart';
import 'package:kasirtoko/screens/service/service_form_screen.dart';
import 'package:kasirtoko/screens/settings/multi_device_server_screen.dart';
import 'package:kasirtoko/screens/settings/printer_management_screen.dart';
import 'package:kasirtoko/screens/settings/receipt_settings_screen.dart';
import 'package:kasirtoko/screens/settings/settings_screen.dart';
import 'package:kasirtoko/services/server/tls_certificate_manager.dart';
import 'package:kasirtoko/services/server_lifecycle_bridge.dart';
import 'package:kasirtoko/utils/app_theme.dart';
import 'package:kasirtoko/utils/date_format.dart';

const bool _exportScreenshots = bool.fromEnvironment('EXPORT_SCREENSHOTS');

class _Vp {
  final String label;
  final Size size;
  final double textScale;
  final double bottomInset;

  const _Vp(
    this.label,
    this.size, {
    this.textScale = 1.0,
    this.bottomInset = 0.0,
  });
}

const List<_Vp> _eightViewports = [
  _Vp('320x640_s10', Size(320, 640)),
  _Vp('360x640_s10', Size(360, 640)),
  _Vp('360x800_s10', Size(360, 800)),
  _Vp('390x844_s10', Size(390, 844)),
  _Vp('412x915_s10', Size(412, 915)),
  _Vp('480x960_s10', Size(480, 960)),
  _Vp('800x1280_s10', Size(800, 1280)),
  _Vp('1280x800_s10', Size(1280, 800)),
];

const List<_Vp> _stressViewports = [
  _Vp('320x640_s12', Size(320, 640), textScale: 1.2),
  _Vp('320x640_s15', Size(320, 640), textScale: 1.5),
  _Vp('360x640_s15', Size(360, 640), textScale: 1.5),
  _Vp('320x640_kb260', Size(320, 640), textScale: 1.2, bottomInset: 260),
  _Vp('360x640_kb260', Size(360, 640), textScale: 1.5, bottomInset: 260),
  _Vp('800x1280_s15', Size(800, 1280), textScale: 1.5),
];

class _FakeServerProvider extends PosServerProvider {
  bool _running = true;
  late List<PairedTerminalModel> _terminals;
  final List<PrintJobModel> _jobs = const [
    PrintJobModel(
      id: 1,
      jobUuid: 'job-01',
      terminalId: 'TERM-COUNTER-UTAMA-01',
      invoiceNumber: 'INV-STAFF-20261127-001',
      printerId: 1,
      status: PrintJobStatus.submitted,
      createdAt: '2026-11-27T12:00:00',
    ),
  ];

  _FakeServerProvider() {
    _terminals = [
      const PairedTerminalModel(
        id: 1,
        terminalId: 'TERM-COUNTER-UTAMA-01',
        terminalCode: 'T01',
        terminalName: 'Terminal Kasir Counter Utama Mall Selatan Lantai Dasar',
        deviceModel: 'Samsung Galaxy Tab A9 Pro Business Edition',
        deviceSecretHash: 'h1',
        deviceTokenHash: 't1',
        assignedRegisterId: 1,
        defaultPrinterId: 1,
        allowAutoOpenDrawer: true,
        allowManualOpenDrawer: true,
        pairedAt: '2026-11-27T08:00:00',
      ),
      const PairedTerminalModel(
        id: 2,
        terminalId: 'TERM-EKSPRES-02',
        terminalCode: 'T02',
        terminalName: 'Counter Layanan Ekspres Pintu Timur Parkiran Utama',
        deviceModel: 'Xiaomi Redmi Note 13 Pro NFC',
        deviceSecretHash: 'h2',
        deviceTokenHash: 't2',
        assignedRegisterId: 2,
        defaultPrinterId: 2,
        allowAutoOpenDrawer: false,
        allowManualOpenDrawer: true,
        pairedAt: '2026-11-27T09:00:00',
      ),
    ];
  }

  @override
  bool get isBusy => false;

  @override
  bool get isRunning => _running;

  @override
  int get port => 8443;

  @override
  List<String> get localIps => const ['192.168.43.100', '10.0.2.15'];

  @override
  List<PairedTerminalModel> get terminals => _terminals;

  @override
  List<PrintJobModel> get printJobs => _jobs;

  @override
  ServerLifecycleStatus get fgsStatus => const ServerLifecycleStatus(
        shouldRun: true,
        isRunning: true,
        ignoringBatteryOptimizations: true,
        sdkInt: 34,
      );

  @override
  TlsServerIdentity? get identity => const TlsServerIdentity(
        certPem: '',
        privateKeyPem: '',
        sha256Hex: 'a1b2c3d4e5f60708a1b2c3d4e5f60708a1b2c3d4e5f60708a1b2c3d4e5f60708',
        createdAt: '2026-11-27',
        expiresAt: '2029-11-27',
      );

  @override
  ActivePairingBanner? get activePairing => null;

  @override
  String? get lastError => null;

  @override
  bool isTerminalOnline(String terminalId) => terminalId == 'TERM-COUNTER-UTAMA-01';

  @override
  Future<void> refreshStatus() async {
    notifyListeners();
  }

  @override
  Future<bool> startServer({int port = 8443}) async {
    _running = true;
    notifyListeners();
    return true;
  }

  @override
  Future<void> stopServer() async {
    _running = false;
    notifyListeners();
  }

  @override
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
    _terminals = _terminals.map((t) {
      if (t.terminalId != terminalId) return t;
      return PairedTerminalModel(
        id: t.id,
        terminalId: t.terminalId,
        terminalCode: t.terminalCode,
        terminalName: terminalName ?? t.terminalName,
        deviceModel: t.deviceModel,
        deviceSecretHash: t.deviceSecretHash,
        deviceTokenHash: t.deviceTokenHash,
        assignedRegisterId: clearAssignedRegister ? null : (assignedRegisterId ?? t.assignedRegisterId),
        defaultPrinterId: clearDefaultPrinter ? null : (defaultPrinterId ?? t.defaultPrinterId),
        allowAutoOpenDrawer: allowAutoOpenDrawer ?? t.allowAutoOpenDrawer,
        allowManualOpenDrawer: allowManualOpenDrawer ?? t.allowManualOpenDrawer,
        isRevoked: t.isRevoked,
        pairedAt: t.pairedAt,
        lastSeenAt: t.lastSeenAt,
      );
    }).toList();
    notifyListeners();
  }
}

class _AdminTestHarness {
  final AuthProvider auth = AuthProvider();
  final ProductProvider product = ProductProvider();
  final PosProvider pos = PosProvider();
  final CashFlowProvider cashFlow = CashFlowProvider();
  final DebtProvider debt = DebtProvider();
  final AttendanceProvider attendance = AttendanceProvider();
  final SettingsProvider settings = SettingsProvider();
  final CustomerProvider customer = CustomerProvider();
  final PurchaseProvider purchase = PurchaseProvider();
  final PrinterProvider printer = PrinterProvider();
  final ServiceOrderProvider service = ServiceOrderProvider();
  final _FakeServerProvider server = _FakeServerProvider();
  int secondPrinterId = 0;

  static Future<_AdminTestHarness> createOpenDbAndSeed() async {
    await DatabaseHelper.instance.openTestDatabase(path: inMemoryDatabasePath);
    final db = DatabaseHelper.instance;

    // Add extra cash register & thermal printers with realistic long names
    await db.insertCashRegister(
      CashRegisterModel(
        registerCode: 'REG-UTAMA-02',
        name: 'Laci Kasir Counter Depan Layanan Ekspres & Grosir Cabang Mall',
        isShared: false,
      ),
    );
    await db.insertPrinter(
      PrinterDeviceModel(
        name: 'Printer Thermal Bluetooth 80mm High Speed Counter Utama Depan',
        category: PrinterCategory.thermal,
        connectionType: PrinterConnectionType.bluetooth,
        address: 'AA:BB:CC:11:22:33',
        paperSize: '80mm',
        isDefault: true,
      ),
    );
    final secondPrnId = await db.insertPrinter(
      PrinterDeviceModel(
        name: 'Printer Thermal LAN Counter Ekspres Gudang Belakang',
        category: PrinterCategory.thermal,
        connectionType: PrinterConnectionType.lan,
        address: '192.168.1.210',
        paperSize: '58mm',
      ),
    );
    final prodId = await db.insertProduct(
      ProductModel(
        code: 'PRD-VIP-001',
        name: 'Kopi Susu Gula Aren Premium Kemasan Botol 1000ml Edisi Lebaran',
        category: 'Minuman',
        barcode: '8991009991',
        sellingPrice: 125000,
        costPrice: 80000,
        stock: 30,
      ),
    );
    await db.insertProduct(
      ProductModel(
        code: 'SRV-VIP-002',
        name: 'Jasa Packing Kayu & Proteksi Pengiriman Ekspedisi',
        category: 'Jasa',
        isService: true,
        sellingPrice: 45000,
        stock: 0,
      ),
    );
    await db.insertCustomer(
      CustomerModel(
        name: 'Ibu Hj. Siti Fatimah Zahra Counter Grosir Cabang Mall',
        phone: '081234567890',
        address: 'Jl. Merdeka Selatan Raya No. 123',
      ),
    );

    final h = _AdminTestHarness();
    h.secondPrinterId = secondPrnId;
    await h.auth.loadUsers();
    // Login via default Owner seeded PIN ('123456') or set admin logged in via authenticateWithPin
    await h.auth.loginWithPin('123456');
    if (h.auth.currentUser == null && h.auth.activeUsers.isNotEmpty) {
      await h.auth.loginWithPassword(h.auth.activeUsers.first.username, 'admin123');
    }
    await h.settings.loadSettings();
    await h.printer.loadPrinters();
    await h.product.loadProducts();
    await h.customer.loadCustomers();
    await h.cashFlow.checkOpenShift(cashierId: h.auth.currentUser?.id ?? 1);
    if (!h.cashFlow.isShiftOpen) {
      await h.cashFlow.startShift(
        cashierId: h.auth.currentUser?.id ?? 1,
        cashierName: h.auth.currentUser?.name ?? 'Pemilik Toko',
        startingCash: 1500000,
      );
    }
    await h.debt.loadDebts();
    await h.purchase.loadPurchases();
    await h.attendance.loadAttendances();
    await h.service.loadOrders();

    // Populate cart & held orders for POS/Payment/Held tests
    final addedProd = h.product.allProducts.firstWhere((p) => p.id == prodId, orElse: () => h.product.allProducts.first);
    h.pos.addProduct(addedProd);
    h.pos.addProduct(h.product.allProducts.last);
    h.pos.holdCurrentOrder();
    h.pos.addProduct(addedProd);
    h.pos.setSelectedPromo(
      PromoModel(
        id: 1,
        name: 'Promo Diskon Spesial Member VIP Counter Depan',
        promoType: 'diskon_persen',
        discountValue: 10,
        startDate: DateTime.now().subtract(const Duration(days: 1)),
        endDate: DateTime.now().add(const Duration(days: 7)),
      ),
    );
    h.pos.setCartDiscount(5000);

    return h;
  }

  Widget wrap(Widget child) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
        ChangeNotifierProvider<ProductProvider>.value(value: product),
        ChangeNotifierProvider<PosProvider>.value(value: pos),
        ChangeNotifierProvider<CashFlowProvider>.value(value: cashFlow),
        ChangeNotifierProvider<DebtProvider>.value(value: debt),
        ChangeNotifierProvider<AttendanceProvider>.value(value: attendance),
        ChangeNotifierProvider<SettingsProvider>.value(value: settings),
        ChangeNotifierProvider<CustomerProvider>.value(value: customer),
        ChangeNotifierProvider<PurchaseProvider>.value(value: purchase),
        ChangeNotifierProvider<PrinterProvider>.value(value: printer),
        ChangeNotifierProvider<ServiceOrderProvider>.value(value: service),
        ChangeNotifierProvider<PosServerProvider>.value(value: server),
      ],
      child: child,
    );
  }

  Future<void> disposeAll() async {
    await DatabaseHelper.instance.closeTestDatabase();
  }
}

Future<void> _pumpAndVerifyZeroOverflow(
  WidgetTester tester, {
  required _AdminTestHarness harness,
  required Widget screen,
  required _Vp vp,
  ThemeData? themeOverride,
  GlobalKey? boundaryKey,
}) async {
  final captured = <FlutterErrorDetails>[];
  final prev = FlutterError.onError;
  FlutterError.onError = (details) {
    captured.add(details);
  };

  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = vp.size;
  tester.view.viewInsets = FakeViewPadding(bottom: vp.bottomInset);

  try {
    Widget body = MediaQuery(
      data: MediaQueryData(
        size: vp.size,
        textScaler: TextScaler.linear(vp.textScale),
        viewInsets: EdgeInsets.only(bottom: vp.bottomInset),
      ),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: themeOverride ?? AppTheme.lightTheme,
        home: harness.wrap(screen),
      ),
    );
    if (boundaryKey != null) {
      body = RepaintBoundary(key: boundaryKey, child: body);
    }
    await tester.pumpWidget(body);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 120)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    final ex = tester.takeException();
    expect(ex, isNull, reason: 'Exception on ${vp.label}: $ex');

    final layoutErrors = captured.where((e) {
      final msg = e.exceptionAsString();
      return msg.contains('overflowed') ||
          msg.contains('RenderFlex') ||
          msg.contains('intrinsic dimensions');
    }).toList();
    expect(
      layoutErrors,
      isEmpty,
      reason: 'Layout/overflow error on ${vp.label}: ${layoutErrors.map((e) => e.exceptionAsString()).join('\n')}',
    );
  } finally {
    FlutterError.onError = prev;
    tester.view.reset();
  }
}

Future<void> _settleAndDisposeHarness(WidgetTester tester, _AdminTestHarness? harness) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
  if (harness != null) {
    await tester.runAsync(harness.disposeAll);
  }
}

Future<void> _scrollToFirst(
  WidgetTester tester,
  Finder target, {
  int index = 0,
  Offset step = const Offset(0, -200),
  int maxDrags = 15,
}) async {
  final scrollables = find.byType(Scrollable);
  for (var i = 0; i < maxDrags; i++) {
    final matching = target.hitTestable();
    if (matching.evaluate().length > index) {
      await tester.ensureVisible(matching.at(index));
      await tester.pump();
      return;
    }
    if (scrollables.evaluate().isEmpty) break;
    await tester.drag(scrollables.first, step);
    await tester.pump();
  }
  final all = target.evaluate();
  if (all.length > index) {
    await tester.ensureVisible(target.at(index));
    await tester.pump();
  }
}

Future<ThemeData> _loadScreenshotTheme(WidgetTester tester) async {
  await tester.runAsync(() async {
    final flutterExe = File(Platform.resolvedExecutable);
    final cacheRoot = Directory(
      '${flutterExe.parent.parent.parent.path}${Platform.pathSeparator}material_fonts',
    );
    if (cacheRoot.existsSync()) {
      for (final name in ['roboto-regular.ttf', 'roboto-medium.ttf', 'roboto-bold.ttf']) {
        final f = File('${cacheRoot.path}${Platform.pathSeparator}$name');
        if (f.existsSync()) {
          await ui.loadFontFromList(f.readAsBytesSync(), fontFamily: 'Roboto');
        }
      }
      final iconsFile = File('${cacheRoot.path}${Platform.pathSeparator}materialicons-regular.otf');
      if (iconsFile.existsSync()) {
        await ui.loadFontFromList(iconsFile.readAsBytesSync(), fontFamily: 'MaterialIcons');
      }
    }
  });
  final base = AppTheme.lightTheme;
  return base.copyWith(
    textTheme: ThemeData.light().textTheme.apply(fontFamily: 'Roboto'),
    primaryTextTheme: ThemeData.light().primaryTextTheme.apply(fontFamily: 'Roboto'),
    appBarTheme: base.appBarTheme.copyWith(
      titleTextStyle: base.appBarTheme.titleTextStyle?.copyWith(fontFamily: 'Roboto'),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: base.elevatedButtonTheme.style?.copyWith(
        textStyle: const WidgetStatePropertyAll(
          TextStyle(fontFamily: 'Roboto', fontWeight: FontWeight.bold, fontSize: 14),
        ),
      ),
    ),
  );
}

TransactionModel _sampleLongTransaction() => TransactionModel(
      id: 99,
      invoiceNumber: 'INV-20261127-9999-LONG',
      date: DateTime(2026, 11, 27, 14, 30),
      cashierId: 1,
      cashierName: 'Muhammad Abdurrahman Assidiq Counter Utama',
      customerName: 'Ibu Hj. Siti Fatimah Zahra Counter Grosir Cabang Mall',
      subtotal: 125000000,
      discountTotal: 1500000,
      taxAmount: 13585000,
      promoName: 'Promo Akhir Pekan Member VIP Counter Utama',
      grandTotal: 137085000,
      paymentMethod: 'transfer',
      creditUsed: 500000,
      amountPaid: 137085000,
      changeAmount: 0,
      items: [
        TransactionItemModel(
          productId: 1,
          productCode: 'PRD-001',
          productName: 'Kopi Susu Gula Aren Premium Kemasan Botol 1000ml Edisi Khusus',
          unitName: 'Karton',
          qty: 20,
          unitPrice: 6250000,
          subtotal: 125000000,
        ),
      ],
    );

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  setUpAll(() async {
    await DateHelper.ensureInitialized();
  });

  group('Admin POS Global Overflow Matrix (8 Viewports + Scales 1.0/1.2/1.5 + Keyboard)', () {
    testWidgets('Reported #1 MultiDeviceServerScreen renders zero overflow & switches long Dropdowns',
        (tester) async {
      final harness = await tester.runAsync(_AdminTestHarness.createOpenDbAndSeed);
      addTearDown(() => _settleAndDisposeHarness(tester, harness));

      for (final vp in [..._eightViewports, ..._stressViewports]) {
        await _pumpAndVerifyZeroOverflow(
          tester,
          harness: harness!,
          screen: MultiDeviceServerScreen(key: ValueKey('mds_${vp.label}')),
          vp: vp,
        );
      }

      // Interactive Dropdown selection for Laci Kasir & Printer Default at 320x640 s15
      await _pumpAndVerifyZeroOverflow(
        tester,
        harness: harness!,
        screen: const MultiDeviceServerScreen(key: ValueKey('mds_interactive')),
        vp: const _Vp('320x640_s15_dd', Size(320, 640), textScale: 1.5),
      );
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(320, 640);
      addTearDown(tester.view.reset);
      await tester.pump();

      final ddFinder = find.byType(DropdownButtonFormField<int?>);
      await _scrollToFirst(tester, ddFinder, index: 0);
      await tester.tap(ddFinder.at(0));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.textContaining('REG-UTAMA-02').last);
      await tester.pumpAndSettle();
      expect(harness.server.terminals.first.assignedRegisterId, isNotNull);

      await _scrollToFirst(tester, ddFinder, index: 1);
      await tester.tap(ddFinder.at(1));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.textContaining('LAN Counter Ekspres').last);
      await tester.pumpAndSettle();
      expect(harness.server.terminals.first.defaultPrinterId, harness.secondPrinterId);

      // Open Pairing Terminal Baru AlertDialog and open Laci Kas dropdown
      await _scrollToFirst(tester, find.text('Pairing Terminal Baru'), step: const Offset(0, 260), maxDrags: 25);
      await tester.tap(find.text('Pairing Terminal Baru').first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Batal'));
      await tester.pumpAndSettle();
    });

    testWidgets('ShiftScreen, SettingsScreen (+ Kelola Laci Kas dialog), ReceiptSettings & PrinterManagement',
        (tester) async {
      final harness = await tester.runAsync(_AdminTestHarness.createOpenDbAndSeed);
      addTearDown(() => _settleAndDisposeHarness(tester, harness));

      for (final vp in [..._eightViewports, _stressViewports[1], _stressViewports[3]]) {
        await _pumpAndVerifyZeroOverflow(
          tester,
          harness: harness!,
          screen: ShiftScreen(key: ValueKey('shift_${vp.label}')),
          vp: vp,
        );
        await _pumpAndVerifyZeroOverflow(
          tester,
          harness: harness,
          screen: SettingsScreen(key: ValueKey('set_${vp.label}')),
          vp: vp,
        );
        await _pumpAndVerifyZeroOverflow(
          tester,
          harness: harness,
          screen: ReceiptSettingsScreen(key: ValueKey('recset_${vp.label}')),
          vp: vp,
        );
        await _pumpAndVerifyZeroOverflow(
          tester,
          harness: harness,
          screen: PrinterManagementScreen(key: ValueKey('prn_${vp.label}')),
          vp: vp,
        );
      }

      // Open Kelola Laci Kas AlertDialog (uses LayoutBuilder inside AlertDialog) at 320x640 s15
      await _pumpAndVerifyZeroOverflow(
        tester,
        harness: harness!,
        screen: const SettingsScreen(key: ValueKey('set_dlg')),
        vp: const _Vp('320x640_s15_setdlg', Size(320, 640), textScale: 1.5),
      );
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(320, 640);
      addTearDown(tester.view.reset);
      await tester.pump();
      final manageRegistersFinder = find.textContaining('Kelola Laci & Assignment');
      await _scrollToFirst(tester, manageRegistersFinder, step: const Offset(0, -250), maxDrags: 25);
      await tester.tap(manageRegistersFinder.first);
      for (var i = 0; i < 8 && find.text('Tutup').evaluate().isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Tutup'));
      await tester.pumpAndSettle();

      // Open Tambah Printer AlertDialog (uses LayoutBuilder inside AlertDialog) at 320x640 s15
      await _pumpAndVerifyZeroOverflow(
        tester,
        harness: harness,
        screen: const PrinterManagementScreen(key: ValueKey('prn_dlg')),
        vp: const _Vp('320x640_s15_prndlg', Size(320, 640), textScale: 1.5),
      );
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(320, 640);
      await tester.pump();
      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(AlertDialog), findsOneWidget);
    });

    testWidgets('HomeScreen, PosScreen, PaymentDialog, ReceiptDialog & HeldOrdersDialog render zero overflow',
        (tester) async {
      final harness = await tester.runAsync(_AdminTestHarness.createOpenDbAndSeed);
      addTearDown(() => _settleAndDisposeHarness(tester, harness));

      for (final vp in [..._eightViewports, ..._stressViewports]) {
        await _pumpAndVerifyZeroOverflow(
          tester,
          harness: harness!,
          screen: LoginScreen(key: ValueKey('login_${vp.label}')),
          vp: vp,
        );
      }

      for (final vp in [_eightViewports[0], _eightViewports[1], _eightViewports[4], _eightViewports[7], _stressViewports[1]]) {
        await _pumpAndVerifyZeroOverflow(
          tester,
          harness: harness!,
          screen: HomeScreen(key: ValueKey('home_${vp.label}')),
          vp: vp,
        );
        await _pumpAndVerifyZeroOverflow(
          tester,
          harness: harness,
          screen: PosScreen(key: ValueKey('pos_${vp.label}')),
          vp: vp,
        );
        await _pumpAndVerifyZeroOverflow(
          tester,
          harness: harness,
          screen: Scaffold(body: PaymentDialog(key: ValueKey('pay_${vp.label}'))),
          vp: vp,
        );
        await _pumpAndVerifyZeroOverflow(
          tester,
          harness: harness,
          screen: Scaffold(
            body: ReceiptDialog(
              key: ValueKey('rec_${vp.label}'),
              transaction: _sampleLongTransaction(),
            ),
          ),
          vp: vp,
        );
        await _pumpAndVerifyZeroOverflow(
          tester,
          harness: harness,
          screen: Scaffold(body: HeldOrdersDialog(key: ValueKey('held_${vp.label}'))),
          vp: vp,
        );
      }
    });

    testWidgets('Feature Screens (DailyReport, CashFlow, Return, Purchase, Customer, Debt, Barcode, Employee, Service)',
        (tester) async {
      final harness = await tester.runAsync(_AdminTestHarness.createOpenDbAndSeed);
      addTearDown(() => _settleAndDisposeHarness(tester, harness));

      final narrowAndTablet = [
        _eightViewports[0],
        _eightViewports[1],
        _eightViewports[7],
        _stressViewports[1],
      ];
      for (final vp in narrowAndTablet) {
        await _pumpAndVerifyZeroOverflow(tester, harness: harness!, screen: DailyReportScreen(key: ValueKey('dr_${vp.label}')), vp: vp);
        await _pumpAndVerifyZeroOverflow(tester, harness: harness, screen: CashFlowScreen(key: ValueKey('cf_${vp.label}')), vp: vp);
        await _pumpAndVerifyZeroOverflow(tester, harness: harness, screen: ReturnScreen(key: ValueKey('ret_${vp.label}')), vp: vp);
        await _pumpAndVerifyZeroOverflow(tester, harness: harness, screen: PurchaseListScreen(key: ValueKey('pur_${vp.label}')), vp: vp);
        await _pumpAndVerifyZeroOverflow(tester, harness: harness, screen: CustomerListScreen(key: ValueKey('cust_${vp.label}')), vp: vp);
        await _pumpAndVerifyZeroOverflow(tester, harness: harness, screen: DebtListScreen(key: ValueKey('debt_${vp.label}')), vp: vp);
        await _pumpAndVerifyZeroOverflow(tester, harness: harness, screen: BarcodeGeneratorScreen(key: ValueKey('bc_${vp.label}')), vp: vp);
        await _pumpAndVerifyZeroOverflow(tester, harness: harness, screen: EmployeeManagementScreen(key: ValueKey('emp_${vp.label}')), vp: vp);
        await _pumpAndVerifyZeroOverflow(tester, harness: harness, screen: ProductFormScreen(key: ValueKey('pf_${vp.label}')), vp: vp);
        await _pumpAndVerifyZeroOverflow(tester, harness: harness, screen: PromoScreen(key: ValueKey('promo_${vp.label}')), vp: vp);
        await _pumpAndVerifyZeroOverflow(tester, harness: harness, screen: ServiceFormScreen(key: ValueKey('sf_${vp.label}')), vp: vp);
        await _pumpAndVerifyZeroOverflow(tester, harness: harness, screen: AttendanceHistoryScreen(key: ValueKey('att_${vp.label}')), vp: vp);
      }

      // Open DailyReport Pilih Bulan AlertDialog (uses LayoutBuilder inside AlertDialog) at 320x640 s15
      await _pumpAndVerifyZeroOverflow(
        tester,
        harness: harness!,
        screen: const DailyReportScreen(key: ValueKey('dr_dlg')),
        vp: const _Vp('320x640_s15_drdlg', Size(320, 640), textScale: 1.5),
      );
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(320, 640);
      addTearDown(tester.view.reset);
      await tester.pump();
      await tester.ensureVisible(find.text('Pilih Bulan'));
      await tester.pump();
      await tester.tap(find.text('Pilih Bulan'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(AlertDialog), findsOneWidget);
    });

    testWidgets('Export visual overflow verification screenshots for Admin POS App', (tester) async {
      if (!_exportScreenshots) return;

      final theme = await _loadScreenshotTheme(tester);
      final harness = await tester.runAsync(_AdminTestHarness.createOpenDbAndSeed);
      addTearDown(() => _settleAndDisposeHarness(tester, harness));

      final outDir = Directory('docs/screenshots/overflow_audit');
      if (!outDir.existsSync()) outDir.createSync(recursive: true);

      Future<void> capture(GlobalKey key, String filename) async {
        final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final img = await boundary.toImage(pixelRatio: 2.0);
          final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
          img.dispose();
          if (bytes != null) {
            File('${outDir.path}/$filename').writeAsBytesSync(bytes.buffer.asUint8List());
          }
        });
      }

      final k1 = GlobalKey();
      await _pumpAndVerifyZeroOverflow(
        tester,
        harness: harness!,
        screen: const MultiDeviceServerScreen(),
        vp: const _Vp('shot_mds_320', Size(320, 640)),
        themeOverride: theme,
        boundaryKey: k1,
      );
      await capture(k1, 'admin_multi_device_320x640.png');

      final k2 = GlobalKey();
      await _pumpAndVerifyZeroOverflow(
        tester,
        harness: harness,
        screen: const MultiDeviceServerScreen(),
        vp: const _Vp('shot_mds_360_s15', Size(360, 640), textScale: 1.5),
        themeOverride: theme,
        boundaryKey: k2,
      );
      await capture(k2, 'admin_multi_device_360x640_fs15.png');

      // Also capture Registered Terminal Card with Laci Kasir & Printer Default dropdowns at 360x640 & 800x1280
      final k2b = GlobalKey();
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(360, 640);
      await tester.pumpWidget(
        RepaintBoundary(
          key: k2b,
          child: MediaQuery(
            data: const MediaQueryData(
              size: Size(360, 640),
              textScaler: TextScaler.linear(1.5),
            ),
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: theme,
              home: harness.wrap(const MultiDeviceServerScreen()),
            ),
          ),
        ),
      );
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
      await _scrollToFirst(tester, find.text('Laci Kasir'), step: const Offset(0, -220));
      await tester.pumpAndSettle();
      await capture(k2b, 'admin_multi_device_terminal_card_360x640_fs15.png');

      final k2t = GlobalKey();
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(800, 1280);
      await tester.pumpWidget(
        RepaintBoundary(
          key: k2t,
          child: MediaQuery(
            data: const MediaQueryData(size: Size(800, 1280)),
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: theme,
              home: harness.wrap(const MultiDeviceServerScreen()),
            ),
          ),
        ),
      );
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pumpAndSettle();
      await capture(k2t, 'admin_multi_device_800x1280.png');
      tester.view.reset();

      final k3 = GlobalKey();
      await _pumpAndVerifyZeroOverflow(
        tester,
        harness: harness,
        screen: const HomeScreen(),
        vp: const _Vp('shot_home_320_s15', Size(320, 640), textScale: 1.5),
        themeOverride: theme,
        boundaryKey: k3,
      );
      await capture(k3, 'admin_home_320x640_fs15.png');

      final k4 = GlobalKey();
      await _pumpAndVerifyZeroOverflow(
        tester,
        harness: harness,
        screen: const ShiftScreen(),
        vp: const _Vp('shot_shift_320_s15', Size(320, 640), textScale: 1.5),
        themeOverride: theme,
        boundaryKey: k4,
      );
      await capture(k4, 'admin_shift_320x640_fs15.png');
    });
  });
}
