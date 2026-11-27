import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'providers/attendance_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/backup_provider.dart';
import 'providers/cash_flow_provider.dart';
import 'providers/customer_provider.dart';
import 'providers/debt_provider.dart';
import 'providers/pos_provider.dart';
import 'providers/printer_provider.dart';
import 'providers/product_provider.dart';
import 'providers/purchase_provider.dart';
import 'providers/server_provider.dart';
import 'providers/service_order_provider.dart';
import 'providers/settings_provider.dart';

import 'screens/login_screen.dart';
import 'utils/app_theme.dart';
import 'utils/date_format.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DateHelper.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  runApp(const KasirTokoApp());
}

class KasirTokoApp extends StatelessWidget {
  const KasirTokoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()..loadUsers()),
        ChangeNotifierProvider(create: (_) => ProductProvider()..loadProducts()),
        ChangeNotifierProvider(create: (_) => PosProvider()..loadPromos()),
        ChangeNotifierProvider(create: (_) => CashFlowProvider()..checkOpenShift()),
        ChangeNotifierProvider(create: (_) => DebtProvider()..loadDebts()),
        ChangeNotifierProvider(create: (_) => AttendanceProvider()..loadAttendances()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()..loadSettings()),
        ChangeNotifierProvider(create: (_) => CustomerProvider()..loadCustomers()),
        ChangeNotifierProvider(create: (_) => PurchaseProvider()..loadPurchases()),
        ChangeNotifierProvider(create: (_) => PrinterProvider()..loadPrinters()),
        ChangeNotifierProvider(create: (_) => ServiceOrderProvider()..loadOrders()),
        ChangeNotifierProvider(create: (_) => PosServerProvider()..initialize()),
        ChangeNotifierProvider(create: (_) => BackupProvider()..initialize()),
      ],
      child: MaterialApp(
        title: 'KasirToko Admin POS',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: const LoginScreen(),
      ),
    );
  }
}
