import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:kasirtoko/database/db_helper.dart';
import 'package:kasirtoko/models/customer.dart';
import 'package:kasirtoko/models/product.dart';
import 'package:kasirtoko/models/shift.dart';
import 'package:kasirtoko/models/store_profile.dart';
import 'package:kasirtoko/models/user.dart';
import 'package:kasirtoko/models/warehouse_doc.dart';
import 'package:kasirtoko/providers/attendance_provider.dart';
import 'package:kasirtoko/providers/auth_provider.dart';
import 'package:kasirtoko/providers/cash_flow_provider.dart';
import 'package:kasirtoko/providers/customer_provider.dart';
import 'package:kasirtoko/providers/debt_provider.dart';
import 'package:kasirtoko/providers/pos_provider.dart';
import 'package:kasirtoko/providers/printer_provider.dart';
import 'package:kasirtoko/providers/product_provider.dart';
import 'package:kasirtoko/providers/purchase_provider.dart';
import 'package:kasirtoko/providers/settings_provider.dart';
import 'package:kasirtoko/screens/cash_flow/cash_flow_screen.dart';
import 'package:kasirtoko/screens/pos/payment_dialog.dart';
import 'package:kasirtoko/screens/pos/pos_screen.dart';
import 'package:kasirtoko/screens/products/barcode_generator_screen.dart';
import 'package:kasirtoko/screens/purchases/purchase_list_screen.dart';
import 'package:kasirtoko/screens/reports/audit_log_screen.dart';
import 'package:kasirtoko/screens/reports/daily_report_screen.dart';
import 'package:kasirtoko/screens/warehouse/stock_opname_screen.dart';
import 'package:kasirtoko/screens/warehouse/warehouse_docs_screen.dart';
import 'package:kasirtoko/utils/app_theme.dart';
import 'package:kasirtoko/utils/date_format.dart';
import 'package:kasirtoko/widgets/quantity_stepper.dart';

class FakeProductProvider extends ProductProvider {
  final List<ProductModel> _seed;
  FakeProductProvider(this._seed);

  @override
  List<ProductModel> get allProducts => _seed;

  @override
  List<ProductModel> get products => _seed;

  @override
  Future<void> loadProducts({String? query, String? category}) async {}
}

class FakePosProvider extends PosProvider {
  @override
  Future<void> loadPromos() async {}
}

class FakeSettingsProvider extends SettingsProvider {
  @override
  BusinessType get businessType => BusinessType.general;

  @override
  Future<void> loadSettings() async {}
}

class FakeAuthProvider extends AuthProvider {
  final UserModel _user = UserModel(id: 1, name: 'Owner Test', role: AppRoles.owner);

  @override
  UserModel? get currentUser => _user;

  @override
  List<UserModel> get users => [_user];

  @override
  bool get isLoggedIn => true;

  @override
  bool hasPermission(String permissionKey) => true;

  @override
  Future<void> loadUsers({bool includeInactive = true}) async {}

  @override
  Future<void> logAction(
    String actionType,
    String details, {
    String? module,
    String objectId = '',
    String beforeValue = '',
    String afterValue = '',
  }) async {}
}

class FakeCustomerProvider extends CustomerProvider {
  @override
  List<CustomerModel> get customers => [
        CustomerModel(id: 1, name: 'Toko Mawar', phone: '081234567', address: 'Jl. Melati No. 1'),
      ];

  @override
  Future<void> loadCustomers({String? query}) async {}
}

class FakeCashFlowProvider extends CashFlowProvider {
  final ShiftModel _openShift = ShiftModel(
    id: 1,
    cashierId: 1,
    cashierName: 'Owner Test',
    startTime: DateTime(2026, 11, 25, 8, 0),
    startingCash: 200000,
    status: 'open',
  );

  @override
  ShiftModel? get currentShift => _openShift;

  @override
  bool get isShiftOpen => true;

  @override
  Future<void> checkOpenShift() async {}
}

