import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../database/db_helper.dart';
import '../../models/product.dart';
import '../../models/purchase.dart';
import '../../models/customer_debt.dart';
import '../../models/transaction.dart';
import '../../models/user.dart';
import '../../providers/auth_provider.dart';
import '../../providers/cash_flow_provider.dart';
import '../../providers/product_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/document_service.dart';
import '../../services/excel_service.dart';
import '../../services/whatsapp_service.dart';
import '../../utils/app_theme.dart';
import '../../utils/currency_format.dart';
import '../../utils/date_format.dart';
import '../pos/receipt_dialog.dart';

class DailyReportScreen extends StatefulWidget {
  const DailyReportScreen({super.key});

  @override
  State<DailyReportScreen> createState() => _DailyReportScreenState();
}

class _DailyReportScreenState extends State<DailyReportScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchCtrl = TextEditingController();

  String _preset = 'today'; // today | yesterday | week | month | specific_month | specific_year | custom
  late DateTime _startDate;
  late DateTime _endDate;
  String _periodLabel = 'Hari Ini';

  Map<String, dynamic> _analytics = {};
  bool _isLoading = true;
  int _txVisibleLimit = 25;
  String _productSubTab = 'topSelling'; // topSelling | leastSelling | unsold | topRevenue | topProfit | lowStock

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    final now = DateTime.now();
    _startDate = DateTime(now.year, now.month, now.day);
    _endDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
    _periodLabel = 'Hari Ini (${DateHelper.formatShort(_startDate)})';
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final res = await DatabaseHelper.instance.getBusinessAnalyticsReport(_startDate, _endDate);
    if (!mounted) return;
    setState(() {
      _analytics = res;
      _txVisibleLimit = 25;
      _isLoading = false;
    });
  }

  Future<void> _selectPreset(String preset) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    if (preset == 'custom') {
      final range = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2020),
        lastDate: DateTime(now.year + 1),
        initialDateRange: DateTimeRange(start: _startDate, end: _endDate.isAfter(today) ? today : _endDate),
      );
      if (range == null) return;
      _preset = 'custom';
      _startDate = DateTime(range.start.year, range.start.month, range.start.day);
      _endDate = DateTime(range.end.year, range.end.month, range.end.day, 23, 59, 59);
      _periodLabel = '${DateHelper.formatShort(_startDate)} s/d ${DateHelper.formatShort(_endDate)}';
    } else if (preset == 'specific_month') {
      int chosenYear = now.year;
      int chosenMonth = now.month;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (_, setDState) => AlertDialog(
            title: const Text('Pilih Bulan & Tahun'),
            content: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: chosenMonth,
                    decoration: const InputDecoration(labelText: 'Bulan'),
                    items: List.generate(12, (i) => i + 1)
                        .map((m) => DropdownMenuItem(value: m, child: Text(_monthName(m))))
                        .toList(),
                    onChanged: (v) => setDState(() => chosenMonth = v ?? chosenMonth),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: chosenYear,
                    decoration: const InputDecoration(labelText: 'Tahun'),
                    items: List.generate(7, (i) => now.year - 5 + i)
                        .map((y) => DropdownMenuItem(value: y, child: Text('$y')))
                        .toList(),
                    onChanged: (v) => setDState(() => chosenYear = v ?? chosenYear),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
              ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Terapkan')),
            ],
          ),
        ),
      );
      if (confirmed != true) return;
      _preset = 'specific_month';
      _startDate = DateTime(chosenYear, chosenMonth, 1);
      final nextMonth = DateTime(chosenYear, chosenMonth + 1, 1);
      _endDate = nextMonth.subtract(const Duration(milliseconds: 1));
      _periodLabel = '${_monthName(chosenMonth)} $chosenYear';
    } else if (preset == 'specific_year') {
      int chosenYear = now.year;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (_, setDState) => AlertDialog(
            title: const Text('Pilih Tahun Laporan'),
            content: DropdownButtonFormField<int>(
              value: chosenYear,
              decoration: const InputDecoration(labelText: 'Tahun'),
              items: List.generate(7, (i) => now.year - 5 + i)
                  .map((y) => DropdownMenuItem(value: y, child: Text('$y')))
                  .toList(),
              onChanged: (v) => setDState(() => chosenYear = v ?? chosenYear),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
              ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Terapkan')),
            ],
          ),
        ),
      );
      if (confirmed != true) return;
      _preset = 'specific_year';
      _startDate = DateTime(chosenYear, 1, 1);
      _endDate = DateTime(chosenYear, 12, 31, 23, 59, 59);
      _periodLabel = 'Tahun $chosenYear';
    } else {
      _preset = preset;
      switch (preset) {
        case 'today':
          _startDate = today;
          _endDate = DateTime(today.year, today.month, today.day, 23, 59, 59);
          _periodLabel = 'Hari Ini (${DateHelper.formatShort(today)})';
          break;
        case 'yesterday':
          final y = today.subtract(const Duration(days: 1));
          _startDate = y;
          _endDate = DateTime(y.year, y.month, y.day, 23, 59, 59);
          _periodLabel = 'Kemarin (${DateHelper.formatShort(y)})';
          break;
        case 'week':
          final monday = today.subtract(Duration(days: today.weekday - 1));
          _startDate = monday;
          _endDate = DateTime(today.year, today.month, today.day, 23, 59, 59);
          _periodLabel = 'Minggu Ini (${DateHelper.formatShort(monday)} - ${DateHelper.formatShort(today)})';
          break;
        case 'month':
          _startDate = DateTime(today.year, today.month, 1);
          _endDate = DateTime(today.year, today.month, today.day, 23, 59, 59);
          _periodLabel = 'Bulan ${_monthName(today.month)} ${today.year}';
          break;
      }
    }
    await _loadData();
  }

  String _monthName(int m) {
    const names = [
      'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
      'Jul', 'Agt', 'Sep', 'Okt', 'Nov', 'Des',
    ];
    return names[(m - 1).clamp(0, 11)];
  }

  Future<void> _showTransactionActions(TransactionModel t) async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final cashFlow = Provider.of<CashFlowProvider>(context, listen: false);
    final productProv = Provider.of<ProductProvider>(context, listen: false);
    final isVoid = t.status == 'voided' || t.status == 'void';

    await showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(t.invoiceNumber, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('${DateHelper.formatFull(t.date)} • ${CurrencyHelper.format(t.grandTotal)}'),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.receipt_long_rounded, color: AppTheme.primaryGreen),
                title: const Text('Lihat & Cetak Ulang Struk'),
                onTap: () {
                  Navigator.pop(ctx);
                  showDialog(
                    context: context,
                    builder: (_) => ReceiptDialog(transaction: t, isReprint: true),
                  );
                },
              ),
              if (!isVoid && auth.hasPermission(AppPermissions.voidTransaction))
                ListTile(
                  leading: const Icon(Icons.cancel_rounded, color: AppTheme.accentRed),
                  title: const Text(
                    'Batalkan Transaksi (VOID)',
                    style: TextStyle(color: AppTheme.accentRed, fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text('Mengembalikan sisa stok & menyesuaikan saldo shift / kasbon'),
                  onTap: () async {
                    Navigator.pop(ctx);
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (dCtx) => AlertDialog(
                        title: const Text('Batalkan Transaksi?'),
                        content: Text(
                          'Nota ${t.invoiceNumber} senilai ${CurrencyHelper.format(t.grandTotal)} akan dibatalkan dan sisa stok barang yang belum diretur akan dikembalikan.',
                        ),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(dCtx, false), child: const Text('Batal')),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accentRed),
                            onPressed: () => Navigator.pop(dCtx, true),
                            child: const Text('YA, VOID'),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true && t.id != null) {
                      try {
                        await DatabaseHelper.instance.voidTransaction(
                          t.id!,
                          shiftId: cashFlow.currentShift?.id,
                        );
                        await auth.logAction(
                          'void_transaksi',
                          'Membatalkan nota ${t.invoiceNumber} senilai ${CurrencyHelper.format(t.grandTotal)}',
                          module: 'transaksi',
                          objectId: t.invoiceNumber,
                        );
                        await productProv.loadProducts();
                        await cashFlow.checkOpenShift();
                        await _loadData();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Transaksi ${t.invoiceNumber} berhasil di-VOID.')),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('$e'), backgroundColor: AppTheme.accentRed),
                          );
                        }
                      }
                    }
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
    final settings = Provider.of<SettingsProvider>(context);
    final auth = Provider.of<AuthProvider>(context);
    final canViewProfit = auth.hasPermission(AppPermissions.viewProfit);

    final validTx = (_analytics['transactions'] as List<dynamic>? ?? []).cast<TransactionModel>();
    final sales = Map<String, dynamic>.from(_analytics['sales'] as Map? ?? {});
    final profit = Map<String, dynamic>.from(_analytics['profit'] as Map? ?? {});

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pusat Analitik Bisnis'),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_rounded),
            tooltip: 'Ekspor PDF Analitik',
            onPressed: _isLoading
                ? null
                : () async {
                    await DocumentService.printAnalyticsReportPdf(
                      storeName: settings.storeName,
                      storeAddress: settings.storeAddress,
                      periodLabel: _periodLabel,
                      analytics: _analytics,
                      includeProfit: canViewProfit,
                      logoPath: settings.logoPath,
                    );
                  },
          ),
          IconButton(
            icon: const Icon(Icons.file_download_rounded),
            tooltip: 'Ekspor Excel Transaksi',
            onPressed: (_isLoading || validTx.isEmpty)
                ? null
                : () async {
                    final path = await ExcelService.exportTransactionsToExcel(validTx);
                    if (path.isNotEmpty && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Laporan transaksi diekspor ke Excel!'), backgroundColor: AppTheme.success),
                      );
                    }
                  },
          ),
          IconButton(
            icon: const Icon(Icons.share_rounded),
            tooltip: 'Kirim Ringkasan ke WA Admin',
            onPressed: _isLoading
                ? null
                : () async {
                    final totalRev = (sales['totalRevenue'] as num?)?.toDouble() ?? 0.0;
                    final trxCount = (sales['trxCount'] as int?) ?? 0;
                    final gp = (profit['grossProfit'] as num?)?.toDouble() ?? 0.0;
                    final ok = await WhatsAppService.sendDailySummaryReport(
                      ownerPhone: settings.ownerPhone,
                      storeName: settings.storeName,
                      reportedBy: auth.currentUser?.name ?? 'Kasir',
                      totalTransactions: trxCount,
                      totalSales: totalRev,
                      totalGrossProfit: canViewProfit ? gp : null,
                    );
                    if (!ok && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Nomor WhatsApp Admin/Owner belum diatur di Pengaturan Toko.')),
                      );
                    }
                  },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: AppTheme.accentOrange,
          tabs: const [
            Tab(text: 'Penjualan'),
            Tab(text: 'Produk'),
            Tab(text: 'Pelanggan'),
            Tab(text: 'Supplier'),
            Tab(text: 'Keuntungan'),
          ],
        ),
      ),
      body: Column(
        children: [
          // Period Filter Strip
          Container(
            width: double.infinity,
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _presetChip('today', 'Hari Ini'),
                      const SizedBox(width: 6),
                      _presetChip('yesterday', 'Kemarin'),
                      const SizedBox(width: 6),
                      _presetChip('week', 'Minggu Ini'),
                      const SizedBox(width: 6),
                      _presetChip('month', 'Bulan Ini'),
                      const SizedBox(width: 6),
                      _presetChip('specific_month', 'Pilih Bulan'),
                      const SizedBox(width: 6),
                      _presetChip('specific_year', 'Pilih Tahun'),
                      const SizedBox(width: 6),
                      _presetChip('custom', 'Rentang Kustom'),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.date_range_rounded, size: 15, color: AppTheme.primaryGreen),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        'Periode: $_periodLabel',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.primaryGreen),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildSalesTab(sales, validTx),
                      _buildProductsTab(canViewProfit),
                      _buildCustomersTab(),
                      _buildSuppliersTab(),
                      _buildProfitTab(profit, canViewProfit),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSalesTab(Map<String, dynamic> sales, List<TransactionModel> validTx) {
    final isWide = MediaQuery.sizeOf(context).width >= AppBreakpoints.tablet;
    final totalRev = (sales['totalRevenue'] as num?)?.toDouble() ?? 0.0;
    final netSales = (sales['netSales'] as num?)?.toDouble() ?? 0.0;
    final trxCount = (sales['trxCount'] as int?) ?? 0;
    final itemsSold = (sales['totalItemsSold'] as num?)?.toDouble() ?? 0.0;
    final avgVal = (sales['avgTrxValue'] as num?)?.toDouble() ?? 0.0;

    final cash = (sales['cashSales'] as num?)?.toDouble() ?? 0.0;
    final transfer = (sales['transferSales'] as num?)?.toDouble() ?? 0.0;
    final qris = (sales['qrisSales'] as num?)?.toDouble() ?? 0.0;
    final kasbon = (sales['kasbonSales'] as num?)?.toDouble() ?? 0.0;
    final dailySeries = (sales['dailySeries'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();

    final q = _searchCtrl.text.trim().toLowerCase();
    final filteredTx = q.isEmpty
        ? validTx
        : validTx
            .where((t) =>
                t.invoiceNumber.toLowerCase().contains(q) ||
                t.customerName.toLowerCase().contains(q) ||
                t.cashierName.toLowerCase().contains(q))
            .toList();
    final shownTx = filteredTx.take(_txVisibleLimit).toList();

    return RefreshIndicator(
      onRefresh: _loadData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(14),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1020),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GridView.count(
                  crossAxisCount: isWide ? 4 : 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: isWide ? 1.85 : 1.75,
                  children: [
                    _kpiCard('Omzet Kotor', CurrencyHelper.format(totalRev), Icons.payments_rounded, AppTheme.primaryGreen),
                    _kpiCard('Penjualan Bersih', CurrencyHelper.format(netSales), Icons.verified_rounded, Colors.teal),
                    _kpiCard('Transaksi Valid', '$trxCount Nota', Icons.receipt_long_rounded, AppTheme.accentBlue),
                    _kpiCard('Rata-rata / Nota', '${CurrencyHelper.format(avgVal)} • ${itemsSold.toInt()} item', Icons.insights_rounded, Colors.indigo),
                  ],
                ),
                const SizedBox(height: 14),

                // Sales Trend Bar Visualization
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: AppTheme.cardDecoration(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Grafik Tren Penjualan Harian', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                      const SizedBox(height: 12),
                      if (dailySeries.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 18),
                          child: Center(child: Text('Belum ada penjualan pada periode ini.', style: TextStyle(color: AppTheme.textMuted, fontSize: 12))),
                        )
                      else
                        SizedBox(
                          height: 145,
                          child: _DailySalesBarChart(series: dailySeries),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Payment Methods Breakdown
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: AppTheme.cardDecoration(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Komposisi Metode Pembayaran', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                      const SizedBox(height: 10),
                      _methodProgress('Tunai', cash, totalRev, AppTheme.primaryGreen),
                      _methodProgress('Transfer Bank', transfer, totalRev, Colors.indigo),
                      _methodProgress('QRIS', qris, totalRev, AppTheme.accentBlue),
                      _methodProgress('Kasbon / Tempo', kasbon, totalRev, AppTheme.accentOrange),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Search & Paginated Transactions List
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Rincian Nota (${filteredTx.length})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _searchCtrl,
                  decoration: const InputDecoration(
                    hintText: 'Cari nomor nota, pelanggan, atau kasir...',
                    isDense: true,
                    prefixIcon: Icon(Icons.search_rounded, size: 19),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 8),

                if (shownTx.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(child: Text('Tidak ada transaksi yang cocok.', style: TextStyle(color: AppTheme.textMuted))),
                  )
                else ...[
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: shownTx.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (_, idx) {
                      final t = shownTx[idx];
                      return Card(
                        child: ListTile(
                          onTap: () => _showTransactionActions(t),
                          leading: CircleAvatar(
                            backgroundColor: AppTheme.primaryGreenSoft,
                            child: Text(
                              t.paymentMethod.substring(0, 1).toUpperCase(),
                              style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryGreen),
                            ),
                          ),
                          title: Text('${t.invoiceNumber} • ${t.customerName}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          subtitle: Text(
                            '${DateHelper.formatFull(t.date)} • Kasir: ${t.cashierName} • ${t.paymentMethod.toUpperCase()}',
                            style: const TextStyle(fontSize: 11),
                          ),
                          trailing: Text(
                            CurrencyHelper.format(t.grandTotal),
                            style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryGreen),
                          ),
                        ),
                      );
                    },
                  ),
                  if (filteredTx.length > _txVisibleLimit)
                    Center(
                      child: OutlinedButton(
                        onPressed: () => setState(() => _txVisibleLimit += 25),
                        child: Text('Muat Lebih Banyak (${filteredTx.length - _txVisibleLimit} tersisa)'),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProductsTab(bool canViewProfit) {
    final products = Map<String, dynamic>.from(_analytics['products'] as Map? ?? {});
    final topSelling = (products['topSelling'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    final leastSelling = (products['leastSelling'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    final unsold = (products['unsold'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    final topRevenue = (products['topRevenue'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    final topProfit = (products['topProfit'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    final lowStock = (products['lowStock'] as List<dynamic>? ?? []).cast<ProductModel>();
    final categories = (products['categories'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1020),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Category breakdown
              if (categories.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: AppTheme.cardDecoration(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Penjualan per Kategori', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                      const SizedBox(height: 8),
                      ...categories.take(8).map((c) {
                        final rev = (c['revenue'] as num).toDouble();
                        final qty = (c['qtySold'] as num).toDouble();
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Expanded(child: Text('${c['category']} (${qty.toInt()} unit)', style: const TextStyle(fontSize: 12.5))),
                              Text(CurrencyHelper.format(rev), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: AppTheme.primaryGreen)),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // Sub-filter chips
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _prodChip('topSelling', 'Terlaris (${topSelling.length})'),
                    const SizedBox(width: 6),
                    _prodChip('leastSelling', 'Paling Sepi (${leastSelling.length})'),
                    const SizedBox(width: 6),
                    _prodChip('unsold', 'Belum Laku (${unsold.length})'),
                    const SizedBox(width: 6),
                    _prodChip('topRevenue', 'Omzet Tertinggi'),
                    if (canViewProfit) ...[
                      const SizedBox(width: 6),
                      _prodChip('topProfit', 'Profit Tertinggi'),
                    ],
                    const SizedBox(width: 6),
                    _prodChip('lowStock', 'Stok Menipis (${lowStock.length})'),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              if (_productSubTab == 'lowStock')
                _buildLowStockList(lowStock)
              else if (_productSubTab == 'unsold')
                _buildUnsoldList(unsold)
              else
                _buildProductMetricList(
                  _productSubTab == 'leastSelling'
                      ? leastSelling
                      : (_productSubTab == 'topRevenue'
                          ? topRevenue
                          : (_productSubTab == 'topProfit' && canViewProfit ? topProfit : topSelling)),
                  canViewProfit: canViewProfit,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProductMetricList(List<Map<String, dynamic>> rows, {required bool canViewProfit}) {
    if (rows.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: Text('Belum ada penjualan produk pada periode ini.', style: TextStyle(color: AppTheme.textMuted))),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: rows.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (_, idx) {
        final r = rows[idx];
        final qty = (r['qtySold'] as num).toDouble();
        final rev = (r['revenue'] as num).toDouble();
        final prof = (r['profit'] as num).toDouble();
        return Card(
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: AppTheme.primaryGreenSoft,
              child: Text('#${idx + 1}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.primaryGreen)),
            ),
            title: Text('${r['name']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
            subtitle: Text(
              'SKU: ${r['code']} • Kategori: ${r['category']} • Terjual: ${qty == qty.truncateToDouble() ? qty.toInt() : qty.toStringAsFixed(1)} ${r['unit']}',
              style: const TextStyle(fontSize: 11),
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(CurrencyHelper.format(rev), style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryGreen, fontSize: 12.5)),
                if (canViewProfit)
                  Text('Laba: ${CurrencyHelper.format(prof)}', style: const TextStyle(fontSize: 10.5, color: Colors.teal)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildUnsoldList(List<Map<String, dynamic>> unsold) {
    if (unsold.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: Text('Semua produk aktif tercatat memiliki penjualan pada periode ini!')),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: unsold.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (_, idx) {
        final r = unsold[idx];
        return Card(
          child: ListTile(
            leading: const CircleAvatar(backgroundColor: Colors.grey, child: Icon(Icons.hourglass_empty_rounded, color: Colors.white, size: 18)),
            title: Text('${r['name']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            subtitle: Text('SKU: ${r['code']} • Kategori: ${r['category']} • Sisa Stok: ${(r['stock'] as num).toInt()} ${r['unit']}', style: const TextStyle(fontSize: 11)),
            trailing: Text(CurrencyHelper.format((r['sellingPrice'] as num).toDouble()), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
          ),
        );
      },
    );
  }

  Widget _buildLowStockList(List<ProductModel> lowStock) {
    if (lowStock.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: Text('Tidak ada produk berstok menipis saat ini.')),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: lowStock.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (_, idx) {
        final p = lowStock[idx];
        return Card(
          child: ListTile(
            leading: const CircleAvatar(backgroundColor: AppTheme.accentRedSoft, child: Icon(Icons.warning_amber_rounded, color: AppTheme.accentRed, size: 19)),
            title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            subtitle: Text('SKU: ${p.code} • Min. Alert: ${p.minStockAlert.toInt()} ${p.baseUnit}', style: const TextStyle(fontSize: 11)),
            trailing: Text('Sisa ${p.stock.toInt()} ${p.baseUnit}', style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.accentRed)),
          ),
        );
      },
    );
  }

  Widget _buildCustomersTab() {
    final cust = Map<String, dynamic>.from(_analytics['customers'] as Map? ?? {});
    final bySpent = (cust['bySpent'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    final byFreq = (cust['byFreq'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    final activeDebts = (cust['activeDebts'] as List<dynamic>? ?? []).cast<CustomerDebtModel>();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1020),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Pelanggan Nilai Belanja Tertinggi', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 8),
              if (bySpent.isEmpty)
                const Text('Belum ada data belanja pelanggan pada periode ini.', style: TextStyle(color: AppTheme.textMuted))
              else
                ...bySpent.take(15).map((c) => Card(
                      margin: const EdgeInsets.only(bottom: 6),
                      child: ListTile(
                        leading: const CircleAvatar(backgroundColor: AppTheme.primaryGreenSoft, child: Icon(Icons.person_rounded, color: AppTheme.primaryGreen)),
                        title: Text('${c['name']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        subtitle: Text('Frekuensi: ${c['freq']}x • Nota Terbesar: ${CurrencyHelper.format((c['maxTrx'] as num).toDouble())}', style: const TextStyle(fontSize: 11)),
                        trailing: Text(CurrencyHelper.format((c['totalSpent'] as num).toDouble()), style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryGreen)),
                      ),
                    )),
              const SizedBox(height: 16),
              const Text('Pelanggan Paling Sering Berkunjung', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 8),
              if (byFreq.isEmpty)
                const Text('Belum ada data kunjungan pelanggan.', style: TextStyle(color: AppTheme.textMuted))
              else
                ...byFreq.take(10).map((c) => Card(
                      margin: const EdgeInsets.only(bottom: 6),
                      child: ListTile(
                        title: Text('${c['name']}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                        trailing: Text('${c['freq']} transaksi', style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.accentBlue)),
                      ),
                    )),
              const SizedBox(height: 16),
              Text('Piutang / Kasbon Belum Lunas (${activeDebts.length})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 8),
              if (activeDebts.isEmpty)
                const Text('Semua tagihan pelanggan sudah lunas!', style: TextStyle(color: AppTheme.primaryGreen))
              else
                ...activeDebts.map((d) => Card(
                      margin: const EdgeInsets.only(bottom: 6),
                      child: ListTile(
                        title: Text('${d.customerName} (#${d.invoiceNumber})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        subtitle: Text(
                          'Jatuh Tempo: ${DateHelper.formatShort(d.dueDate)}${d.isOverdue ? " • TERLAMBAT" : ""}',
                          style: TextStyle(fontSize: 11, color: d.isOverdue ? AppTheme.accentRed : AppTheme.textMuted),
                        ),
                        trailing: Text(CurrencyHelper.format(d.remainingDebt), style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.accentRed)),
                      ),
                    )),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSuppliersTab() {
    final sup = Map<String, dynamic>.from(_analytics['suppliers'] as Map? ?? {});
    final summary = (sup['summary'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    final debts = (sup['debts'] as List<dynamic>? ?? []).cast<SupplierDebtModel>();
    final payments = (sup['payments'] as List<dynamic>? ?? []).cast<SupplierDebtPaymentModel>();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1020),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Ringkasan Pembelian & Kewajiban per Supplier', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 8),
              if (summary.isEmpty)
                const Text('Belum ada transaksi pembelian supplier.', style: TextStyle(color: AppTheme.textMuted))
              else
                ...summary.map((s) => Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: const CircleAvatar(backgroundColor: AppTheme.primaryGreenSoft, child: Icon(Icons.local_shipping_rounded, color: AppTheme.primaryGreen)),
                        title: Text('${s['supplierName']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                        subtitle: Text(
                          'PO Periode Ini: ${s['purchaseCount']}x • Total Beli: ${CurrencyHelper.format((s['totalPurchaseValue'] as num).toDouble())}',
                          style: const TextStyle(fontSize: 11.5),
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            const Text('Sisa Utang', style: TextStyle(fontSize: 10, color: AppTheme.textMuted)),
                            Text(
                              CurrencyHelper.format((s['activeDebt'] as num).toDouble()),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: (s['activeDebt'] as num) > 0 ? AppTheme.accentRed : AppTheme.primaryGreen,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )),
              const SizedBox(height: 16),
              Text('Hutang Supplier Berjalan (${debts.where((d) => !d.isPaidOff).length})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 8),
              if (debts.isEmpty)
                const Text('Tidak ada hutang supplier.', style: TextStyle(color: AppTheme.textMuted))
              else
                ...debts.map((d) => Card(
                      margin: const EdgeInsets.only(bottom: 6),
                      child: ListTile(
                        title: Text('${d.supplierName} (#${d.purchaseNumber})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        subtitle: Text('Status: ${d.status.toUpperCase()}${d.dueDate != null ? " • Tempo: ${DateHelper.formatShort(d.dueDate!)}" : ""}', style: const TextStyle(fontSize: 11)),
                        trailing: Text(CurrencyHelper.format(d.remainingDebt), style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.accentRed)),
                      ),
                    )),
              const SizedBox(height: 16),
              Text('Pembayaran Utang pada Periode (${payments.length})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 8),
              ...payments.map((p) => Card(
                    margin: const EdgeInsets.only(bottom: 6),
                    child: ListTile(
                      title: Text(CurrencyHelper.format(p.amount), style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryGreen)),
                      subtitle: Text('${DateHelper.formatFull(p.date)} • ${p.paymentSource == "kas_laci" ? "Kas Laci" : "Transfer (${p.accountName})"}', style: const TextStyle(fontSize: 11)),
                    ),
                  )),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfitTab(Map<String, dynamic> profit, bool canViewProfit) {
    if (!canViewProfit) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Akses laporan HPP & Keuntungan Kotor hanya tersedia untuk Pemilik (Owner) atau karyawan yang diberi izin melihat profit.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textMuted),
          ),
        ),
      );
    }

    final grossSales = (profit['grossSales'] as num?)?.toDouble() ?? 0.0;
    final discount = (profit['totalDiscount'] as num?)?.toDouble() ?? 0.0;
    final returns = (profit['totalReturn'] as num?)?.toDouble() ?? 0.0;
    final grossReturns = (profit['grossReturnValue'] as num?)?.toDouble() ?? returns;
    final exchangeOut = (profit['exchangeOutValue'] as num?)?.toDouble() ?? 0.0;
    final netSales = (profit['netSales'] as num?)?.toDouble() ?? 0.0;
    final grossSalesHpp = (profit['grossSalesHpp'] as num?)?.toDouble() ?? ((profit['totalHpp'] as num?)?.toDouble() ?? 0.0);
    final hppRecovered = (profit['hppRecovered'] as num?)?.toDouble() ?? 0.0;
    final exchangeHpp = (profit['exchangeHpp'] as num?)?.toDouble() ?? 0.0;
    final damagedLoss = (profit['damagedLoss'] as num?)?.toDouble() ?? 0.0;
    final hpp = (profit['totalHpp'] as num?)?.toDouble() ?? 0.0;
    final grossProfit = (profit['grossProfit'] as num?)?.toDouble() ?? 0.0;
    final margin = (profit['profitMargin'] as num?)?.toDouble() ?? 0.0;
    final returnsMeta = Map<String, dynamic>.from(_analytics['returns'] as Map? ?? {});
    final retTunai = (returnsMeta['cashReturnOut'] as num?)?.toDouble() ?? 0.0;
    final retTransfer = (returnsMeta['transferReturnOut'] as num?)?.toDouble() ?? 0.0;
    final retQris = (returnsMeta['qrisReturnOut'] as num?)?.toDouble() ?? 0.0;
    final retCredit = (returnsMeta['creditIssuedTotal'] as num?)?.toDouble() ?? 0.0;
    final retDebtOffset = (returnsMeta['debtOffsetTotal'] as num?)?.toDouble() ?? 0.0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: AppTheme.cardDecoration(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Rekapitulasi Laba Rugi Kotor (Riil SQLite)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    const Divider(height: 18),
                    _profitRow('Penjualan Kotor (Gross Sales)', CurrencyHelper.format(grossSales)),
                    _profitRow('Total Diskon & Promo', '-${CurrencyHelper.format(discount)}', color: Colors.pink),
                    _profitRow('Retur Kotor (Tunai/Transfer/Kredit/Tukar)', CurrencyHelper.format(grossReturns), color: AppTheme.accentRed),
                    if (exchangeOut > 0)
                      _profitRow('Nilai Barang Keluar Pengganti (Tukar Barang)', '+${CurrencyHelper.format(exchangeOut)}', color: AppTheme.accentBlue),
                    _profitRow('Dampak Penyesuaian Retur Netto ke Omzet', CurrencyHelper.format(-returns), color: AppTheme.accentRed),
                    const Divider(height: 12),
                    _profitRow('Penjualan Bersih (Net Sales)', CurrencyHelper.format(netSales), bold: true),
                    _profitRow('HPP Penjualan Awal', '-${CurrencyHelper.format(grossSalesHpp)}', color: AppTheme.accentOrange),
                    if (hppRecovered > 0)
                      _profitRow('Pemulihan HPP (Retur Layak Jual)', '+${CurrencyHelper.format(hppRecovered)}', color: AppTheme.primaryGreen),
                    if (exchangeHpp > 0)
                      _profitRow('Tambahan HPP Barang Tukar Keluar', '-${CurrencyHelper.format(exchangeHpp)}', color: AppTheme.accentOrange),
                    _profitRow('Harga Pokok Penjualan Bersih (HPP Adjusted)', '-${CurrencyHelper.format(hpp)}', bold: true, color: AppTheme.accentOrange),
                    if (damagedLoss > 0)
                      _profitRow('Nilai Kerugian Modal Barang Rusak / Afkir', CurrencyHelper.format(damagedLoss), color: AppTheme.accentRed),
                    const Divider(height: 14),
                    _profitRow(
                      'LABA KOTOR (GROSS PROFIT)',
                      CurrencyHelper.format(grossProfit),
                      bold: true,
                      color: grossProfit >= 0 ? AppTheme.primaryGreen : AppTheme.accentRed,
                    ),
                    _profitRow('Margin Keuntungan Kotor', '${margin.toStringAsFixed(1)}%', bold: true, color: Colors.teal),
                    if (grossReturns > 0) ...[
                      const Divider(height: 18),
                      const Text('Rincian Penyelesaian Retur Periode Ini:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                      const SizedBox(height: 4),
                      if (retTunai > 0) _profitRow('• Refund Tunai (Kas Laci)', CurrencyHelper.format(retTunai)),
                      if (retTransfer > 0) _profitRow('• Refund Transfer Bank', CurrencyHelper.format(retTransfer)),
                      if (retQris > 0) _profitRow('• Refund QRIS / E-Wallet', CurrencyHelper.format(retQris)),
                      if (retCredit > 0) _profitRow('• Diterbitkan ke Saldo Kredit Pelanggan', CurrencyHelper.format(retCredit)),
                      if (retDebtOffset > 0) _profitRow('• Pemotongan Piutang / Kasbon', CurrencyHelper.format(retDebtOffset)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _profitRow(String label, String value, {bool bold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: bold ? 13.5 : 12.5, fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
          Text(value, style: TextStyle(fontSize: bold ? 14.5 : 12.5, fontWeight: bold ? FontWeight.bold : FontWeight.w600, color: color ?? AppTheme.textDark)),
        ],
      ),
    );
  }

  Widget _presetChip(String key, String label) {
    final selected = _preset == key;
    return ChoiceChip(
      label: Text(label, style: TextStyle(fontSize: 11.5, color: selected ? Colors.white : AppTheme.textDark)),
      selected: selected,
      selectedColor: AppTheme.primaryGreen,
      onSelected: (_) => _selectPreset(key),
    );
  }

  Widget _prodChip(String key, String label) {
    final selected = _productSubTab == key;
    return ChoiceChip(
      label: Text(label, style: TextStyle(fontSize: 11.5, color: selected ? Colors.white : AppTheme.textDark)),
      selected: selected,
      selectedColor: AppTheme.primaryGreen,
      onSelected: (_) => setState(() => _productSubTab = key),
    );
  }

  Widget _kpiCard(String title, String val, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: AppTheme.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 5),
              Expanded(child: Text(title, style: const TextStyle(fontSize: 11, color: AppTheme.textMuted), overflow: TextOverflow.ellipsis)),
            ],
          ),
          Text(val, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color), maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  Widget _methodProgress(String label, double val, double total, Color color) {
    final ratio = total > 0 ? (val / total).clamp(0.0, 1.0) : 0.0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(fontSize: 12)),
              Text('${CurrencyHelper.format(val)} (${(ratio * 100).toStringAsFixed(0)}%)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
            ],
          ),
          const SizedBox(height: 3),
          LinearProgressIndicator(
            value: ratio,
            minHeight: 6,
            borderRadius: BorderRadius.circular(4),
            backgroundColor: Colors.grey.shade200,
            color: color,
          ),
        ],
      ),
    );
  }
}

class _DailySalesBarChart extends StatelessWidget {
  final List<Map<String, dynamic>> series;

  const _DailySalesBarChart({required this.series});

  @override
  Widget build(BuildContext context) {
    final shown = series.length > 14 ? series.sublist(series.length - 14) : series;
    final maxVal = shown.fold<double>(0.0, (m, e) {
      final v = (e['total'] as num).toDouble();
      return v > m ? v : m;
    });

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: shown.map((item) {
        final total = (item['total'] as num).toDouble();
        final frac = maxVal > 0 ? (total / maxVal).clamp(0.05, 1.0) : 0.05;
        final rawDate = item['date'].toString();
        final shortLabel = rawDate.length >= 10 ? '${rawDate.substring(8, 10)}/${rawDate.substring(5, 7)}' : rawDate;

        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  total >= 1000000
                      ? '${(total / 1000000).toStringAsFixed(1)}jt'
                      : (total >= 1000 ? '${(total / 1000).toInt()}k' : '${total.toInt()}'),
                  style: const TextStyle(fontSize: 8.5, color: AppTheme.textMuted),
                  maxLines: 1,
                ),
                const SizedBox(height: 4),
                Flexible(
                  child: FractionallySizedBox(
                    heightFactor: frac,
                    child: Container(
                      width: double.infinity,
                      constraints: const BoxConstraints(minHeight: 6),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryGreen,
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(shortLabel, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600), maxLines: 1),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
