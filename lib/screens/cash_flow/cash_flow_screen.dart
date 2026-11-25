import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../database/db_helper.dart';
import '../../providers/auth_provider.dart';
import '../../providers/cash_flow_provider.dart';
import '../../utils/app_theme.dart';
import '../../utils/currency_format.dart';
import '../../utils/date_format.dart';

class CashFlowScreen extends StatefulWidget {
  const CashFlowScreen({super.key});

  @override
  State<CashFlowScreen> createState() => _CashFlowScreenState();
}

class _CashFlowScreenState extends State<CashFlowScreen> {
  final TextEditingController _amountCtrl = TextEditingController();
  final TextEditingController _noteCtrl = TextEditingController();

  String _type = 'out'; // 'in' | 'out'
  String _category = 'Operasional Toko';
  String _accountMode = 'kas_laci'; // 'kas_laci' | 'transfer'
  bool _isInternalTransfer = false;

  String _rangePreset = 'today'; // 'today' | 'yesterday' | '7d' | 'month' | 'custom'
  late DateTime _startDate;
  late DateTime _endDate;
  Map<String, dynamic> _report = {};
  bool _loadingReport = true;

  final List<String> _expenseCategories = [
    'Operasional Toko',
    'Beli Kantong Plastik',
    'Iuran Kebersihan / Keamanan',
    'Listrik & Air Toko',
    'Gaji / Konsumsi Karyawan',
    'Setor Kas ke Bank (Internal)',
    'Prive / Ambil Kas Owner',
    'Lain-lain',
  ];

