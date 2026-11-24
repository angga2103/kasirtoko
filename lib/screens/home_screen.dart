import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/product_provider.dart';
import '../providers/cash_flow_provider.dart';
import '../providers/debt_provider.dart';
import '../providers/settings_provider.dart';
import '../utils/app_theme.dart';
import '../utils/currency_format.dart';
import 'login_screen.dart';
import 'pos/pos_screen.dart';
import 'returns/return_screen.dart';
import 'cash_flow/shift_screen.dart';
import 'cash_flow/cash_flow_screen.dart';
import 'products/product_list_screen.dart';
import 'products/barcode_generator_screen.dart';
import 'debts/debt_list_screen.dart';
import 'warehouse/stock_opname_screen.dart';
import 'warehouse/warehouse_docs_screen.dart';
import 'warehouse/expiry_tracking_screen.dart';
import 'attendance/attendance_camera_screen.dart';
import 'attendance/attendance_history_screen.dart';
import 'promo/promo_screen.dart';
import 'reports/daily_report_screen.dart';
import 'reports/audit_log_screen.dart';
import 'settings/settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<ProductProvider>(context, listen: false).loadProducts();
      Provider.of<CashFlowProvider>(context, listen: false).checkOpenShift();
      Provider.of<DebtProvider>(context, listen: false).loadDebts();
      Provider.of<SettingsProvider>(context, listen: false).loadSettings();
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final cashFlow = Provider.of<CashFlowProvider>(context);
    final product = Provider.of<ProductProvider>(context);
    final debt = Provider.of<DebtProvider>(context);
    final settings = Provider.of<SettingsProvider>(context);

    final user = auth.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(settings.storeName, style: const TextStyle(fontSize: 16)),
            Text(
              '${user?.name ?? "User"} • ${user?.roleDisplay ?? ""}',
              style: const TextStyle(fontSize: 11, color: Colors.white70),
            ),
          ],
        ),
        actions: [
          // Shift status badge
          Container(
            margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            decoration: BoxDecoration(
              color: cashFlow.isShiftOpen ? AppTheme.success : AppTheme.accentOrange,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  cashFlow.isShiftOpen ? Icons.lock_open_rounded : Icons.lock_rounded,
                  size: 13,
                  color: Colors.white,
                ),
                const SizedBox(width: 4),
                Text(
                  cashFlow.isShiftOpen ? 'Shift Terbuka' : 'Shift Tertutup',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'Keluar Akun',
            onPressed: () {
              auth.logout();
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              );
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await product.loadProducts();
          await cashFlow.checkOpenShift();
          await debt.loadDebts();
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Quick Stats Header Cards
              _buildStatsRow(cashFlow, debt, product),
              const SizedBox(height: 16),

              // 2. Big Highlight POS Button
              _buildBigPosCard(context, cashFlow),
              const SizedBox(height: 20),

              // 3. Operational Section Title
              const Text(
                'Menu Operasional & Kasir',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textDark),
              ),
              const SizedBox(height: 10),

              // Operational Grid
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 3,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 0.95,
                children: [
                  _buildMenuCard(
                    context,
                    title: 'Retur Produk',
                    subtitle: 'Scan QR Nota',
                    icon: Icons.replay_circle_filled_rounded,
                    color: Colors.indigo,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ReturnScreen()),
                    ),
                  ),
                  _buildMenuCard(
                    context,
                    title: 'Shift Kasir',
                    subtitle: cashFlow.isShiftOpen ? 'Tutup Shift' : 'Buka Shift',
                    icon: Icons.point_of_sale_rounded,
                    color: Colors.teal,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ShiftScreen()),
                    ),
                  ),
                  _buildMenuCard(
                    context,
                    title: 'Buku Kasbon',
                    subtitle: '${debt.unpaidDebts.length} Tagihan',
                    icon: Icons.receipt_long_rounded,
                    color: debt.overdueCount > 0 ? AppTheme.accentRed : Colors.blueGrey,
                    badgeText: debt.overdueCount > 0 ? '${debt.overdueCount} Lewat' : null,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const DebtListScreen()),
                    ),
                  ),
                  _buildMenuCard(
                    context,
                    title: 'Arus Kas Laci',
                    subtitle: 'Keluar / Masuk',
                    icon: Icons.account_balance_wallet_rounded,
                    color: Colors.deepOrange,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const CashFlowScreen()),
                    ),
                  ),
                  _buildMenuCard(
                    context,
                    title: 'Absensi Selfie',
                    subtitle: 'Anti-AI Liveness',
                    icon: Icons.camera_front_rounded,
                    color: Colors.purple,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const AttendanceCameraScreen()),
                    ),
                  ),
                  _buildMenuCard(
                    context,
                    title: 'Diskon & Promo',
                    subtitle: 'Beli X Gratis Y',
                    icon: Icons.discount_rounded,
                    color: Colors.pink,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const PromoScreen()),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // 4. Warehouse & Master Data Section
              const Text(
                'Gudang, Stok & Label',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textDark),
              ),
              const SizedBox(height: 10),

              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 3,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 0.95,
                children: [
                  _buildMenuCard(
                    context,
                    title: 'Master Produk',
                    subtitle: 'Multi Satuan',
                    icon: Icons.inventory_2_rounded,
                    color: Colors.blue,
                    badgeText: product.lowStockCount > 0 ? '${product.lowStockCount} Menipis' : null,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ProductListScreen()),
                    ),
                  ),
                  _buildMenuCard(
                    context,
                    title: 'Cetak Barcode',
                    subtitle: 'Stiker Thermal',
                    icon: Icons.qr_code_2_rounded,
                    color: Colors.cyan,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const BarcodeGeneratorScreen()),
                    ),
                  ),
                  _buildMenuCard(
                    context,
                    title: 'Kadaluarsa',
                    subtitle: '${product.expiringCount} Batch',
                    icon: Icons.event_busy_rounded,
                    color: Colors.amber.shade800,
                    badgeText: product.expiringCount > 0 ? '${product.expiringCount} Batch' : null,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ExpiryTrackingScreen()),
                    ),
                  ),
                  _buildMenuCard(
                    context,
                    title: 'Stok Opname',
                    subtitle: 'Cek Selisih Fisik',
                    icon: Icons.checklist_rounded,
                    color: Colors.indigoAccent,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const StockOpnameScreen()),
                    ),
                  ),
                  _buildMenuCard(
                    context,
                    title: 'Surat Jalan',
                    subtitle: 'Ambil / Kirim',
                    icon: Icons.local_shipping_rounded,
                    color: Colors.deepPurple,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const WarehouseDocsScreen()),
                    ),
                  ),
                  _buildMenuCard(
                    context,
                    title: 'Disiplin Staf',
                    subtitle: 'Laporan Mingguan',
                    icon: Icons.badge_rounded,
                    color: Colors.brown,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const AttendanceHistoryScreen()),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // 5. Reports & Admin Management Section
              if (auth.isOwner || auth.isSupervisor) ...[
                const Text(
                  'Laporan & Keamanan Admin',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _buildMenuCard(
                        context,
                        title: 'Laporan Penjualan',
                        subtitle: 'Kirim ke WhatsApp Owner',
                        icon: Icons.analytics_rounded,
                        color: AppTheme.primaryGreen,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const DailyReportScreen()),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildMenuCard(
                        context,
                        title: 'Log Audit Karyawan',
                        subtitle: 'Jejak Void & Buka Laci',
                        icon: Icons.security_rounded,
                        color: Colors.red.shade700,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const AuditLogScreen()),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _buildMenuCard(
                  context,
                  title: 'Pengaturan & Backup Google Drive / WhatsApp',
                  subtitle: 'Printer 58/80mm • Nama Toko • Cadangkan Database',
                  icon: Icons.settings_backup_restore_rounded,
                  color: Colors.blueGrey.shade800,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatsRow(CashFlowProvider cashFlow, DebtProvider debt, ProductProvider product) {
    return Row(
      children: [
        Expanded(
          child: _buildStatMiniCard(
            title: 'Kas di Laci',
            value: cashFlow.isShiftOpen
                ? CurrencyHelper.formatCompact(cashFlow.currentShift!.expectedCash)
                : 'Tutup',
            color: Colors.teal,
            icon: Icons.account_balance_wallet_rounded,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildStatMiniCard(
            title: 'Piutang Jatuh Tempo',
            value: debt.overdueCount > 0 ? '${debt.overdueCount} Nota' : '0 Nota',
            color: debt.overdueCount > 0 ? AppTheme.accentRed : Colors.blueGrey,
            icon: Icons.warning_amber_rounded,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildStatMiniCard(
            title: 'Kadaluarsa',
            value: '${product.expiringCount} Batch',
            color: product.expiringCount > 0 ? AppTheme.accentOrange : Colors.green,
            icon: Icons.timer_rounded,
          ),
        ),
      ],
    );
  }

  Widget _buildStatMiniCard({
    required String title,
    required String value,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 10, color: AppTheme.textMuted),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBigPosCard(BuildContext context, CashFlowProvider cashFlow) {
    return InkWell(
      onTap: () {
        if (!cashFlow.isShiftOpen) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Peringatan: Shift belum dibuka. Buka shift kasir terlebih dahulu.'),
              backgroundColor: AppTheme.accentOrange,
            ),
          );
        }
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const PosScreen()),
        );
      },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF0F766E), Color(0xFF14B8A6)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0F766E).withOpacity(0.3),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.point_of_sale_rounded, color: Colors.white, size: 36),
            ),
            const SizedBox(width: 16),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'POINT OF SALE (KASIR)',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                  SizedBox(height: 3),
                  Text(
                    'Scan Barcode • Multi Satuan • Harga Bertingkat',
                    style: TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    String? badgeText,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.black.withOpacity(0.06)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 22),
                ),
                if (badgeText != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.accentRed,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      badgeText,
                      style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textDark,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
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
    );
  }
}

extension ColorExtension on Colors {
  static Color emeraldGreenAccent() => const Color(0xFF10B981);
}