class FakePrinterProvider extends PrinterProvider {
  @override
  Future<void> loadPrinters() async {}
}

class FakeDebtProvider extends DebtProvider {
  @override
  Future<void> loadDebts() async {}
}

class FakePurchaseProvider extends PurchaseProvider {
  @override
  Future<void> loadPurchases() async {}
}

class FakeAttendanceProvider extends AttendanceProvider {
  @override
  Future<void> loadAttendances() async {}
}

Widget _wrapWithProviders(Widget child, {PosProvider? posOverride}) {
  final seedProducts = [
    ProductModel(id: 1, code: 'P-01', name: 'Kopi Susu', sellingPrice: 15000, stock: 25),
    ProductModel(id: 2, code: 'P-02', name: 'Roti Bakar', sellingPrice: 12000, stock: 10),
  ];

  return MultiProvider(
    providers: [
      ChangeNotifierProvider<ProductProvider>(create: (_) => FakeProductProvider(seedProducts)),
      ChangeNotifierProvider<PosProvider>(create: (_) => posOverride ?? FakePosProvider()),
      ChangeNotifierProvider<SettingsProvider>(create: (_) => FakeSettingsProvider()),
      ChangeNotifierProvider<AuthProvider>(create: (_) => FakeAuthProvider()),
      ChangeNotifierProvider<CustomerProvider>(create: (_) => FakeCustomerProvider()),
      ChangeNotifierProvider<CashFlowProvider>(create: (_) => FakeCashFlowProvider()),
      ChangeNotifierProvider<PrinterProvider>(create: (_) => FakePrinterProvider()),
      ChangeNotifierProvider<DebtProvider>(create: (_) => FakeDebtProvider()),
      ChangeNotifierProvider<PurchaseProvider>(create: (_) => FakePurchaseProvider()),
      ChangeNotifierProvider<AttendanceProvider>(create: (_) => FakeAttendanceProvider()),
    ],
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      home: child,
    ),
  );
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  setUpAll(() async {
    await DateHelper.ensureInitialized();
  });

  group('Responsive layout, inline controls & keyboard safety', () {
    Future<void> pumpAtViewport(
      WidgetTester tester,
      Widget widget,
      Size size, {
      double bottomInset = 0,
      PosProvider? posOverride,
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      if (bottomInset > 0) {
        tester.view.viewInsets = FakeViewPadding(bottom: bottomInset);
      } else {
        tester.view.viewInsets = FakeViewPadding.zero;
      }
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_wrapWithProviders(widget, posOverride: posOverride));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }

    Future<void> pumpDbScreenAtViewport(
      WidgetTester tester,
      Widget widget,
      Size size,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      tester.view.viewInsets = FakeViewPadding.zero;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_wrapWithProviders(widget));
      await tester.pump();
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 180)));
      await tester.pump();
      expect(tester.takeException(), isNull);
    }

    testWidgets('PosScreen renders cleanly & inline grid stepper updates cart on 360x640 with keyboard up', (tester) async {
      final pos = FakePosProvider();
      await pumpAtViewport(tester, const PosScreen(), const Size(360, 640), bottomInset: 260, posOverride: pos);
      expect(find.text('Kopi Susu'), findsOneWidget);
      expect(find.text('BAYAR'), findsOneWidget);

      await pumpAtViewport(
        tester,
        const PosScreen(key: ValueKey('pos_tap_phone')),
        const Size(360, 640),
        posOverride: pos,
      );
      final addIcons = find.byIcon(Icons.add_rounded);
      expect(addIcons, findsWidgets);
      await tester.ensureVisible(addIcons.first);
      await tester.tap(addIcons.first);
      await tester.pumpAndSettle();
      expect(pos.totalUnitsCount, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('PosScreen renders cleanly on 412x915 standard phone', (tester) async {
      await pumpAtViewport(tester, const PosScreen(), const Size(412, 915));
      expect(find.text('Kopi Susu'), findsOneWidget);
      expect(find.text('Keranjang (0 Jenis)'), findsNothing);
    });

    testWidgets('PosScreen switches to dual-pane layout on tablet 800x1280 and 1280x800', (tester) async {
      await pumpAtViewport(tester, const PosScreen(), const Size(800, 1280));
      expect(find.text('Keranjang (0 Jenis)'), findsOneWidget);

      await pumpAtViewport(tester, const PosScreen(), const Size(1280, 800));
      expect(find.text('Keranjang (0 Jenis)'), findsOneWidget);
      expect(find.text('PROSES PEMBAYARAN'), findsOneWidget);
    });

    testWidgets('PaymentDialog renders dynamic quick cash nominals & Kasbon member picker on 360x640 with keyboard up', (tester) async {
      final pos = FakePosProvider();
      pos.addProduct(ProductModel(id: 1, code: 'P-01', name: 'Kopi', sellingPrice: 49000, stock: 10));
      await pumpAtViewport(
        tester,
        const Scaffold(body: PaymentDialog()),
        const Size(360, 640),
        bottomInset: 240,
        posOverride: pos,
      );
      expect(find.text('Rp 50.000'), findsOneWidget);
      expect(find.text('Rp 100.000'), findsOneWidget);
      expect(find.text('Rp 150.000'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('WarehouseDocFormScreen displays editable qty clearly without overflow on 360x640 and 1280x800', (tester) async {
      final doc = WarehouseDocModel(
        id: 1,
        docNumber: 'SJ-202611-1010',
        docType: 'surat_jalan',
        date: DateTime(2026, 11, 25),
        recipientName: 'Toko Mawar',
        itemsJson: '[{"product_id":1,"name":"Beras Super","qty":10,"unit":"Sak","note":""}]',
      );

      await pumpAtViewport(
        tester,
        WarehouseDocFormScreen(docToEdit: doc, onSaved: () {}),
        const Size(360, 640),
        bottomInset: 240,
      );
      expect(find.text('10'), findsOneWidget);
      expect(tester.getSize(find.byType(QuantityStepper).first).width, greaterThanOrEqualTo(110));

      final stepperPlus = find.descendant(
        of: find.byType(QuantityStepper).first,
        matching: find.byIcon(Icons.add_rounded),
      );
      await tester.ensureVisible(stepperPlus);
      await tester.tap(stepperPlus);
      await tester.pumpAndSettle();
      expect(find.text('11'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await pumpAtViewport(
        tester,
        WarehouseDocFormScreen(key: const ValueKey('tablet_doc_form'), docToEdit: doc, onSaved: () {}),
        const Size(1280, 800),
      );
      expect(find.text('10'), findsOneWidget);
    });

    testWidgets('BarcodeGeneratorScreen & PurchaseListScreen render cleanly at 360x640 and 1280x800', (tester) async {
      for (final size in [const Size(360, 640), const Size(1280, 800)]) {
        await pumpAtViewport(tester, const BarcodeGeneratorScreen(), size);
        await pumpAtViewport(tester, const PurchaseListScreen(), size);
      }
    });

    testWidgets('DB-backed screens (StockOpname, AuditLog, DailyReport, CashFlow) render cleanly at 360x640 and 1280x800', (tester) async {
      await tester.runAsync(() => DatabaseHelper.instance.openTestDatabase(path: inMemoryDatabasePath));
      try {
        for (final size in [const Size(360, 640), const Size(1280, 800)]) {
          await pumpDbScreenAtViewport(tester, const StockOpnameScreen(), size);
          await pumpDbScreenAtViewport(tester, const AuditLogScreen(), size);
          await pumpDbScreenAtViewport(tester, const DailyReportScreen(), size);
          await pumpDbScreenAtViewport(tester, const CashFlowScreen(), size);
        }
      } finally {
        await tester.runAsync(() => DatabaseHelper.instance.closeTestDatabase());
      }
    });
  });
}