  final List<String> _incomeCategories = [
    'Modal Tambahan',
    'Tarik Tunai ke Laci (Internal)',
    'Komisi / Penitipan Barang',
    'Lain-lain',
  ];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _startDate = DateTime(now.year, now.month, now.day);
    _endDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadReport();
    });
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadReport() async {
    setState(() => _loadingReport = true);
    final res = await DatabaseHelper.instance.getCashFlowReport(_startDate, _endDate);
    await Provider.of<CashFlowProvider>(context, listen: false).checkOpenShift();
    if (!mounted) return;
    setState(() {
      _report = res;
      _loadingReport = false;
    });
  }

  void _applyPreset(String preset) async {
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
      _rangePreset = 'custom';
      _startDate = DateTime(range.start.year, range.start.month, range.start.day);
      _endDate = DateTime(range.end.year, range.end.month, range.end.day, 23, 59, 59);
    } else {
      _rangePreset = preset;
      switch (preset) {
        case 'today':
          _startDate = today;
          _endDate = DateTime(today.year, today.month, today.day, 23, 59, 59);
          break;
        case 'yesterday':
          final y = today.subtract(const Duration(days: 1));
          _startDate = y;
          _endDate = DateTime(y.year, y.month, y.day, 23, 59, 59);
          break;
        case '7d':
          _startDate = today.subtract(const Duration(days: 6));
          _endDate = DateTime(today.year, today.month, today.day, 23, 59, 59);
          break;
        case 'month':
          _startDate = DateTime(today.year, today.month, 1);
          _endDate = DateTime(today.year, today.month, today.day, 23, 59, 59);
          break;
      }
    }
    await _loadReport();
  }

  Future<void> _submitFlow() async {
    final amount = double.tryParse(_amountCtrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0.0;
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nominal harus lebih dari Rp 0')),
      );
      return;
    }

    final cashFlow = Provider.of<CashFlowProvider>(context, listen: false);
    final auth = Provider.of<AuthProvider>(context, listen: false);

    if (_type == 'out' && _accountMode == 'kas_laci' && !cashFlow.isShiftOpen) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Shift kasir harus terbuka untuk mengeluarkan uang dari Laci Kasir.'),
          backgroundColor: AppTheme.accentRed,
        ),
      );
      return;
    }

    try {
      await cashFlow.recordCashFlow(
        type: _type,
        category: _category,
        amount: amount,
        note: _noteCtrl.text.trim(),
        cashierName: auth.currentUser?.name ?? 'Kasir',
        paymentMethod: _accountMode == 'kas_laci' ? 'tunai' : 'transfer',
        accountName: _accountMode == 'kas_laci' ? 'Laci Kasir' : 'Rekening Bank / QRIS',
        sourceType: _isInternalTransfer ? 'transfer_internal' : 'manual',
        isInternalTransfer: _isInternalTransfer,
      );

      await auth.logAction(
        _type == 'out' ? 'kas_keluar' : 'kas_masuk',
        '${_type == 'out' ? "Pengeluaran" : "Pemasukan"} $_category: ${CurrencyHelper.format(amount)} (${_accountMode == "kas_laci" ? "Laci Kasir" : "Rekening"})${_isInternalTransfer ? " [Transfer Internal]" : ""}',
        module: 'arus_kas',
      );

      _amountCtrl.clear();
      _noteCtrl.clear();
      await _loadReport();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Catatan arus kas berhasil disimpan!'),
          backgroundColor: _type == 'in' ? AppTheme.primaryGreen : AppTheme.accentOrange,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Bad state: ', '').replaceFirst('ArgumentError: ', '')),
          backgroundColor: AppTheme.accentRed,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cashFlow = Provider.of<CashFlowProvider>(context);
    final isWide = MediaQuery.sizeOf(context).width >= AppBreakpoints.tablet;

    final openingBal = (_report['openingBalance'] as num?)?.toDouble() ?? 0.0;
    final endingCash = (_report['endingCashBalance'] as num?)?.toDouble() ?? 0.0;
    final totalIn = (_report['totalOperationalIn'] as num?)?.toDouble() ?? 0.0;
    final totalOut = (_report['totalOperationalOut'] as num?)?.toDouble() ?? 0.0;
    final entries = (_report['entries'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Arus Kas & Rekonsiliasi Saldo'),
      ),
      body: RefreshIndicator(
        onRefresh: _loadReport,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(14),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Filter Date Presets (Default: Today)
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _presetChip('today', 'Hari Ini'),
                        const SizedBox(width: 6),
                        _presetChip('yesterday', 'Kemarin'),
                        const SizedBox(width: 6),
                        _presetChip('7d', '7 Hari Terakhir'),
                        const SizedBox(width: 6),
                        _presetChip('month', 'Bulan Ini'),
                        const SizedBox(width: 6),
                        _presetChip(
                          'custom',
                          _rangePreset == 'custom'
                              ? '${DateHelper.formatShort(_startDate)} - ${DateHelper.formatShort(_endDate)}'
                              : 'Rentang Kustom',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  if (_loadingReport)
                    const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
                  else ...[
                    // 4 Summary Metrics
                    GridView.count(
                      crossAxisCount: isWide ? 4 : 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                      childAspectRatio: isWide ? 1.85 : 1.9,
                      children: [
                        _summaryCard('Saldo Awal Laci', openingBal, Colors.blueGrey, Icons.account_balance_wallet_outlined),
                        _summaryCard('Masuk Operasional', totalIn, AppTheme.primaryGreen, Icons.south_west_rounded),
                        _summaryCard('Keluar Operasional', totalOut, AppTheme.accentRed, Icons.north_east_rounded),
                        _summaryCard('Saldo Akhir Kas Laci', endingCash, AppTheme.accentBlue, Icons.savings_rounded),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Categorized Breakdown Card (No Double Counting)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: AppTheme.cardDecoration(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Rincian Kategori Arus Kas Periode', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 18,
                            runSpacing: 6,
                            children: [
                              _catChip('Penjualan Tunai', _report['totalSalesCash'], AppTheme.primaryGreen),
                              _catChip('QRIS / Transfer', _report['totalSalesNonCash'], AppTheme.accentBlue),
                              _catChip('Bayar Kasbon', _report['totalDebtPayments'], AppTheme.primaryGreen),
                              _catChip('Pemasukan Lain', _report['totalOtherIn'], Colors.teal),
                              _catChip('Beli Stok Laci', _report['totalCashPurchases'], AppTheme.accentOrange),
                              _catChip('Beli Stok Transfer', _report['totalTransferPurchases'], Colors.deepOrange),
                              _catChip('Bayar Utang Supplier', _report['totalSupplierPayments'], AppTheme.accentRed),
                              _catChip('Beban Operasional', _report['totalOpExpenses'], AppTheme.accentRed),
                              _catChip('Retur Tunai', _report['totalRefundOut'], Colors.purple),
                              _catChip('Transfer Internal (Netral)', _report['totalInternalTransfers'], AppTheme.textMuted),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],

                  // Entry Form Card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: AppTheme.cardDecoration(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Expanded(
                              child: Text(
                                'Catat Kas Masuk / Keluar',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                cashFlow.isShiftOpen
                                    ? 'Laci: ${CurrencyHelper.format(cashFlow.currentShift?.expectedCash ?? 0)}'
                                    : 'Shift Tertutup',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.bold,
                                  color: cashFlow.isShiftOpen ? AppTheme.primaryGreen : AppTheme.accentOrange,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: Material(
                                color: _type == 'out' ? AppTheme.accentRedSoft : AppTheme.lightGreyBg,
                                borderRadius: BorderRadius.circular(10),
                                child: InkWell(
                                  onTap: () => setState(() {
                                    _type = 'out';
                                    _category = _expenseCategories.first;
                                  }),
                                  borderRadius: BorderRadius.circular(10),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: _type == 'out' ? AppTheme.accentRed : AppTheme.borderLight,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.arrow_upward_rounded, size: 15, color: _type == 'out' ? AppTheme.accentRed : AppTheme.textMuted),
                                        const SizedBox(width: 4),
                                        Flexible(
                                          child: Text(
                                            'Pengeluaran',
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 12.5,
                                              fontWeight: _type == 'out' ? FontWeight.bold : FontWeight.w500,
                                              color: _type == 'out' ? AppTheme.accentRed : AppTheme.textDark,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Material(
                                color: _type == 'in' ? AppTheme.primaryGreenSoft : AppTheme.lightGreyBg,
                                borderRadius: BorderRadius.circular(10),
                                child: InkWell(
                                  onTap: () => setState(() {
                                    _type = 'in';
                                    _category = _incomeCategories.first;
                                  }),
                                  borderRadius: BorderRadius.circular(10),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: _type == 'in' ? AppTheme.primaryGreen : AppTheme.borderLight,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.arrow_downward_rounded, size: 15, color: _type == 'in' ? AppTheme.primaryGreen : AppTheme.textMuted),
                                        const SizedBox(width: 4),
                                        Flexible(
                                          child: Text(
                                            'Pemasukan',
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 12.5,
                                              fontWeight: _type == 'in' ? FontWeight.bold : FontWeight.w500,
                                              color: _type == 'in' ? AppTheme.primaryGreen : AppTheme.textDark,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                value: _category,
                                isExpanded: true,
                                decoration: const InputDecoration(labelText: 'Kategori'),
                                items: (_type == 'out' ? _expenseCategories : _incomeCategories)
                                    .map((e) => DropdownMenuItem(value: e, child: Text(e, overflow: TextOverflow.ellipsis)))
                                    .toList(),
                                onChanged: (val) {
                                  if (val != null) {
                                    setState(() {
                                      _category = val;
                                      if (val.contains('Internal')) {
                                        _isInternalTransfer = true;
                                      }
                                    });
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                value: _accountMode,
                                isExpanded: true,
                                decoration: const InputDecoration(labelText: 'Akun / Dompet'),
                                items: const [
                                  DropdownMenuItem(value: 'kas_laci', child: Text('Laci Kasir (Tunai)', overflow: TextOverflow.ellipsis)),
                                  DropdownMenuItem(value: 'transfer', child: Text('Rekening Bank / QRIS', overflow: TextOverflow.ellipsis)),
                                ],
                                onChanged: (v) => setState(() => _accountMode = v ?? 'kas_laci'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _amountCtrl,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          decoration: const InputDecoration(labelText: 'Nominal (Rp) *', prefixText: 'Rp '),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _noteCtrl,
                          decoration: const InputDecoration(labelText: 'Keterangan / Penerima'),
                        ),
                        Material(
                          color: Colors.transparent,
                          child: SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            title: const Text('Mutasi / Transfer Internal (Setor atau Tarik Bank)', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                            subtitle: const Text('Jika aktif, saldo kas diperbarui tanpa dihitung sebagai pendapatan/beban operasional', style: TextStyle(fontSize: 11)),
                            value: _isInternalTransfer,
                            onChanged: (v) => setState(() => _isInternalTransfer = v),
                          ),
                        ),
                        const SizedBox(height: 6),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.save_rounded),
                            label: const Text('Simpan Catatan Arus Kas'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _type == 'in' ? AppTheme.primaryGreen : AppTheme.accentOrange,
                            ),
                            onPressed: _submitFlow,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 18),
                  Text(
                    'Mutasi Arus Kas (${entries.length})',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.textDark),
                  ),
                  const SizedBox(height: 8),

                  if (entries.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      decoration: AppTheme.cardDecoration(),
                      child: const Text(
                        'Belum ada mutasi arus kas pada rentang tanggal ini.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppTheme.textMuted),
                      ),
                    )
                  else
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: entries.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (context, index) {
                        final item = entries[index];
                        final isIn = item['type'] == 'in';
                        final isInternal = item['isInternalTransfer'] == true;
                        final amount = (item['amount'] as num).toDouble();
                        final date = item['date'] as DateTime;
                        final accountName = (item['accountName'] ?? 'Laci Kasir').toString();
                        final sourceType = (item['sourceType'] ?? 'manual').toString();
                        final sourceId = (item['sourceId'] ?? '').toString();
                        final note = (item['note'] ?? '').toString();

                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: AppTheme.cardDecoration(),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 18,
                                backgroundColor: isInternal
                                    ? Colors.grey.shade200
                                    : (isIn ? AppTheme.primaryGreenSoft : AppTheme.accentRedSoft),
                                child: Icon(
                                  isInternal
                                      ? Icons.swap_horiz_rounded
                                      : (isIn ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded),
                                  color: isInternal
                                      ? Colors.blueGrey
                                      : (isIn ? AppTheme.primaryGreen : AppTheme.accentRed),
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Flexible(
                                          child: Text(
                                            (item['category'] ?? '').toString(),
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                          decoration: BoxDecoration(
                                            color: Colors.grey.shade100,
                                            borderRadius: BorderRadius.circular(5),
                                          ),
                                          child: Text(accountName, style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600)),
                                        ),
                                      ],
                                    ),
                                    if (note.isNotEmpty)
                                      Text(note, style: const TextStyle(fontSize: 11.5, color: AppTheme.textSecondary)),
                                    Text(
                                      '${DateHelper.formatFull(date)} • ${item['cashierName']} • ${sourceType.toUpperCase()}${sourceId.isNotEmpty ? " #$sourceId" : ""}',
                                      style: const TextStyle(fontSize: 10.5, color: AppTheme.textMuted),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${isIn ? "+" : "-"}${CurrencyHelper.format(amount)}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13.5,
                                  color: isInternal
                                      ? Colors.blueGrey
                                      : (isIn ? AppTheme.primaryGreen : AppTheme.accentRed),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _presetChip(String key, String label) {
    final selected = _rangePreset == key;
    return ChoiceChip(
      label: Text(label, style: TextStyle(fontSize: 12, color: selected ? Colors.white : AppTheme.textDark)),
      selected: selected,
      selectedColor: AppTheme.primaryGreen,
      onSelected: (_) => _applyPreset(key),
    );
  }

  Widget _summaryCard(String title, double val, Color color, IconData icon) {
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
            CurrencyHelper.format(val),
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _catChip(String label, dynamic rawVal, Color color) {
    final val = (rawVal as num?)?.toDouble() ?? 0.0;
    return Text(
      '$label: ${CurrencyHelper.format(val)}',
      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: val > 0 ? color : AppTheme.textMuted),
    );
  }
}
