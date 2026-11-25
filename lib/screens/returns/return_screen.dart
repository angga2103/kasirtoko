import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../database/db_helper.dart';
import '../../models/return_item.dart';
import '../../models/return_order.dart';
import '../../models/transaction.dart';
import '../../providers/auth_provider.dart';
import '../../providers/cash_flow_provider.dart';
import '../../providers/debt_provider.dart';
import '../../providers/product_provider.dart';
import '../../utils/app_theme.dart';
import '../../utils/currency_format.dart';
import '../../utils/date_format.dart';
import '../../widgets/quantity_stepper.dart';
import '../scanner/barcode_scanner_screen.dart';

class ReturnScreen extends StatefulWidget {
  const ReturnScreen({super.key});

  @override
  State<ReturnScreen> createState() => _ReturnScreenState();
}

class _ReturnScreenState extends State<ReturnScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _returnNoteCtrl = TextEditingController();

  String _txPreset = 'today'; // 'today' | '7d' | '30d' | 'custom'
  late DateTime _txStart;
  late DateTime _txEnd;
  String? _barcodeFilter;

  List<TransactionModel> _recentTransactions = [];
  List<ReturnOrderModel> _returnHistory = [];
  bool _loadingList = true;
  bool _loadingTxDetail = false;
  bool _submitting = false;

  TransactionModel? _selectedTransaction;
  final Map<int, Map<String, dynamic>> _itemReturnState = {};
  String _refundMethod = 'tunai';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    final now = DateTime.now();
    _txStart = DateTime(now.year, now.month, now.day);
    _txEnd = DateTime(now.year, now.month, now.day, 23, 59, 59);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadTransactionsAndHistory();
      Provider.of<CashFlowProvider>(context, listen: false).checkOpenShift();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    _returnNoteCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadTransactionsAndHistory() async {
    setState(() => _loadingList = true);
    final txs = await DatabaseHelper.instance.getTransactionsByDateRange(
      _txStart,
      _txEnd,
      query: _searchCtrl.text.trim(),
      barcode: _barcodeFilter,
      limit: 150,
    );
    final rets = await DatabaseHelper.instance.getReturnOrders(
      start: _txStart.subtract(const Duration(days: 30)),
      end: DateTime.now(),
      limit: 100,
    );
    if (!mounted) return;
    setState(() {
      _recentTransactions = txs;
      _returnHistory = rets;
      _loadingList = false;
    });
  }

  void _setDatePreset(String preset) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (preset == 'custom') {
      final range = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2020),
        lastDate: DateTime(now.year + 1),
        initialDateRange: DateTimeRange(start: _txStart, end: _txEnd.isAfter(today) ? today : _txEnd),
      );
      if (range == null) return;
      _txPreset = 'custom';
      _txStart = DateTime(range.start.year, range.start.month, range.start.day);
      _txEnd = DateTime(range.end.year, range.end.month, range.end.day, 23, 59, 59);
    } else {
      _txPreset = preset;
      switch (preset) {
        case 'today':
          _txStart = today;
          _txEnd = DateTime(today.year, today.month, today.day, 23, 59, 59);
          break;
        case '7d':
          _txStart = today.subtract(const Duration(days: 6));
          _txEnd = DateTime(today.year, today.month, today.day, 23, 59, 59);
          break;
        case '30d':
          _txStart = today.subtract(const Duration(days: 29));
          _txEnd = DateTime(today.year, today.month, today.day, 23, 59, 59);
          break;
      }
    }
    await _loadTransactionsAndHistory();
  }

  Future<void> _scanReceiptOrProductBarcode() async {
    final res = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => const BarcodeScannerScreen(
          title: 'Scan QR Struk / Barcode Produk',
          helperText: 'Scan QR footer struk atau barcode produk untuk mencari nota',
          continuousMode: false,
        ),
      ),
    );
    if (res == null || res.trim().isEmpty || !mounted) return;
    final code = res.trim();
    if (code.startsWith('TRX|') || code.toUpperCase().startsWith('INV-')) {
      _barcodeFilter = null;
      await _selectInvoiceByCode(code);
    } else {
      setState(() {
        _barcodeFilter = code;
        _searchCtrl.clear();
      });
      await _loadTransactionsAndHistory();
    }
  }

  Future<void> _selectInvoiceByCode(String rawInput) async {
    String cleanInvoice = rawInput.trim();
    if (cleanInvoice.startsWith('TRX|')) {
      final parts = cleanInvoice.split('|');
      if (parts.length >= 2) cleanInvoice = parts[1].trim();
    }
    if (cleanInvoice.isEmpty) return;
    final trx = await DatabaseHelper.instance.getTransactionByInvoice(cleanInvoice);
    if (trx == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Nota "$cleanInvoice" tidak ditemukan.'), backgroundColor: AppTheme.accentRed),
        );
      }
      return;
    }
    await _loadTransactionForReturn(trx);
  }

  Future<void> _loadTransactionForReturn(TransactionModel trx) async {
    setState(() {
      _loadingTxDetail = true;
      _selectedTransaction = null;
      _itemReturnState.clear();
    });

    final returnedMap = trx.id != null
        ? await DatabaseHelper.instance.getReturnedQuantitiesForTransaction(trx.id!)
        : <String, double>{};

    if (!mounted) return;
    setState(() {
      _loadingTxDetail = false;
      _selectedTransaction = trx;
      _refundMethod = trx.paymentMethod == 'kasbon' ? 'potong_piutang' : 'tunai';
      for (int i = 0; i < trx.items.length; i++) {
        final item = trx.items[i];
        final key = '${item.productId}_${item.unitName}';
        final alreadyReturned = returnedMap[key] ?? 0.0;
        final remainingQty = (item.qty - alreadyReturned).clamp(0.0, item.qty);
        _itemReturnState[i] = {
          'selected': false,
          'qty': remainingQty > 0 ? (remainingQty >= 1 ? 1.0 : remainingQty) : 0.0,
          'maxQty': remainingQty,
          'alreadyReturned': alreadyReturned,
          'condition': 'baik',
        };
      }
    });

    if ((trx.status == 'void' || trx.status == 'voided') && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Transaksi berstatus VOID dan tidak dapat diretur.'),
          backgroundColor: AppTheme.accentOrange,
        ),
      );
    }
  }

  double get _totalRefundAmount {
    if (_selectedTransaction == null) return 0.0;
    double total = 0.0;
    _itemReturnState.forEach((index, state) {
      if (state['selected'] == true) {
        final item = _selectedTransaction!.items[index];
        final qty = state['qty'] as double;
        total += (qty * item.unitPrice);
      }
    });
    return total;
  }

  Future<void> _processReturn() async {
    if (_selectedTransaction == null || _submitting) return;
    final totalRefund = _totalRefundAmount;
    if (totalRefund <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pilih minimal 1 barang dengan jumlah valid untuk diretur.')),
      );
      return;
    }

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final productProv = Provider.of<ProductProvider>(context, listen: false);
    final cashFlow = Provider.of<CashFlowProvider>(context, listen: false);
    final debtProv = Provider.of<DebtProvider>(context, listen: false);
    final cashier = auth.currentUser;

    if (_refundMethod == 'tunai' && !cashFlow.isShiftOpen) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Shift kasir harus terbuka untuk mengembalikan uang tunai dari Kas Laci.'),
          backgroundColor: AppTheme.accentRed,
        ),
      );
      return;
    }

    final returnNumber = 'RET-${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}';
    final returnItems = <ReturnItemModel>[];
    _itemReturnState.forEach((index, state) {
      if (state['selected'] == true) {
        final item = _selectedTransaction!.items[index];
        final qty = state['qty'] as double;
        final condition = state['condition'] as String;
        returnItems.add(
          ReturnItemModel(
            productId: item.productId,
            productName: item.productName,
            unitName: item.unitName,
            conversionFactor: item.conversionFactor,
            returnQty: qty,
            refundPrice: item.unitPrice,
            subtotal: qty * item.unitPrice,
            condition: condition,
          ),
        );
      }
    });

    final returnOrder = ReturnOrderModel(
      returnNumber: returnNumber,
      transactionId: _selectedTransaction!.id!,
      invoiceNumber: _selectedTransaction!.invoiceNumber,
      date: DateTime.now(),
      cashierId: cashier?.id ?? 1,
      cashierName: cashier?.name ?? 'Kasir',
      totalRefund: totalRefund,
      refundMethod: _refundMethod,
      note: _returnNoteCtrl.text.trim(),
      items: returnItems,
    );

    setState(() => _submitting = true);
    try {
      await DatabaseHelper.instance.insertReturnOrder(
        returnOrder,
        shiftId: cashFlow.currentShift?.id,
      );

      await auth.logAction(
        'retur_transaksi',
        'Retur nota #${_selectedTransaction!.invoiceNumber} ($returnNumber): ${returnItems.length} item, Total: ${CurrencyHelper.format(totalRefund)}',
        module: 'retur',
        objectId: returnNumber,
      );

      await productProv.loadProducts();
      await cashFlow.checkOpenShift();
      await debtProv.loadDebts();
      await _loadTransactionsAndHistory();

      if (!mounted) return;
      final inv = _selectedTransaction!.invoiceNumber;
      setState(() {
        _submitting = false;
        _selectedTransaction = null;
        _itemReturnState.clear();
        _returnNoteCtrl.clear();
      });

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.check_circle_rounded, color: AppTheme.primaryGreen),
              SizedBox(width: 8),
              Text('Retur Berhasil!'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('No. Retur: $returnNumber', style: const TextStyle(fontWeight: FontWeight.bold)),
              Text('Nota Asli: $inv'),
              Text('Total Pengembalian: ${CurrencyHelper.format(totalRefund)}',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryGreen)),
              Text('Metode Refund: ${_refundMethod.toUpperCase()}'),
              const SizedBox(height: 8),
              const Text(
                'Barang kondisi BAIK dikembalikan ke stok aktif. Riwayat retur kini tercatat pada tab Riwayat.',
                style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
              ),
            ],
          ),
          actions: [
            ElevatedButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Retur & Pengembalian Barang'),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: AppTheme.accentOrange,
          tabs: [
            const Tab(text: 'Proses Retur'),
            Tab(text: 'Riwayat Retur (${_returnHistory.length})'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildProcessReturnTab(),
          _buildHistoryTab(),
        ],
      ),
    );
  }

  Widget _buildProcessReturnTab() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 880),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Filter & Search Card
              Container(
                padding: const EdgeInsets.all(14),
                decoration: AppTheme.cardDecoration(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _dateChip('today', 'Hari Ini'),
                          const SizedBox(width: 6),
                          _dateChip('7d', '7 Hari'),
                          const SizedBox(width: 6),
                          _dateChip('30d', '30 Hari'),
                          const SizedBox(width: 6),
                          _dateChip(
                            'custom',
                            _txPreset == 'custom'
                                ? '${DateHelper.formatShort(_txStart)} - ${DateHelper.formatShort(_txEnd)}'
                                : 'Kustom',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _searchCtrl,
                            decoration: InputDecoration(
                              hintText: 'Cari No. Nota / Pelanggan / Produk...',
                              hintStyle: const TextStyle(fontSize: 12),
                              prefixIcon: const Icon(Icons.search_rounded, size: 20),
                              suffixIcon: (_searchCtrl.text.isNotEmpty || _barcodeFilter != null)
                                  ? IconButton(
                                      icon: const Icon(Icons.clear, size: 18),
                                      onPressed: () {
                                        _searchCtrl.clear();
                                        _barcodeFilter = null;
                                        _loadTransactionsAndHistory();
                                      },
                                    )
                                  : null,
                            ),
                            onChanged: (_) => _loadTransactionsAndHistory(),
                            onSubmitted: (val) => _selectInvoiceByCode(val),
                          ),
                        ),
                        const SizedBox(width: 6),
                        OutlinedButton.icon(
                          onPressed: _scanReceiptOrProductBarcode,
                          icon: const Icon(Icons.qr_code_scanner_rounded, size: 19),
                          label: const Text('Scan', style: TextStyle(fontSize: 12)),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                          ),
                        ),
                      ],
                    ),
                    if (_barcodeFilter != null) ...[
                      const SizedBox(height: 8),
                      Chip(
                        label: Text('Filter Barcode: $_barcodeFilter', style: const TextStyle(fontSize: 11)),
                        onDeleted: () {
                          setState(() => _barcodeFilter = null);
                          _loadTransactionsAndHistory();
                        },
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),

              if (_selectedTransaction == null) ...[
                Text(
                  'Daftar Transaksi (${_recentTransactions.length})',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                ),
                const SizedBox(height: 8),
                if (_loadingList)
                  const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
                else if (_recentTransactions.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: AppTheme.cardDecoration(),
                    child: const Text(
                      'Tidak ada transaksi yang cocok pada rentang tanggal ini.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppTheme.textMuted),
                    ),
                  )
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _recentTransactions.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, idx) {
                      final t = _recentTransactions[idx];
                      final isVoided = t.status == 'void' || t.status == 'voided';
                      return Card(
                        child: ListTile(
                          onTap: () => _loadTransactionForReturn(t),
                          leading: CircleAvatar(
                            backgroundColor: isVoided ? AppTheme.accentRedSoft : AppTheme.primaryGreenSoft,
                            child: Icon(
                              isVoided ? Icons.block_rounded : Icons.receipt_long_rounded,
                              color: isVoided ? AppTheme.accentRed : AppTheme.primaryGreen,
                            ),
                          ),
                          title: Text(
                            '#${t.invoiceNumber} • ${t.customerName}',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                          ),
                          subtitle: Text(
                            '${DateHelper.formatFull(t.date)} • ${t.items.length} item • ${t.paymentMethod.toUpperCase()}${isVoided ? " [VOID]" : ""}',
                            style: const TextStyle(fontSize: 11.5),
                          ),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                CurrencyHelper.format(t.grandTotal),
                                style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryGreen),
                              ),
                              const Text('Pilih →', style: TextStyle(fontSize: 10.5, color: AppTheme.accentBlue)),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
              ] else if (_loadingTxDetail)
                const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
              else ...[
                // Back to list + Selected Transaction Card
                TextButton.icon(
                  onPressed: () => setState(() => _selectedTransaction = null),
                  icon: const Icon(Icons.arrow_back_rounded, size: 18),
                  label: const Text('Kembali ke Daftar Nota'),
                ),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: AppTheme.cardDecoration(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _selectedTransaction!.invoiceNumber,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: _selectedTransaction!.status == 'completed'
                                  ? Colors.green.shade100
                                  : Colors.orange.shade100,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _selectedTransaction!.status.toUpperCase(),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: _selectedTransaction!.status == 'completed'
                                    ? Colors.green.shade800
                                    : Colors.orange.shade800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Tanggal: ${DateHelper.formatFull(_selectedTransaction!.date)} • Kasir: ${_selectedTransaction!.cashierName}',
                        style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                      ),
                      Text(
                        'Pelanggan: ${_selectedTransaction!.customerName} • Bayar: ${_selectedTransaction!.paymentMethod.toUpperCase()}',
                        style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                      ),
                      const Divider(height: 14),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Total Belanja Asli:', style: TextStyle(fontSize: 12)),
                          Text(
                            CurrencyHelper.format(_selectedTransaction!.grandTotal),
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                if (_itemReturnState.values.any((s) => ((s['alreadyReturned'] as num?)?.toDouble() ?? 0.0) > 0))
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.accentOrange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTheme.accentOrange.withValues(alpha: 0.4)),
                    ),
                    child: const Text(
                      'Perhatian: Nota ini sudah memiliki retur sebelumnya. Sisa kuantitas yang masih bisa diretur telah dibatasi otomatis.',
                      style: TextStyle(fontSize: 11.5, color: AppTheme.accentOrange, fontWeight: FontWeight.w600),
                    ),
                  ),

                const Text('Pilih Barang yang Diretur & Kondisinya:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),

                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _selectedTransaction!.items.length,
                  itemBuilder: (context, index) {
                    final item = _selectedTransaction!.items[index];
                    final state = _itemReturnState[index]!;
                    final isSelected = state['selected'] as bool;
                    final currentQty = state['qty'] as double;
                    final maxQty = (state['maxQty'] as num).toDouble();
                    final alreadyReturned = (state['alreadyReturned'] as num).toDouble();
                    final condition = state['condition'] as String;
                    final canReturn =
                        _selectedTransaction!.status != 'void' && _selectedTransaction!.status != 'voided' && maxQty > 0;
                    final allowDecimal = maxQty != maxQty.truncateToDouble() || item.qty != item.qty.truncateToDouble();

                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Checkbox(
                                  value: isSelected,
                                  onChanged: canReturn
                                      ? (val) => setState(() => state['selected'] = val ?? false)
                                      : null,
                                ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.productName,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                          color: canReturn ? AppTheme.textDark : AppTheme.textMuted,
                                        ),
                                      ),
                                      Text(
                                        alreadyReturned > 0
                                            ? 'Beli: ${item.qty} • Pernah diretur: $alreadyReturned • Sisa maks: $maxQty ${item.unitName}'
                                            : 'Beli: ${item.qty} ${item.unitName} @ ${CurrencyHelper.format(item.unitPrice)}',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: canReturn ? AppTheme.textMuted : AppTheme.accentRed,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (isSelected)
                                  Text(
                                    CurrencyHelper.format(currentQty * item.unitPrice),
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                  )
                                else if (maxQty <= 0)
                                  const Text('Habis Diretur', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                              ],
                            ),
                            if (isSelected && canReturn) ...[
                              const Divider(height: 12),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                alignment: WrapAlignment.spaceBetween,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Text('Qty Retur: ', style: TextStyle(fontSize: 11)),
                                      QuantityStepper(
                                        value: currentQty,
                                        minValue: maxQty >= 1 ? 1.0 : maxQty,
                                        maxValue: maxQty,
                                        allowDecimal: allowDecimal,
                                        compact: true,
                                        unitLabel: item.unitName,
                                        onChanged: (val) => setState(() => state['qty'] = val),
                                      ),
                                    ],
                                  ),
                                  DropdownButton<String>(
                                    value: condition,
                                    isDense: true,
                                    items: const [
                                      DropdownMenuItem(value: 'baik', child: Text('Baik (Kembali Stok)')),
                                      DropdownMenuItem(value: 'rusak', child: Text('Rusak / Afkir')),
                                    ],
                                    onChanged: (val) {
                                      if (val != null) setState(() => state['condition'] = val);
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 14),

                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: AppTheme.cardDecoration(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Metode Pengembalian Dana (Refund):', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(child: _buildRefundChip('tunai', 'Tunai (Kas Laci)', Icons.money_rounded)),
                          const SizedBox(width: 8),
                          Expanded(child: _buildRefundChip('potong_piutang', 'Potong Kasbon', Icons.receipt_rounded)),
                          const SizedBox(width: 8),
                          Expanded(child: _buildRefundChip('tukar_barang', 'Tukar Barang', Icons.swap_horiz_rounded)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _returnNoteCtrl,
                        decoration: const InputDecoration(labelText: 'Alasan Retur (Opsional)'),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('TOTAL PENGEMBALIAN', style: TextStyle(fontWeight: FontWeight.bold)),
                          Text(
                            CurrencyHelper.format(_totalRefundAmount),
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primaryGreen),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: (_submitting || _totalRefundAmount <= 0) ? null : _processReturn,
                          icon: const Icon(Icons.assignment_return_rounded),
                          label: Text(_submitting ? 'MEMPROSES...' : 'PROSES RETUR SEKARANG'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHistoryTab() {
    if (_loadingList) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_returnHistory.isEmpty) {
      return const Center(child: Text('Belum ada riwayat retur barang.'));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(14),
      itemCount: _returnHistory.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, idx) {
        final r = _returnHistory[idx];
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(r.returnNumber, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: AppTheme.primaryGreenSoft, borderRadius: BorderRadius.circular(8)),
                      child: Text(r.refundMethod.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.primaryGreen)),
                    ),
                  ],
                ),
                Text(
                  'Nota Asli: #${r.invoiceNumber} • ${DateHelper.formatFull(r.date)} • ${r.cashierName}',
                  style: const TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
                ),
                const Divider(height: 12),
                ...r.items.map((it) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${it.productName} (${it.returnQty} ${it.unitName}) • ${it.condition.toUpperCase()}',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                          Text(CurrencyHelper.format(it.subtotal), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    )),
                const Divider(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(r.note.isNotEmpty ? 'Catatan: ${r.note}' : 'Total Refund', style: const TextStyle(fontSize: 11.5, color: AppTheme.textMuted)),
                    Text(
                      CurrencyHelper.format(r.totalRefund),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5, color: AppTheme.accentRed),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _dateChip(String key, String label) {
    final selected = _txPreset == key;
    return ChoiceChip(
      label: Text(label, style: TextStyle(fontSize: 12, color: selected ? Colors.white : AppTheme.textDark)),
      selected: selected,
      selectedColor: AppTheme.primaryGreen,
      onSelected: (_) => _setDatePreset(key),
    );
  }

  Widget _buildRefundChip(String method, String label, IconData icon) {
    final selected = _refundMethod == method;
    return InkWell(
      onTap: () => setState(() => _refundMethod = method),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primaryGreenSoft : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? AppTheme.primaryGreen : Colors.grey.shade300, width: selected ? 1.8 : 1),
        ),
        child: Column(
          children: [
            Icon(icon, size: 18, color: selected ? AppTheme.primaryGreen : AppTheme.textMuted),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10.5, fontWeight: selected ? FontWeight.bold : FontWeight.normal),
            ),
          ],
        ),
      ),
    );
  }
}
