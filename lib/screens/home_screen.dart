import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../database/db_helper.dart';
import '../models/audit_log.dart';
import '../models/cash_flow.dart';
import '../models/service_order.dart';
import '../models/stock_opname.dart';
import '../models/transaction.dart';
import '../models/user.dart';
import '../providers/auth_provider.dart';
import '../providers/cash_flow_provider.dart';
import '../providers/debt_provider.dart';
import '../providers/product_provider.dart';
import '../providers/service_order_provider.dart';
import '../providers/settings_provider.dart';
import '../utils/app_theme.dart';
import '../utils/currency_format.dart';
import '../utils/date_format.dart';
import 'attendance/attendance_camera_screen.dart';
import 'attendance/attendance_history_screen.dart';
import 'cash_flow/cash_flow_screen.dart';
import 'cash_flow/shift_screen.dart';
import 'customers/customer_list_screen.dart';
import 'debts/debt_list_screen.dart';
import 'employees/employee_management_screen.dart';
import 'login_screen.dart';
import 'pos/pos_screen.dart';
import 'products/barcode_generator_screen.dart';
import 'products/product_form_screen.dart';
import 'products/product_list_screen.dart';
import 'promo/promo_screen.dart';
import 'purchases/purchase_list_screen.dart';
import 'reports/audit_log_screen.dart';
import 'reports/daily_report_screen.dart';
import 'returns/return_screen.dart';
import 'scanner/barcode_scanner_screen.dart';
import 'service/service_list_screen.dart';
import 'settings/printer_management_screen.dart';
import 'settings/receipt_settings_screen.dart';
import 'settings/settings_screen.dart';
import 'warehouse/expiry_tracking_screen.dart';
import 'warehouse/stock_opname_screen.dart';
import 'warehouse/warehouse_docs_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Map<String, dynamic> _analytics = {};
  bool _loadingAnalytics = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshAll();
    });
  }

  Future<void> _refreshAll() async {
    if (!mounted) return;
    await Future.wait([
      Provider.of<ProductProvider>(context, listen: false).loadProducts(),
      Provider.of<CashFlowProvider>(context, listen: false).checkOpenShift(),
      Provider.of<DebtProvider>(context, listen: false).loadDebts(),
      Provider.of<SettingsProvider>(context, listen: false).loadSettings(),
      Provider.of<ServiceOrderProvider>(context, listen: false).loadOrders(),
    ]);
    final analytics = await DatabaseHelper.instance.getDashboardAnalytics();
    if (mounted) {
      setState(() {
        _analytics = analytics;
        _loadingAnalytics = false;
      });
    }
  }

  Future<void> _pushAndRefresh(Widget screen) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    await _refreshAll();
  }

  Future<void> _quickScanBarcode() async {
    final code = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => const BarcodeScannerScreen(
          title: 'Scan Cepat Produk / Nota',
          helperText: 'Scan produk untuk lihat / tambah, atau QR Nota untuk retur',
          continuousMode: false,
        ),
      ),
    );
    if (code == null || code.isEmpty || !mounted) return;

    if (code.startsWith('TRX|')) {
      _pushAndRefresh(const ReturnScreen());
      return;
    }

    final prodProv = Provider.of<ProductProvider>(context, listen: false);
    final match = await prodProv.findProductByBarcode(code);
    if (!mounted) return;

    if (match != null) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(match.product.name),
          content: Text(
            'Kode: ${match.product.code}\n'
            'Harga: ${CurrencyHelper.format(match.product.sellingPrice)}\n'
            'Stok: ${match.product.stock.toInt()} ${match.product.baseUnit}',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Tutup')),
            if (Provider.of<AuthProvider>(context, listen: false).hasPermission(AppPermissions.manageProducts))
              OutlinedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _pushAndRefresh(ProductFormScreen(productToEdit: match.product));
                },
                child: const Text('Edit Produk'),
              ),
            if (Provider.of<AuthProvider>(context, listen: false).hasPermission(AppPermissions.accessPos))
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _pushAndRefresh(const PosScreen());
                },
                child: const Text('Buka Kasir'),
              ),
          ],
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Barcode "$code" belum terdaftar di katalog produk.')),
      );
    }
  }

  void _showNotificationsSheet(
    ProductProvider prod,
    DebtProvider debt,
    ServiceOrderProvider srv,
  ) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Pusat Notifikasi Operasional',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const Divider(),
              if (debt.overdueCount > 0)
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFFEE2E2),
                    child: Icon(Icons.warning_amber_rounded, color: AppTheme.accentRed),
                  ),
                  title: Text('${debt.overdueCount} Tagihan Kasbon Lewat Jatuh Tempo'),
                  subtitle: const Text('Ketuk untuk tagih via WhatsApp atau cetak Invoice'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _pushAndRefresh(const DebtListScreen());
                  },
                ),
              if (prod.expiringCount > 0)
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFFEF3C7),
                    child: Icon(Icons.event_busy_rounded, color: AppTheme.accentOrange),
                  ),
                  title: Text('${prod.expiringCount} Batch Produk Mendekati Kadaluarsa'),
                  subtitle: const Text('Periksa status kadaluarsa di gudang'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _pushAndRefresh(const ExpiryTrackingScreen());
                  },
                ),
              if (prod.lowStockCount > 0)
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFE0F2FE),
                    child: Icon(Icons.inventory_2_rounded, color: AppTheme.accentBlue),
                  ),
                  title: Text('${prod.lowStockCount} Produk Stok Menipis'),
                  subtitle: const Text('Lakukan pembelian restock supplier'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _pushAndRefresh(const ProductListScreen());
                  },
                ),
              if (srv.activeCount > 0)
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: AppTheme.primaryGreenSoft,
                    child: Icon(Icons.build_rounded, color: AppTheme.primaryGreen),
                  ),
                  title: Text('${srv.activeCount} Unit Servis Sedang Aktif'),
                  subtitle: const Text('Pantau progres pengerjaan teknisi'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _pushAndRefresh(const ServiceListScreen());
                  },
                ),
              if (debt.overdueCount == 0 &&
                  prod.expiringCount == 0 &&
                  prod.lowStockCount == 0 &&
                  srv.activeCount == 0)
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: Text('Semua operasional aman, tidak ada peringatan mendesak.')),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showProfileSheet(UserModel? user) {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: CircleAvatar(
                  radius: 26,
                  backgroundColor: AppTheme.primaryGreenSoft,
                  child: Text(
                    user?.name.isNotEmpty == true ? user!.name[0].toUpperCase() : 'U',
                    style: const TextStyle(color: AppTheme.primaryGreen, fontWeight: FontWeight.bold, fontSize: 20),
                  ),
                ),
                title: Text(user?.name ?? 'User', style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('${user?.roleDisplay ?? ""} • @${user?.username ?? ""}'),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.camera_front_rounded, color: AppTheme.accentPurple),
                title: const Text('Absensi Selfie (Anti-AI Liveness)'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pushAndRefresh(const AttendanceCameraScreen());
                },
              ),
              ListTile(
                leading: const Icon(Icons.logout_rounded, color: AppTheme.accentRed),
                title: const Text('Keluar / Ganti Akun Karyawan', style: TextStyle(color: AppTheme.accentRed)),
                onTap: () {
                  Navigator.pop(ctx);
                  auth.logout();
                  Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final cashFlow = Provider.of<CashFlowProvider>(context);
    final productProv = Provider.of<ProductProvider>(context);
    final debtProv = Provider.of<DebtProvider>(context);
    final settings = Provider.of<SettingsProvider>(context);
    final srvProv = Provider.of<ServiceOrderProvider>(context);

    final user = auth.currentUser;
    final alertCount = debtProv.overdueCount + productProv.lowStockCount;
    final logoFile = settings.logoPath.isNotEmpty ? File(settings.logoPath) : null;
    final hasLogo = logoFile != null && logoFile.existsSync();
    final isTablet = AppBreakpoints.isTablet(context);

    return Scaffold(
      backgroundColor: AppTheme.lightGreyBg,
      appBar: AppBar(
        toolbarHeight: 66,
        titleSpacing: 14,
        title: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
              ),
              clipBehavior: Clip.antiAlias,
              child: hasLogo
                  ? Image.file(logoFile, fit: BoxFit.contain)
                  : const Icon(Icons.storefront_rounded, color: AppTheme.primaryGreen),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    settings.storeName,
                    style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold, color: Colors.white),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${settings.branchName} • ${user?.name ?? "User"} (${user?.roleDisplay ?? ""})',
                    style: const TextStyle(fontSize: 11, color: Colors.white70),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.notifications_none_rounded),
                tooltip: 'Notifikasi',
                onPressed: () => _showNotificationsSheet(productProv, debtProv, srvProv),
              ),
              if (alertCount > 0)
                Positioned(
                  top: 10,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(color: AppTheme.accentRed, shape: BoxShape.circle),
                    child: Text(
                      '$alertCount',
                      style: const TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.account_circle_outlined),
            tooltip: 'Profil Karyawan',
            onPressed: () => _showProfileSheet(user),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshAll,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1200),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. Welcome Card
                  _buildWelcomeCard(context, settings, user, cashFlow, auth),
                  const SizedBox(height: 16),

                  // 2. Statistics Grid
                  _buildStatisticsSection(auth, cashFlow, productProv),
                  const SizedBox(height: 18),

                  // 3. Quick Actions
                  const Text(
                    'Aksi Cepat Operasional',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                  ),
                  const SizedBox(height: 10),
                  _buildQuickActions(context, auth, settings, srvProv),
                  const SizedBox(height: 20),

                  // 4. Desktop/Tablet Split: Modules + Recent Activity Side-by-Side
                  if (isTablet)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 3,
                          child: _buildAllModulesSection(context, auth, cashFlow, debtProv, productProv, settings),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          flex: 2,
                          child: _buildRecentActivityCard(auth),
                        ),
                      ],
                    )
                  else ...[
                    _buildAllModulesSection(context, auth, cashFlow, debtProv, productProv, settings),
                    const SizedBox(height: 20),
                    _buildRecentActivityCard(auth),
                  ],
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWelcomeCard(
    BuildContext context,
    SettingsProvider settings,
    UserModel? user,
    CashFlowProvider cashFlow,
    AuthProvider auth,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppTheme.darkBg, Color(0xFF0F766E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryGreen.withValues(alpha: 0.22),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 12,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      settings.businessType.label,
                      style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () => _pushAndRefresh(const ShiftScreen()),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: cashFlow.isShiftOpen ? AppTheme.success : AppTheme.accentOrange,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            cashFlow.isShiftOpen ? Icons.lock_open_rounded : Icons.lock_rounded,
                            size: 11,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            cashFlow.isShiftOpen ? 'Shift Terbuka' : 'Shift Tertutup',
                            style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                '${DateHelper.greetingByTime()}, ${user?.name ?? "Tim"}!',
                style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 3),
              Text(
                '${DateHelper.formatReadable(DateTime.now())} • ${settings.storeName}',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
          if (auth.hasPermission(AppPermissions.accessPos))
            ElevatedButton.icon(
              onPressed: () {
                if (!cashFlow.isShiftOpen) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Info: Shift kasir belum dibuka. Buka shift agar saldo laci tercatat.'),
                      backgroundColor: AppTheme.accentOrange,
                    ),
                  );
                }
                _pushAndRefresh(const PosScreen());
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppTheme.primaryGreen,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
              ),
              icon: const Icon(Icons.point_of_sale_rounded),
              label: const Text('BUKA KASIR (POS)'),
            ),
        ],
      ),
    );
  }

  Widget _buildStatisticsSection(
    AuthProvider auth,
    CashFlowProvider cashFlow,
    ProductProvider productProv,
  ) {
    final todayRev = (_analytics['todayRevenue'] as num?)?.toDouble() ?? 0.0;
    final todayTx = (_analytics['todayTxCount'] as num?)?.toInt() ?? 0;
    final totalProducts = (_analytics['totalProducts'] as num?)?.toInt() ?? productProv.allProducts.length;
    final todayProfit = (_analytics['todayGrossProfit'] as num?)?.toDouble() ?? 0.0;
    final todayExpense = (_analytics['todayExpense'] as num?)?.toDouble() ?? 0.0;
    final cashSales = (_analytics['todayCashSales'] as num?)?.toDouble() ?? 0.0;
    final qrisSales = (_analytics['todayQrisSales'] as num?)?.toDouble() ?? 0.0;
    final cashDrawerBalance = cashFlow.isShiftOpen ? cashFlow.currentShift!.expectedCash : 0.0;

    final cards = <Widget>[
      _StatTile(
        title: 'Omzet Hari Ini',
        value: _loadingAnalytics ? '...' : CurrencyHelper.formatCompact(todayRev),
        subtitle: '$todayTx Transaksi',
        icon: Icons.payments_rounded,
        color: AppTheme.primaryGreen,
      ),
      _StatTile(
        title: 'Saldo Kas Laci',
        value: cashFlow.isShiftOpen ? CurrencyHelper.formatCompact(cashDrawerBalance) : 'Tutup',
        subtitle: cashFlow.isShiftOpen ? 'Shift ${cashFlow.currentShift!.cashierName}' : 'Ketuk Shift',
        icon: Icons.account_balance_wallet_rounded,
        color: Colors.teal,
      ),
      _StatTile(
        title: 'Tunai vs QRIS',
        value: _loadingAnalytics ? '...' : CurrencyHelper.formatCompact(cashSales),
        subtitle: 'QRIS: ${CurrencyHelper.formatCompact(qrisSales)}',
        icon: Icons.qr_code_2_rounded,
        color: AppTheme.accentBlue,
      ),
      _StatTile(
        title: 'Total Produk',
        value: '$totalProducts Item',
        subtitle: '${productProv.lowStockCount} stok menipis',
        icon: Icons.inventory_2_rounded,
        color: AppTheme.accentIndigo,
      ),
      _StatTile(
        title: 'Pengeluaran Hari Ini',
        value: _loadingAnalytics ? '...' : CurrencyHelper.formatCompact(todayExpense),
        subtitle: 'Arus kas keluar',
        icon: Icons.arrow_circle_up_rounded,
        color: AppTheme.accentOrange,
      ),
      if (auth.hasPermission(AppPermissions.viewProfit))
        _StatTile(
          title: 'Laba Kotor Hari Ini',
          value: _loadingAnalytics ? '...' : CurrencyHelper.formatCompact(todayProfit),
          subtitle: 'Estimasi margin',
          icon: Icons.trending_up_rounded,
          color: AppTheme.success,
        ),
    ];

    final crossCount = AppBreakpoints.isTablet(context) ? 3 : 2;
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: crossCount,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: AppBreakpoints.isTablet(context) ? 2.1 : 1.75,
      children: cards,
    );
  }

  Widget _buildQuickActions(
    BuildContext context,
    AuthProvider auth,
    SettingsProvider settings,
    ServiceOrderProvider srvProv,
  ) {
    final actions = <_QuickActionItem>[
      if (auth.hasPermission(AppPermissions.accessPos))
        _QuickActionItem(
          label: 'Kasir',
          icon: Icons.point_of_sale_rounded,
          color: AppTheme.primaryGreen,
          onTap: () => _pushAndRefresh(const PosScreen()),
        ),
      if (auth.hasPermission(AppPermissions.manageProducts))
        _QuickActionItem(
          label: 'Tambah Produk',
          icon: Icons.add_box_rounded,
          color: AppTheme.accentBlue,
          onTap: () => _pushAndRefresh(const ProductFormScreen()),
        ),
      _QuickActionItem(
        label: 'Scan Barcode',
        icon: Icons.qr_code_scanner_rounded,
        color: AppTheme.accentIndigo,
        onTap: _quickScanBarcode,
      ),
      if (auth.hasPermission(AppPermissions.manageService))
        _QuickActionItem(
          label: 'Servis',
          badge: srvProv.activeCount > 0 ? '${srvProv.activeCount}' : null,
          icon: Icons.build_circle_rounded,
          color: settings.businessType.prioritizeService ? AppTheme.accentOrange : Colors.blueGrey,
          onTap: () => _pushAndRefresh(const ServiceListScreen()),
        ),
      if (auth.hasPermission(AppPermissions.manageCustomers))
        _QuickActionItem(
          label: 'Pelanggan',
          icon: Icons.people_alt_rounded,
          color: Colors.teal,
          onTap: () => _pushAndRefresh(const CustomerListScreen()),
        ),
      if (auth.hasPermission(AppPermissions.managePurchases))
        _QuickActionItem(
          label: 'Pembelian',
          icon: Icons.add_shopping_cart_rounded,
          color: Colors.deepPurple,
          onTap: () => _pushAndRefresh(const PurchaseListScreen()),
        ),
      if (auth.hasPermission(AppPermissions.manageProducts) || auth.hasPermission(AppPermissions.manageStock))
        _QuickActionItem(
          label: 'Stok',
          icon: Icons.inventory_rounded,
          color: Colors.brown,
          onTap: () => _pushAndRefresh(const ProductListScreen()),
        ),
      if (auth.hasPermission(AppPermissions.viewReports))
        _QuickActionItem(
          label: 'Laporan',
          icon: Icons.analytics_rounded,
          color: AppTheme.success,
          onTap: () => _pushAndRefresh(const DailyReportScreen()),
        ),
    ];

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: AppBreakpoints.quickActionGridCount(context),
      crossAxisSpacing: 8,
      mainAxisSpacing: 8,
      childAspectRatio: 0.96,
      children: actions,
    );
  }

  Widget _buildAllModulesSection(
    BuildContext context,
    AuthProvider auth,
    CashFlowProvider cashFlow,
    DebtProvider debtProv,
    ProductProvider productProv,
    SettingsProvider settings,
  ) {
    final tiles = <_ModuleItem>[
      _ModuleItem(
        title: 'Shift Kasir',
        subtitle: cashFlow.isShiftOpen ? 'Tutup Shift' : 'Buka Shift',
        icon: Icons.access_time_filled_rounded,
        color: Colors.teal,
        onTap: () => _pushAndRefresh(const ShiftScreen()),
      ),
      if (auth.hasPermission(AppPermissions.accessPos) || auth.hasPermission(AppPermissions.voidTransaction))
        _ModuleItem(
          title: 'Retur Produk',
          subtitle: 'Scan QR Nota',
          icon: Icons.replay_circle_filled_rounded,
          color: Colors.indigo,
          onTap: () => _pushAndRefresh(const ReturnScreen()),
        ),
      if (auth.hasPermission(AppPermissions.manageCustomers))
        _ModuleItem(
          title: 'Buku Kasbon',
          subtitle: '${debtProv.unpaidDebts.length} Tagihan',
          badge: debtProv.overdueCount > 0 ? '${debtProv.overdueCount}' : null,
          icon: Icons.receipt_long_rounded,
          color: debtProv.overdueCount > 0 ? AppTheme.accentRed : Colors.blueGrey,
          onTap: () => _pushAndRefresh(const DebtListScreen()),
        ),
      _ModuleItem(
        title: 'Arus Kas Laci',
        subtitle: 'Masuk / Keluar',
        icon: Icons.account_balance_wallet_rounded,
        color: Colors.deepOrange,
        onTap: () => _pushAndRefresh(const CashFlowScreen()),
      ),
      if (auth.hasPermission(AppPermissions.applyDiscount))
        _ModuleItem(
          title: 'Diskon & Promo',
          subtitle: 'Beli X Gratis Y',
          icon: Icons.discount_rounded,
          color: Colors.pink,
          onTap: () => _pushAndRefresh(const PromoScreen()),
        ),
      if (auth.hasPermission(AppPermissions.manageStock))
        _ModuleItem(
          title: 'Stok Opname',
          subtitle: 'Audit Fisik',
          icon: Icons.checklist_rounded,
          color: AppTheme.accentIndigo,
          onTap: () => _pushAndRefresh(const StockOpnameScreen()),
        ),
      if (auth.hasPermission(AppPermissions.manageStock))
        _ModuleItem(
          title: 'Kadaluarsa',
          subtitle: '${productProv.expiringCount} Batch',
          icon: Icons.event_busy_rounded,
          color: Colors.amber.shade800,
          onTap: () => _pushAndRefresh(const ExpiryTrackingScreen()),
        ),
      _ModuleItem(
        title: 'Surat Jalan',
        subtitle: 'Kirim / Gudang',
        icon: Icons.local_shipping_rounded,
        color: Colors.deepPurple,
        onTap: () => _pushAndRefresh(const WarehouseDocsScreen()),
      ),
      _ModuleItem(
        title: 'Cetak Label',
        subtitle: 'Barcode & QR',
        icon: Icons.qr_code_2_rounded,
        color: Colors.cyan.shade700,
        onTap: () => _pushAndRefresh(const BarcodeGeneratorScreen()),
      ),
      _ModuleItem(
        title: 'Absensi Selfie',
        subtitle: 'Anti-AI Liveness',
        icon: Icons.camera_front_rounded,
        color: AppTheme.accentPurple,
        onTap: () => _pushAndRefresh(const AttendanceCameraScreen()),
      ),
      _ModuleItem(
        title: 'Disiplin Staf',
        subtitle: 'Rekap Mingguan',
        icon: Icons.badge_rounded,
        color: Colors.brown,
        onTap: () => _pushAndRefresh(const AttendanceHistoryScreen()),
      ),
      if (auth.hasPermission(AppPermissions.managePrinters))
        _ModuleItem(
          title: 'Printer',
          subtitle: 'Thermal/Laser/DM',
          icon: Icons.print_rounded,
          color: Colors.blueGrey.shade700,
          onTap: () => _pushAndRefresh(const PrinterManagementScreen()),
        ),
      if (auth.hasPermission(AppPermissions.managePrinters))
        _ModuleItem(
          title: 'Desain Struk',
          subtitle: 'Template & Copy',
          icon: Icons.receipt_rounded,
          color: AppTheme.primaryGreen,
          onTap: () => _pushAndRefresh(const ReceiptSettingsScreen()),
        ),
      if (auth.hasPermission(AppPermissions.manageEmployees))
        _ModuleItem(
          title: 'Karyawan',
          subtitle: 'Role & Hak Akses',
          icon: Icons.manage_accounts_rounded,
          color: Colors.purple,
          onTap: () => _pushAndRefresh(const EmployeeManagementScreen()),
        ),
      if (auth.hasPermission(AppPermissions.viewReports))
        _ModuleItem(
          title: 'Log Audit',
          subtitle: 'Riwayat Keamanan',
          icon: Icons.security_rounded,
          color: AppTheme.accentRed,
          onTap: () => _pushAndRefresh(const AuditLogScreen()),
        ),
      if (auth.hasPermission(AppPermissions.manageStoreSettings))
        _ModuleItem(
          title: 'Pengaturan Toko',
          subtitle: 'Profil & Backup',
          icon: Icons.settings_rounded,
          color: AppTheme.darkBg,
          onTap: () => _pushAndRefresh(const SettingsScreen()),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Modul Operasional & Manajemen',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textDark),
        ),
        const SizedBox(height: 10),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: AppBreakpoints.isTablet(context) ? 4 : 3,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: 1.0,
          children: tiles,
        ),
      ],
    );
  }

  Widget _buildRecentActivityCard(AuthProvider auth) {
    final txs = (_analytics['recentTransactions'] as List<TransactionModel>?) ?? [];
    final srvs = (_analytics['recentServices'] as List<ServiceOrderModel>?) ?? [];
    final opnames = (_analytics['recentOpnames'] as List<StockOpnameModel>?) ?? [];
    final flows = (_analytics['recentCashFlows'] as List<CashFlowModel>?) ?? [];
    final audits = (_analytics['recentAudits'] as List<AuditLogModel>?) ?? [];

    final feed = <Map<String, dynamic>>[
      for (final t in txs.take(3))
        {
          'time': t.date,
          'icon': Icons.receipt_long_rounded,
          'color': AppTheme.primaryGreen,
          'title': 'Penjualan ${t.invoiceNumber}',
          'sub': '${CurrencyHelper.format(t.grandTotal)} • ${t.paymentMethod.toUpperCase()} (${t.cashierName})',
        },
      for (final s in srvs.take(3))
        {
          'time': s.updatedAt,
          'icon': Icons.build_rounded,
          'color': AppTheme.accentOrange,
          'title': 'Servis ${s.ticketNumber} (${ServiceStatus.label(s.status)})',
          'sub': '${s.deviceType} ${s.brand} ${s.model} • ${s.customerName}',
        },
      for (final o in opnames.take(2))
        {
          'time': o.date,
          'icon': Icons.checklist_rounded,
          'color': AppTheme.accentBlue,
          'title': 'Stok Opname: ${o.productName}',
          'sub': 'Sistem ${o.systemStock.toInt()} → Fisik ${o.physicalStock.toInt()} (${o.auditedBy})',
        },
      for (final f in flows.take(2))
        {
          'time': f.date,
          'icon': f.isIn ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
          'color': f.isIn ? AppTheme.success : AppTheme.accentRed,
          'title': '${f.isIn ? "Kas Masuk" : "Kas Keluar"}: ${f.category}',
          'sub': '${CurrencyHelper.format(f.amount)} • ${f.cashierName}',
        },
      if (auth.hasPermission(AppPermissions.viewReports))
        for (final a in audits.take(2))
          {
            'time': a.timestamp,
            'icon': Icons.security_rounded,
            'color': AppTheme.accentPurple,
            'title': a.actionDisplay,
            'sub': '${a.userName} • ${a.details}',
          },
    ];

    feed.sort((a, b) => (b['time'] as DateTime).compareTo(a['time'] as DateTime));

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.history_rounded, size: 18, color: AppTheme.primaryGreen),
              SizedBox(width: 6),
              Text('Aktivitas Terbaru', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            ],
          ),
          const Divider(height: 16),
          if (feed.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: Text('Belum ada aktivitas tercatat hari ini.', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
              ),
            )
          else
            ...feed.take(8).map((item) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 15,
                        backgroundColor: (item['color'] as Color).withValues(alpha: 0.12),
                        child: Icon(item['icon'] as IconData, size: 16, color: item['color'] as Color),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item['title'] as String,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              item['sub'] as String,
                              style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        DateHelper.formatTime(item['time'] as DateTime),
                        style: const TextStyle(fontSize: 10, color: AppTheme.textMuted),
                      ),
                    ],
                  ),
                )),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;

  const _StatTile({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: AppTheme.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Icon(icon, size: 15, color: color),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 11, color: AppTheme.textMuted, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          Text(
            value,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color),
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 10, color: AppTheme.textMuted),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _QuickActionItem extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final String? badge;
  final VoidCallback onTap;

  const _QuickActionItem({
    required this.label,
    required this.icon,
    required this.color,
    this.badge,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.borderLight),
          ),
          child: Stack(
            children: [
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, color: color, size: 22),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      label,
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (badge != null)
                Positioned(
                  right: 0,
                  top: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(color: AppTheme.accentRed, borderRadius: BorderRadius.circular(8)),
                    child: Text(badge!, style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModuleItem extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final String? badge;
  final VoidCallback onTap;

  const _ModuleItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    this.badge,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.borderLight),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, color: color, size: 20),
                  ),
                  if (badge != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: AppTheme.accentRed, borderRadius: BorderRadius.circular(8)),
                      child: Text(badge!, style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                    ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 1),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 10, color: AppTheme.textMuted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
