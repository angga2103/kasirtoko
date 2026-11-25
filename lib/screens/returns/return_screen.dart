import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../database/db_helper.dart';
import '../../models/inventory_movement.dart';
import '../../models/product.dart';
import '../../models/return_exchange_item.dart';
import '../../models/return_item.dart';
import '../../models/return_order.dart';
import '../../models/transaction.dart';
import '../../models/user.dart';
import '../../providers/auth_provider.dart';
import '../../providers/cash_flow_provider.dart';
import '../../providers/customer_provider.dart';
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
  final TextEditingController _transferAccCtrl = TextEditingController();
  final TextEditingController _transferRefCtrl = TextEditingController();

  String _txPreset = 'today'; // 'today' | '7d' | '30d' | 'custom'
  late DateTime _txStart;
  late DateTime _txEnd;
  String? _barcodeFilter;

  List<TransactionModel> _recentTransactions = [];
  List<ReturnOrderModel> _returnHistory = [];
  List<ProductModel> _quarantineProducts = [];
  List<InventoryMovementModel> _movements = [];
  String _movementFilter = '';

  bool _loadingList = true;
  bool _loadingTxDetail = false;
  bool _submitting = false;

  TransactionModel? _selectedTransaction;
  final Map<int, Map<String, dynamic>> _itemReturnState = {};
  final List<ReturnExchangeItemModel> _exchangeItems = [];

  String _refundMethod = RefundMethods.tunai;
  String _diffOrExcessMethod = RefundMethods.tunai;
  int? _overrideCustomerId;
  String _overrideCustomerName = '';
  double _selectedCustomerDebt = 0.0;
  double _selectedCustomerCredit = 0.0;
  String _activeIdempotencyKey = const Uuid().v4();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    final now = DateTime.now();
    _txStart = DateTime(now.year, now.month, now.day);
    _txEnd = DateTime(now.year, now.month, now.day, 23, 59, 59);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAllData();
      Provider.of<CashFlowProvider>(context, listen: false).checkOpenShift();
      Provider.of<CustomerProvider>(context, listen: false).loadCustomers();
      Provider.of<ProductProvider>(context, listen: false).loadProducts();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    _returnNoteCtrl.dispose();
    _transferAccCtrl.dispose();
    _transferRefCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAllData() async {
    setState(() => _loadingList = true);
    final txs = await DatabaseHelper.instance.getTransactionsByDateRange(
      _txStart,
      _txEnd,
      query: _searchCtrl.text.trim(),
      barcode: _barcodeFilter,
      limit: 150,
    );
    final rets = await DatabaseHelper.instance.getReturnOrders(
      start: _txStart.subtract(const Duration(days: 60)),
      end: DateTime.now().add(const Duration(days: 1)),
      limit: 120,
      includeVoided: true,
    );
    final quarantine = await DatabaseHelper.instance.getQuarantineAndDamagedProducts();
    final movs = await DatabaseHelper.instance.getInventoryMovements(
      movementType: _movementFilter.isEmpty ? null : _movementFilter,
      limit: 150,
    );
    if (!mounted) return;
    setState(() {
      _recentTransactions = txs;
      _returnHistory = rets;
      _quarantineProducts = quarantine;
      _movements = movs;
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
    await _loadAllData();
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
      await _loadAllData();
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

  Future<void> _refreshCustomerBalances() async {
    final cid = _effectiveCustomerId;
    if (cid == null) {
      if (mounted) {
        setState(() {
          _selectedCustomerDebt = 0.0;
          _selectedCustomerCredit = 0.0;
        });
      }
      return;
    }
    final debt = await DatabaseHelper.instance.getCustomerOutstandingDebt(cid, _effectiveCustomerName);
    final credit = await DatabaseHelper.instance.getCustomerCreditBalance(cid);
    if (!mounted) return;
    setState(() {
      _selectedCustomerDebt = debt;
      _selectedCustomerCredit = credit;
    });
  }

  int? get _effectiveCustomerId => _overrideCustomerId ?? _selectedTransaction?.customerId;
  String get _effectiveCustomerName {
    if (_overrideCustomerId != null && _overrideCustomerName.isNotEmpty) return _overrideCustomerName;
    return _selectedTransaction?.customerName ?? 'Pelanggan Umum';
  }

  Future<void> _loadTransactionForReturn(TransactionModel trx) async {
    setState(() {
      _loadingTxDetail = true;
      _selectedTransaction = null;
      _itemReturnState.clear();
      _exchangeItems.clear();
      _overrideCustomerId = trx.customerId;
      _overrideCustomerName = trx.customerName;
      _activeIdempotencyKey = const Uuid().v4();
    });

    final returnedMap = trx.id != null
        ? await DatabaseHelper.instance.getReturnedQuantitiesForTransaction(trx.id!)
        : <String, double>{};

    if (!mounted) return;
    final products = Provider.of<ProductProvider>(context, listen: false).products;
    setState(() {
      _loadingTxDetail = false;
      _selectedTransaction = trx;
      _refundMethod = trx.paymentMethod == 'kasbon' ? RefundMethods.potongPiutang : RefundMethods.tunai;
      _diffOrExcessMethod = _refundMethod == RefundMethods.potongPiutang && trx.customerId != null
          ? RefundMethods.saldoKredit
          : RefundMethods.tunai;

      for (int i = 0; i < trx.items.length; i++) {
        final item = trx.items[i];
        final key = '${item.productId}_${item.unitName}';
        final alreadyReturned = returnedMap[key] ?? 0.0;
        final remainingQty = (item.qty - alreadyReturned).clamp(0.0, item.qty);
        final prodMatch = products.where((p) => p.id == item.productId).firstOrNull;
        final tracksStock = !item.isService && (prodMatch == null || prodMatch.managesStock);
        final effectiveUnitRefund = DatabaseHelper.effectiveUnitPriceForReturn(trx, item);

        _itemReturnState[i] = {
          'selected': false,
          'qty': remainingQty > 0 ? (remainingQty >= 1 ? 1.0 : remainingQty) : 0.0,
          'maxQty': remainingQty,
          'alreadyReturned': alreadyReturned,
          'effectiveUnitRefund': effectiveUnitRefund,
          'condition': ReturnConditions.baik,
          'stockTreatment': tracksStock ? StockTreatments.restockSellable : StockTreatments.noStockChange,
          'tracksStock': tracksStock,
        };
      }
    });

    await _refreshCustomerBalances();

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
        final qty = state['qty'] as double;
        final unitRefund = state['effectiveUnitRefund'] as double;
        total += (qty * unitRefund);
      }
    });
    return total;
  }

  double get _totalExchangeAmount =>
      _exchangeItems.fold(0.0, (s, item) => s + item.subtotal);

  double get _exchangeDifference => _totalExchangeAmount - _totalRefundAmount;

  void _pickExchangeProductDialog() {
    final products = Provider.of<ProductProvider>(context, listen: false).products;
    String filter = '';
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDState) {
          final filtered = products.where((p) {
            if (!p.isActive) return false;
            if (filter.trim().isEmpty) return true;
            final q = filter.trim().toLowerCase();
            return p.name.toLowerCase().contains(q) ||
                p.code.toLowerCase().contains(q) ||
                p.barcode.toLowerCase().contains(q);
          }).toList();

          return AlertDialog(
            title: const Text('Pilih Barang Pengganti'),
            content: SizedBox(
              width: 460,
              height: 420,
              child: Column(
                children: [
                  TextField(
                    decoration: const InputDecoration(
                      hintText: 'Cari nama, SKU, atau barcode produk...',
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                    onChanged: (v) => setDState(() => filter = v),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: ListView.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, idx) {
                        final p = filtered[idx];
                        final alreadyChosenQty = _exchangeItems
                            .where((e) => e.productId == p.id)
                            .fold(0.0, (s, e) => s + e.qty);
                        final returnedQtyBackToSellable = _getSelectedSellableReturnQtyForProduct(p.id ?? -1);
                        final effectiveAvailStock = p.stock + returnedQtyBackToSellable - alreadyChosenQty;
                        final canSelect = !p.managesStock || effectiveAvailStock >= 1.0 - 0.0001;

                        return ListTile(
                          enabled: canSelect,
                          title: Text('${p.name} (${p.code})', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          subtitle: Text(
                            'Harga: ${CurrencyHelper.format(p.sellingPrice)} • Stok Jual: ${p.stock.toStringAsFixed(p.stock.truncateToDouble() == p.stock ? 0 : 1)} ${p.baseUnit}'
                            '${returnedQtyBackToSellable > 0 ? " (+${returnedQtyBackToSellable.toStringAsFixed(0)} dari retur ini)" : ""}',
                            style: TextStyle(fontSize: 11.5, color: canSelect ? AppTheme.textMuted : AppTheme.accentRed),
                          ),
                          trailing: canSelect
                              ? ElevatedButton(
                                  onPressed: () {
                                    setState(() {
                                      final existingIdx = _exchangeItems.indexWhere((e) => e.productId == p.id);
                                      if (existingIdx != -1) {
                                        final ex = _exchangeItems[existingIdx];
                                        _exchangeItems[existingIdx] = ReturnExchangeItemModel(
                                          productId: ex.productId,
                                          sku: ex.sku,
                                          productName: ex.productName,
                                          unitName: ex.unitName,
                                          conversionFactor: ex.conversionFactor,
                                          qty: ex.qty + 1,
                                          unitPrice: ex.unitPrice,
                                          costPrice: ex.costPrice,
                                        );
                                      } else {
                                        _exchangeItems.add(
                                          ReturnExchangeItemModel(
                                            productId: p.id!,
                                            sku: p.code,
                                            productName: p.name,
                                            unitName: p.baseUnit,
                                            conversionFactor: 1.0,
                                            qty: 1.0,
                                            unitPrice: p.sellingPrice,
                                            costPrice: p.costPrice,
                                          ),
                                        );
                                      }
                                      if (_exchangeDifference > 0.01 &&
                                          _diffOrExcessMethod == RefundMethods.potongPiutang) {
                                        _diffOrExcessMethod = RefundMethods.tunai;
                                      }
                                    });
                                    Navigator.pop(ctx);
                                  },
                                  child: const Text('Pilih', style: TextStyle(fontSize: 11.5)),
                                )
                              : const Text('Habis', style: TextStyle(fontSize: 11, color: AppTheme.accentRed)),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Tutup')),
            ],
          );
        },
      ),
    );
  }

  double _getSelectedSellableReturnQtyForProduct(int productId) {
    if (_selectedTransaction == null) return 0.0;
    double sum = 0.0;
    _itemReturnState.forEach((index, state) {
      if (state['selected'] == true && state['stockTreatment'] == StockTreatments.restockSellable) {
        final item = _selectedTransaction!.items[index];
        if (item.productId == productId) {
          sum += ((state['qty'] as double) * item.conversionFactor);
        }
      }
    });
    return sum;
  }

  Future<void> _confirmAndProcessReturn() async {
    if (_selectedTransaction == null || _submitting) return;
    final totalRefund = _totalRefundAmount;
    if (totalRefund <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pilih minimal 1 barang dengan jumlah valid untuk diretur.')),
      );
      return;
    }
    if (_refundMethod == RefundMethods.tukarBarang && _exchangeItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tukar Barang wajib memilih minimal 1 produk pengganti agar stok pengganti terpotong.'),
          backgroundColor: AppTheme.accentRed,
        ),
      );
      return;
    }

    final needsCustForCredit = _refundMethod == RefundMethods.saldoKredit ||
        ((_refundMethod == RefundMethods.potongPiutang ||
                (_refundMethod == RefundMethods.tukarBarang && _exchangeDifference.abs() > 0.01)) &&
            _diffOrExcessMethod == RefundMethods.saldoKredit);
    if (needsCustForCredit &&
        (_effectiveCustomerId == null || _effectiveCustomerName.trim().toLowerCase() == 'pelanggan umum')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Saldo Kredit Retur hanya dapat diberikan ke Pelanggan Terdaftar. Pilih pelanggan dahulu.'),
          backgroundColor: AppTheme.accentRed,
        ),
      );
      return;
    }

    final cashFlow = Provider.of<CashFlowProvider>(context, listen: false);
    final touchesDrawerCash = (_refundMethod == RefundMethods.tunai) ||
        (_refundMethod == RefundMethods.tukarBarang &&
            _exchangeDifference.abs() > 0.01 &&
            _diffOrExcessMethod == RefundMethods.tunai) ||
        (_refundMethod == RefundMethods.potongPiutang &&
            totalRefund > _selectedCustomerDebt &&
            _diffOrExcessMethod == RefundMethods.tunai);
    if (touchesDrawerCash && !cashFlow.isShiftOpen) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Shift kasir harus terbuka untuk transaksi yang menyentuh uang Kas Laci.'),
          backgroundColor: AppTheme.accentRed,
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.fact_check_rounded, color: AppTheme.primaryGreen),
            SizedBox(width: 8),
            Expanded(child: Text('Konfirmasi Proses Retur')),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Nota Asli: #${_selectedTransaction!.invoiceNumber}', style: const TextStyle(fontWeight: FontWeight.bold)),
              Text('Pelanggan: $_effectiveCustomerName'),
              const Divider(),
              Text('Metode Penyelesaian: ${RefundMethods.label(_refundMethod)}', style: const TextStyle(fontWeight: FontWeight.w600)),
              Text('Total Nilai Barang Diretur: ${CurrencyHelper.format(totalRefund)}'),
              if (_refundMethod == RefundMethods.tukarBarang) ...[
                Text('Total Barang Pengganti (${_exchangeItems.length} SKU): ${CurrencyHelper.format(_totalExchangeAmount)}'),
                Text(
                  _exchangeDifference.abs() <= 0.01
                      ? 'Selisih Harga: Rp 0 (Tukar Setara)'
                      : (_exchangeDifference > 0
                          ? 'Pelanggan Bayar Tambahan: ${CurrencyHelper.format(_exchangeDifference)} (${RefundMethods.label(_diffOrExcessMethod)})'
                          : 'Toko Kembalikan Selisih: ${CurrencyHelper.format(-_exchangeDifference)} (${RefundMethods.label(_diffOrExcessMethod)})'),
                  style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.accentBlue),
                ),
              ],
              const SizedBox(height: 8),
              const Text('Dampak Stok:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              ..._buildStockImpactSummaryLines().map((line) => Text('• $line', style: const TextStyle(fontSize: 11.5))),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Periksa Lagi')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Ya, Proses Retur')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await _executeReturnSubmit();
  }

  List<String> _buildStockImpactSummaryLines() {
    if (_selectedTransaction == null) return [];
    final lines = <String>[];
    _itemReturnState.forEach((index, state) {
      if (state['selected'] == true) {
        final item = _selectedTransaction!.items[index];
        final qty = state['qty'] as double;
        final treat = state['stockTreatment'] as String;
        lines.add('${item.productName} ($qty ${item.unitName}) -> ${StockTreatments.label(treat)}');
      }
    });
    if (_refundMethod == RefundMethods.tukarBarang) {
      for (final ex in _exchangeItems) {
        lines.add('${ex.productName} (-${ex.qty} ${ex.unitName}) -> Keluar sebagai Barang Pengganti');
      }
    }
    return lines;
  }

  String _buildFinancialImpactPreviewText() {
    final total = _totalRefundAmount;
    switch (_refundMethod) {
      case RefundMethods.tukarBarang:
        final diff = _exchangeDifference;
        if (diff.abs() <= 0.01) {
          return 'Keuangan: Tukar setara (${CurrencyHelper.format(total)}), saldo kas laci tidak berubah.';
        } else if (diff > 0) {
          return 'Keuangan: Pelanggan bayar tambahan ${CurrencyHelper.format(diff)} via ${RefundMethods.label(_diffOrExcessMethod)}.';
        } else {
          return 'Keuangan: Toko kembalikan selisih ${CurrencyHelper.format(-diff)} via ${RefundMethods.label(_diffOrExcessMethod)}.';
        }
      case RefundMethods.tunai:
        return 'Keuangan: Kas laci berkurang ${CurrencyHelper.format(total)}.';
      case RefundMethods.transfer:
        return 'Keuangan: Keluar via Transfer Bank ${CurrencyHelper.format(total)} (kas laci tetap).';
      case RefundMethods.qrisManual:
        return 'Keuangan: Refund QRIS/E-Wallet manual ${CurrencyHelper.format(total)} (kas laci tetap).';
      case RefundMethods.saldoKredit:
        return 'Keuangan: Saldo Kredit $_effectiveCustomerName bertambah +${CurrencyHelper.format(total)} (kewajiban toko).';
      case RefundMethods.potongPiutang:
        final debtCut = total.clamp(0.0, _selectedCustomerDebt);
        final excess = (total - debtCut).clamp(0.0, total);
        return excess > 0.01
            ? 'Keuangan: Piutang terpotong ${CurrencyHelper.format(debtCut)}, sisa ${CurrencyHelper.format(excess)} ke ${RefundMethods.label(_diffOrExcessMethod)}.'
            : 'Keuangan: Piutang $_effectiveCustomerName berkurang ${CurrencyHelper.format(debtCut)}.';
      default:
        return '';
    }
  }

  Future<void> _executeReturnSubmit() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final productProv = Provider.of<ProductProvider>(context, listen: false);
    final cashFlow = Provider.of<CashFlowProvider>(context, listen: false);
    final debtProv = Provider.of<DebtProvider>(context, listen: false);
    final cashier = auth.currentUser;

    final returnNumber = 'RET-${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}';
    final returnItems = <ReturnItemModel>[];
    _itemReturnState.forEach((index, state) {
      if (state['selected'] == true) {
        final item = _selectedTransaction!.items[index];
        final qty = state['qty'] as double;
        final unitRefund = state['effectiveUnitRefund'] as double;
        final condition = state['condition'] as String;
        final treatment = state['stockTreatment'] as String;
        returnItems.add(
          ReturnItemModel(
            productId: item.productId,
            sku: item.productCode,
            productName: item.productName,
            unitName: item.unitName,
            conversionFactor: item.conversionFactor,
            purchasedQty: item.qty,
            previouslyReturnedQty: (state['alreadyReturned'] as num).toDouble(),
            returnQty: qty,
            refundPrice: unitRefund,
            costPrice: item.costPrice,
            subtotal: qty * unitRefund,
            condition: condition,
            stockTreatment: treatment,
          ),
        );
      }
    });

    final totalRefund = _totalRefundAmount;
    final returnOrder = ReturnOrderModel(
      returnNumber: returnNumber,
      transactionId: _selectedTransaction!.id!,
      invoiceNumber: _selectedTransaction!.invoiceNumber,
      date: DateTime.now(),
      cashierId: cashier?.id ?? 1,
      cashierName: cashier?.name ?? 'Kasir',
      customerId: _effectiveCustomerId,
      customerName: _effectiveCustomerName,
      totalRefund: totalRefund,
      refundMethod: _refundMethod,
      reason: _returnNoteCtrl.text.trim(),
      note: _returnNoteCtrl.text.trim(),
      exchangeTotal: _refundMethod == RefundMethods.tukarBarang ? _totalExchangeAmount : 0.0,
      differenceAmount: _refundMethod == RefundMethods.tukarBarang ? _exchangeDifference : 0.0,
      differencePaymentMethod: _diffOrExcessMethod,
      transferAccount: _transferAccCtrl.text.trim(),
      transferReference: _transferRefCtrl.text.trim(),
      idempotencyKey: _activeIdempotencyKey,
      items: returnItems,
      exchangeItems: _refundMethod == RefundMethods.tukarBarang ? List.from(_exchangeItems) : [],
    );

    setState(() => _submitting = true);
    try {
      await DatabaseHelper.instance.insertReturnOrder(
        returnOrder,
        shiftId: cashFlow.currentShift?.id,
      );

      await auth.logAction(
        'retur_transaksi',
        'Retur nota #${_selectedTransaction!.invoiceNumber} ($returnNumber) [${RefundMethods.label(_refundMethod)}]: ${returnItems.length} item, Nilai: ${CurrencyHelper.format(totalRefund)}',
        module: 'retur',
        objectId: returnNumber,
      );

      await productProv.loadProducts();
      await cashFlow.checkOpenShift();
      await debtProv.loadDebts();
      await _loadAllData();

      if (!mounted) return;
      final inv = _selectedTransaction!.invoiceNumber;
      final usedExchange = _refundMethod == RefundMethods.tukarBarang;
      final usedMethodLabel = RefundMethods.label(_refundMethod);
      final diffVal = _exchangeDifference;
      final stockSummary = _buildStockImpactSummaryLines();

      setState(() {
        _submitting = false;
        _selectedTransaction = null;
        _itemReturnState.clear();
        _exchangeItems.clear();
        _returnNoteCtrl.clear();
        _transferAccCtrl.clear();
        _transferRefCtrl.clear();
        _activeIdempotencyKey = const Uuid().v4();
      });

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.check_circle_rounded, color: AppTheme.primaryGreen),
              SizedBox(width: 8),
              Expanded(child: Text('Retur Tercatat di Ledger!')),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('No. Retur: $returnNumber', style: const TextStyle(fontWeight: FontWeight.bold)),
                Text('Nota Asli: #$inv'),
                Text('Metode: $usedMethodLabel'),
                Text('Nilai Barang Retur: ${CurrencyHelper.format(totalRefund)}',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryGreen)),
                if (usedExchange)
                  Text(
                    diffVal.abs() <= 0.01
                        ? 'Selisih Tukar: Rp 0'
                        : (diffVal > 0
                            ? 'Tambahan Bayar: ${CurrencyHelper.format(diffVal)}'
                            : 'Selisih Dikembalikan: ${CurrencyHelper.format(-diffVal)}'),
                  ),
                const SizedBox(height: 8),
                const Text('Mutasi Stok Tercatat:', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                ...stockSummary.map((l) => Text('• $l', style: const TextStyle(fontSize: 11, color: AppTheme.textMuted))),
              ],
            ),
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

  Future<void> _promptVoidReturn(ReturnOrderModel ro) async {
    final reasonCtrl = TextEditingController();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Batalkan Retur ${ro.returnNumber}?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Pembatalan (Void) akan membalikkan semua mutasi stok, stok pengganti, saldo kredit, piutang, dan arus kas secara atomik.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              decoration: const InputDecoration(
                labelText: 'Alasan Pembatalan Retur *',
                hintText: 'Contoh: Salah input item retur',
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Tutup')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accentRed),
            onPressed: () {
              if (reasonCtrl.text.trim().isEmpty) return;
              Navigator.pop(ctx, true);
            },
            child: const Text('YA, BATALKAN RETUR'),
          ),
        ],
      ),
    );
    final reason = reasonCtrl.text.trim();
    reasonCtrl.dispose();
    if (confirm != true || reason.isEmpty || ro.id == null || !mounted) return;

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final cashFlow = Provider.of<CashFlowProvider>(context, listen: false);
    final productProv = Provider.of<ProductProvider>(context, listen: false);
    final debtProv = Provider.of<DebtProvider>(context, listen: false);

    try {
      await DatabaseHelper.instance.voidReturnOrder(
        returnOrderId: ro.id!,
        userId: auth.currentUser?.id ?? 1,
        userName: auth.currentUser?.name ?? 'Admin',
        reason: reason,
        shiftId: cashFlow.currentShift?.id,
      );
      await productProv.loadProducts();
      await cashFlow.checkOpenShift();
      await debtProv.loadDebts();
      await _loadAllData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Retur ${ro.returnNumber} berhasil di-VOID.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceFirst('Bad state: ', '')),
            backgroundColor: AppTheme.accentRed,
          ),
        );
      }
    }
  }

  Future<void> _promptReleaseQuarantine(ProductModel p, String destination) async {
    final qtyCtrl = TextEditingController(text: p.quarantineStock.toStringAsFixed(p.quarantineStock.truncateToDouble() == p.quarantineStock ? 0 : 1));
    final noteCtrl = TextEditingController();
    final isSellable = destination == 'sellable';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isSellable ? 'Lulus Inspeksi -> Stok Jual' : 'Afkir -> Stok Rusak'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${p.name} (Karantina: ${p.quarantineStock} ${p.baseUnit})',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            TextField(
              controller: qtyCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: 'Jumlah (${p.baseUnit})'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: noteCtrl,
              decoration: const InputDecoration(labelText: 'Catatan Inspeksi (Opsional)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(isSellable ? 'Pindah ke Stok Jual' : 'Catat Rusak'),
          ),
        ],
      ),
    );
    final qty = double.tryParse(qtyCtrl.text.trim()) ?? 0.0;
    final note = noteCtrl.text.trim();
    qtyCtrl.dispose();
    noteCtrl.dispose();
    if (ok != true || qty <= 0 || p.id == null || !mounted) return;

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final productProv = Provider.of<ProductProvider>(context, listen: false);
    try {
      await DatabaseHelper.instance.releaseQuarantineStock(
        productId: p.id!,
        qty: qty,
        destination: destination,
        userId: auth.currentUser?.id ?? 1,
        userName: auth.currentUser?.name ?? 'Kasir',
        note: note,
      );
      await productProv.loadProducts();
      await _loadAllData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Karantina ${p.name} (${qty.toStringAsFixed(1)} ${p.baseUnit}) dipindahkan ke ${isSellable ? "Stok Jual" : "Stok Rusak"}.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Bad state: ', '')), backgroundColor: AppTheme.accentRed),
        );
      }
    }
  }

  Future<void> _showLegacyReconciliationModal() async {
    final findings = await DatabaseHelper.instance.getLegacyReturnReconciliationReport();
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Audit & Rekonsiliasi Retur Lama'),
        content: SizedBox(
          width: 480,
          child: findings.isEmpty
              ? const Text(
                  'Bersih! Tidak ditemukan data retur anomali tanpa mutasi keluar/ledger.',
                  style: TextStyle(color: AppTheme.primaryGreen, fontWeight: FontWeight.w600),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: findings.length,
                  separatorBuilder: (_, __) => const Divider(),
                  itemBuilder: (_, idx) {
                    final f = findings[idx];
                    final isHigh = f['severity'] == 'HIGH';
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        isHigh ? Icons.warning_amber_rounded : Icons.info_outline_rounded,
                        color: isHigh ? AppTheme.accentRed : AppTheme.accentOrange,
                      ),
                      title: Text('${f['returnNumber']} • Nota #${f['invoiceNumber']}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                      subtitle: Text(f['message'].toString(), style: const TextStyle(fontSize: 11.5)),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Tutup')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Retur & Tukar Barang'),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: AppTheme.accentOrange,
          isScrollable: true,
          tabs: [
            const Tab(text: 'Proses Retur'),
            Tab(text: 'Riwayat Retur (${_returnHistory.length})'),
            Tab(text: 'Karantina & Mutasi (${_quarantineProducts.length})'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildProcessReturnTab(),
          _buildHistoryTab(),
          _buildQuarantineAndMovementsTab(),
        ],
      ),
    );
  }

  Widget _buildProcessReturnTab() {
    final custProv = Provider.of<CustomerProvider>(context);
    final registeredCustomers = custProv.customers
        .where((c) => c.id != null && c.name.trim().toLowerCase() != 'pelanggan umum')
        .toList();

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 920),
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
                                        _loadAllData();
                                      },
                                    )
                                  : null,
                            ),
                            onChanged: (_) => _loadAllData(),
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
                          _loadAllData();
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
                              Icons.receipt_long_rounded,
                              color: isVoided ? AppTheme.accentRed : AppTheme.primaryGreen,
                              size: 20,
                            ),
                          ),
                          title: Text(
                            '#${t.invoiceNumber} • ${t.customerName}',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                          ),
                          subtitle: Text(
                            '${DateHelper.formatFull(t.date)} • ${t.items.length} item • ${t.paymentMethod.toUpperCase()} [${t.status.toUpperCase()}]',
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
                TextButton.icon(
                  onPressed: () => setState(() {
                    _selectedTransaction = null;
                    _exchangeItems.clear();
                  }),
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
                        'Pelanggan Nota: $_effectiveCustomerName • Bayar Asli: ${_selectedTransaction!.paymentMethod.toUpperCase()}',
                        style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                      ),
                      if (_selectedCustomerDebt > 0 || _selectedCustomerCredit > 0) ...[
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          children: [
                            if (_selectedCustomerDebt > 0)
                              Chip(
                                visualDensity: VisualDensity.compact,
                                backgroundColor: AppTheme.accentRedSoft,
                                label: Text('Piutang Aktif: ${CurrencyHelper.format(_selectedCustomerDebt)}',
                                    style: const TextStyle(fontSize: 11, color: AppTheme.accentRed, fontWeight: FontWeight.bold)),
                              ),
                            if (_selectedCustomerCredit > 0)
                              Chip(
                                visualDensity: VisualDensity.compact,
                                backgroundColor: AppTheme.accentBlue.withValues(alpha: 0.12),
                                label: Text('Saldo Kredit: ${CurrencyHelper.format(_selectedCustomerCredit)}',
                                    style: const TextStyle(fontSize: 11, color: AppTheme.accentBlue, fontWeight: FontWeight.bold)),
                              ),
                          ],
                        ),
                      ],
                      if (_selectedTransaction!.customerId == null && registeredCustomers.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        DropdownButtonFormField<int?>(
                          value: _overrideCustomerId,
                          isDense: true,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Tautkan Pelanggan Terdaftar (Wajib jika Saldo Kredit)',
                            prefixIcon: Icon(Icons.person_search_rounded, size: 18),
                          ),
                          items: [
                            const DropdownMenuItem<int?>(value: null, child: Text('Pelanggan Umum (Anonim)')),
                            ...registeredCustomers.map((c) => DropdownMenuItem<int?>(
                                  value: c.id,
                                  child: Text('${c.name} (${c.phone})', overflow: TextOverflow.ellipsis),
                                )),
                          ],
                          onChanged: (cid) async {
                            final picked = registeredCustomers.where((c) => c.id == cid).firstOrNull;
                            setState(() {
                              _overrideCustomerId = cid;
                              _overrideCustomerName = picked?.name ?? 'Pelanggan Umum';
                            });
                            await _refreshCustomerBalances();
                          },
                        ),
                      ],
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
                      'Perhatian: Nota ini sudah memiliki retur aktif sebelumnya. Kuantitas maksimal dibatasi ke sisa yang belum diretur.',
                      style: TextStyle(fontSize: 11.5, color: AppTheme.accentOrange, fontWeight: FontWeight.w600),
                    ),
                  ),

                const Text('1. Pilih Barang Diretur, Kondisi & Perlakuan Stok:',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
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
                    final effPrice = (state['effectiveUnitRefund'] as num).toDouble();
                    final condition = state['condition'] as String;
                    final treatment = state['stockTreatment'] as String;
                    final tracksStock = (state['tracksStock'] as bool?) ?? true;
                    final canReturn =
                        _selectedTransaction!.status != 'void' && _selectedTransaction!.status != 'voided' && maxQty > 0;
                    final allowDecimal = maxQty != maxQty.truncateToDouble() || item.qty != item.qty.truncateToDouble();

                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
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
                                        '${item.productName}${!tracksStock ? " (Jasa/Non-Stok)" : ""}',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                          color: canReturn ? AppTheme.textDark : AppTheme.textMuted,
                                        ),
                                      ),
                                      Text(
                                        alreadyReturned > 0
                                            ? 'Beli: ${item.qty} • Pernah retur: $alreadyReturned • Sisa maks: $maxQty ${item.unitName} @ ${CurrencyHelper.format(effPrice)}'
                                            : 'Beli: ${item.qty} ${item.unitName} • Nilai efektif: ${CurrencyHelper.format(effPrice)} / ${item.unitName}',
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
                                    CurrencyHelper.format(currentQty * effPrice),
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                  )
                                else if (maxQty <= 0)
                                  const Text('Habis Diretur', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                              ],
                            ),
                            if (isSelected && canReturn) ...[
                              const Divider(height: 12),
                              Row(
                                children: [
                                  const Text('Qty Retur: ', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
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
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 10,
                                runSpacing: 8,
                                children: [
                                  SizedBox(
                                    width: 240,
                                    child: DropdownButtonFormField<String>(
                                      value: condition,
                                      isDense: true,
                                      decoration: const InputDecoration(labelText: 'Kondisi Barang'),
                                      items: ReturnConditions.all
                                          .map((c) => DropdownMenuItem(value: c, child: Text(ReturnConditions.label(c), style: const TextStyle(fontSize: 12))))
                                          .toList(),
                                      onChanged: (val) {
                                        if (val == null) return;
                                        setState(() {
                                          state['condition'] = val;
                                          state['stockTreatment'] = StockTreatments.defaultForCondition(
                                            val,
                                            tracksStock: tracksStock,
                                          );
                                        });
                                      },
                                    ),
                                  ),
                                  SizedBox(
                                    width: 260,
                                    child: DropdownButtonFormField<String>(
                                      value: tracksStock ? treatment : StockTreatments.noStockChange,
                                      isDense: true,
                                      decoration: const InputDecoration(labelText: 'Perlakuan Stok'),
                                      items: (tracksStock ? StockTreatments.all : [StockTreatments.noStockChange])
                                          .map((t) => DropdownMenuItem(value: t, child: Text(StockTreatments.label(t), style: const TextStyle(fontSize: 12))))
                                          .toList(),
                                      onChanged: tracksStock
                                          ? (val) {
                                              if (val != null) setState(() => state['stockTreatment'] = val);
                                            }
                                          : null,
                                    ),
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

                // Step 4: Settlement Method & Exchange Section
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: AppTheme.cardDecoration(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('2. Metode Penyelesaian Retur:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      GridView.count(
                        crossAxisCount: MediaQuery.sizeOf(context).width >= AppBreakpoints.tablet ? 3 : 2,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                        childAspectRatio: 2.8,
                        children: [
                          _buildRefundChip(RefundMethods.tukarBarang, 'Tukar Barang', Icons.swap_horiz_rounded),
                          _buildRefundChip(RefundMethods.tunai, 'Tunai (Laci)', Icons.money_rounded),
                          _buildRefundChip(RefundMethods.transfer, 'Transfer Bank', Icons.account_balance_rounded),
                          _buildRefundChip(RefundMethods.saldoKredit, 'Saldo Kredit', Icons.account_balance_wallet_rounded),
                          _buildRefundChip(RefundMethods.potongPiutang, 'Potong Piutang', Icons.receipt_long_rounded),
                          _buildRefundChip(RefundMethods.qrisManual, 'QRIS Manual', Icons.qr_code_2_rounded),
                        ],
                      ),

                      // TUKAR BARANG PANEL
                      if (_refundMethod == RefundMethods.tukarBarang) ...[
                        const Divider(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Expanded(
                              child: Text(
                                'Produk Pengganti (Stok Otomatis Terpotong)',
                                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                              ),
                            ),
                            ElevatedButton.icon(
                              onPressed: _pickExchangeProductDialog,
                              icon: const Icon(Icons.add_shopping_cart_rounded, size: 16),
                              label: const Text('Pilih Pengganti', style: TextStyle(fontSize: 12)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (_exchangeItems.isEmpty)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppTheme.accentRedSoft,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'Belum ada produk pengganti dipilih. Pilih produk pengganti di atas (bisa SKU sama atau berbeda).',
                              style: TextStyle(fontSize: 11.5, color: AppTheme.accentRed),
                            ),
                          )
                        else ...[
                          ...List.generate(_exchangeItems.length, (i) {
                            final ex = _exchangeItems[i];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 6),
                              color: Colors.blue.shade50,
                              child: ListTile(
                                dense: true,
                                title: Text('${ex.productName} (${ex.sku})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                                subtitle: Text('${ex.qty} ${ex.unitName} @ ${CurrencyHelper.format(ex.unitPrice)} = ${CurrencyHelper.format(ex.subtotal)}'),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.remove_circle_outline, size: 18),
                                      onPressed: () {
                                        setState(() {
                                          if (ex.qty > 1) {
                                            _exchangeItems[i] = ReturnExchangeItemModel(
                                              productId: ex.productId,
                                              sku: ex.sku,
                                              productName: ex.productName,
                                              unitName: ex.unitName,
                                              conversionFactor: ex.conversionFactor,
                                              qty: ex.qty - 1,
                                              unitPrice: ex.unitPrice,
                                              costPrice: ex.costPrice,
                                            );
                                          } else {
                                            _exchangeItems.removeAt(i);
                                          }
                                        });
                                      },
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppTheme.accentRed),
                                      onPressed: () => setState(() => _exchangeItems.removeAt(i)),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }),
                          const SizedBox(height: 8),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text('Nilai Barang Retur:', style: TextStyle(fontSize: 12)),
                                    Text(CurrencyHelper.format(_totalRefundAmount), style: const TextStyle(fontWeight: FontWeight.w600)),
                                  ],
                                ),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text('Nilai Barang Pengganti:', style: TextStyle(fontSize: 12)),
                                    Text(CurrencyHelper.format(_totalExchangeAmount), style: const TextStyle(fontWeight: FontWeight.w600)),
                                  ],
                                ),
                                const Divider(height: 10),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      _exchangeDifference.abs() <= 0.01
                                          ? 'Selisih Tukar Barang:'
                                          : (_exchangeDifference > 0 ? 'Pelanggan Bayar Tambahan:' : 'Toko Kembalikan Selisih:'),
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                                    ),
                                    Text(
                                      CurrencyHelper.format(_exchangeDifference.abs()),
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: _exchangeDifference > 0
                                            ? AppTheme.primaryGreen
                                            : (_exchangeDifference < 0 ? AppTheme.accentRed : AppTheme.textDark),
                                      ),
                                    ),
                                  ],
                                ),
                                if (_exchangeDifference.abs() > 0.01) ...[
                                  const SizedBox(height: 8),
                                  DropdownButtonFormField<String>(
                                    value: _exchangeDifference > 0
                                        ? ([RefundMethods.tunai, RefundMethods.transfer, 'qris', RefundMethods.saldoKredit]
                                                .contains(_diffOrExcessMethod)
                                            ? _diffOrExcessMethod
                                            : RefundMethods.tunai)
                                        : ([RefundMethods.tunai, RefundMethods.transfer, RefundMethods.qrisManual, RefundMethods.saldoKredit]
                                                .contains(_diffOrExcessMethod)
                                            ? _diffOrExcessMethod
                                            : RefundMethods.tunai),
                                    isDense: true,
                                    decoration: InputDecoration(
                                      labelText: _exchangeDifference > 0
                                          ? 'Metode Bayar Tambahan Pelanggan'
                                          : 'Metode Pengembalian Selisih',
                                    ),
                                    items: _exchangeDifference > 0
                                        ? const [
                                            DropdownMenuItem(value: RefundMethods.tunai, child: Text('Tunai (Masuk Laci)')),
                                            DropdownMenuItem(value: RefundMethods.transfer, child: Text('Transfer Bank')),
                                            DropdownMenuItem(value: 'qris', child: Text('QRIS')),
                                            DropdownMenuItem(value: RefundMethods.saldoKredit, child: Text('Potong Saldo Kredit')),
                                          ]
                                        : const [
                                            DropdownMenuItem(value: RefundMethods.tunai, child: Text('Tunai (Keluar Laci)')),
                                            DropdownMenuItem(value: RefundMethods.transfer, child: Text('Transfer Bank')),
                                            DropdownMenuItem(value: RefundMethods.qrisManual, child: Text('QRIS / E-Wallet Manual')),
                                            DropdownMenuItem(value: RefundMethods.saldoKredit, child: Text('Simpan ke Saldo Kredit')),
                                          ],
                                    onChanged: (val) {
                                      if (val != null) setState(() => _diffOrExcessMethod = val);
                                    },
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ],

                      // EXCESS HANDLER FOR POTONG PIUTANG
                      if (_refundMethod == RefundMethods.potongPiutang) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppTheme.accentOrange.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Sisa Piutang Kasbon Pelanggan: ${CurrencyHelper.format(_selectedCustomerDebt)}',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                              if (_totalRefundAmount > _selectedCustomerDebt + 0.01) ...[
                                const SizedBox(height: 6),
                                Text(
                                  'Kelebihan nilai retur (${CurrencyHelper.format(_totalRefundAmount - _selectedCustomerDebt)}) dialihkan ke:',
                                  style: const TextStyle(fontSize: 11.5, color: AppTheme.accentBlue, fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 6),
                                DropdownButtonFormField<String>(
                                  value: [RefundMethods.saldoKredit, RefundMethods.tunai, RefundMethods.transfer, RefundMethods.qrisManual]
                                          .contains(_diffOrExcessMethod)
                                      ? _diffOrExcessMethod
                                      : RefundMethods.saldoKredit,
                                  isDense: true,
                                  decoration: const InputDecoration(labelText: 'Tujuan Kelebihan Potong Piutang'),
                                  items: const [
                                    DropdownMenuItem(value: RefundMethods.saldoKredit, child: Text('Saldo Kredit Pelanggan')),
                                    DropdownMenuItem(value: RefundMethods.tunai, child: Text('Tunai (Kas Laci)')),
                                    DropdownMenuItem(value: RefundMethods.transfer, child: Text('Transfer Bank')),
                                    DropdownMenuItem(value: RefundMethods.qrisManual, child: Text('QRIS Manual')),
                                  ],
                                  onChanged: (v) {
                                    if (v != null) setState(() => _diffOrExcessMethod = v);
                                  },
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],

                      if (_refundMethod == RefundMethods.transfer ||
                          _refundMethod == RefundMethods.qrisManual ||
                          ((_refundMethod == RefundMethods.tukarBarang || _refundMethod == RefundMethods.potongPiutang) &&
                              (_diffOrExcessMethod == RefundMethods.transfer || _diffOrExcessMethod == RefundMethods.qrisManual))) ...[
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _transferAccCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Nama Bank / E-Wallet',
                                  hintText: 'BCA / BRI / GoPay',
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _transferRefCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'No. Referensi (Opsional)',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],

                      const SizedBox(height: 12),
                      TextField(
                        controller: _returnNoteCtrl,
                        decoration: const InputDecoration(labelText: 'Alasan & Catatan Retur'),
                      ),
                      if (_totalRefundAmount > 0) ...[
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryGreenSoft,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppTheme.primaryGreen.withValues(alpha: 0.3)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Preview Dampak Stok & Keuangan:',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.primaryGreen),
                              ),
                              const SizedBox(height: 4),
                              ..._buildStockImpactSummaryLines().map(
                                (line) => Text('• $line', style: const TextStyle(fontSize: 11.5)),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _buildFinancialImpactPreviewText(),
                                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppTheme.accentBlue),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('TOTAL NILAI RETUR', style: TextStyle(fontWeight: FontWeight.bold)),
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
                          onPressed: (_submitting || _totalRefundAmount <= 0) ? null : _confirmAndProcessReturn,
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
    final auth = Provider.of<AuthProvider>(context);
    final canVoid = auth.hasPermission(AppPermissions.voidTransaction);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _showLegacyReconciliationModal,
                  icon: const Icon(Icons.rule_folder_rounded, size: 18),
                  label: const Text('Cek Audit & Rekonsiliasi Data Retur Lama', style: TextStyle(fontSize: 12)),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _loadingList
              ? const Center(child: CircularProgressIndicator())
              : _returnHistory.isEmpty
                  ? const Center(child: Text('Belum ada riwayat retur barang.'))
                  : ListView.separated(
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
                                  children: [
                                    Expanded(
                                      child: Text(r.returnNumber,
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: r.isVoided ? AppTheme.accentRedSoft : AppTheme.primaryGreenSoft,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        r.isVoided ? 'VOID / DIBATALKAN' : RefundMethods.label(r.refundMethod).toUpperCase(),
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: r.isVoided ? AppTheme.accentRed : AppTheme.primaryGreen,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Nota #${r.invoiceNumber} • ${r.customerName} • ${DateHelper.formatFull(r.date)} • ${r.cashierName}',
                                  style: const TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
                                ),
                                const Divider(height: 12),
                                ...r.items.map((it) => Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 2),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              'Masuk: ${it.productName} (${it.returnQty} ${it.unitName}) • ${ReturnConditions.label(it.condition)} -> ${StockTreatments.label(it.stockTreatment)}',
                                              style: const TextStyle(fontSize: 11.5),
                                            ),
                                          ),
                                          Text(CurrencyHelper.format(it.subtotal),
                                              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
                                        ],
                                      ),
                                    )),
                                if (r.exchangeItems.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  ...r.exchangeItems.map((ex) => Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 2),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                'Keluar Pengganti: ${ex.productName} (${ex.qty} ${ex.unitName})',
                                                style: const TextStyle(fontSize: 11.5, color: AppTheme.accentBlue, fontWeight: FontWeight.w600),
                                              ),
                                            ),
                                            Text(CurrencyHelper.format(ex.subtotal),
                                                style: const TextStyle(fontSize: 11.5, color: AppTheme.accentBlue, fontWeight: FontWeight.w600)),
                                          ],
                                        ),
                                      )),
                                ],
                                const Divider(height: 12),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        r.isVoided
                                            ? 'Dibatalkan oleh ${r.voidedByName}: ${r.voidReason}'
                                            : (r.note.isNotEmpty ? 'Catatan: ${r.note}' : 'Total Nilai Retur'),
                                        style: const TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
                                      ),
                                    ),
                                    Text(
                                      CurrencyHelper.format(r.totalRefund),
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                        decoration: r.isVoided ? TextDecoration.lineThrough : null,
                                        color: r.isVoided ? AppTheme.textMuted : AppTheme.accentRed,
                                      ),
                                    ),
                                  ],
                                ),
                                if (!r.isVoided && canVoid) ...[
                                  const SizedBox(height: 6),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton.icon(
                                      onPressed: () => _promptVoidReturn(r),
                                      icon: const Icon(Icons.undo_rounded, size: 16, color: AppTheme.accentRed),
                                      label: const Text('Batalkan Retur (Void)',
                                          style: TextStyle(fontSize: 11.5, color: AppTheme.accentRed)),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildQuarantineAndMovementsTab() {
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        const Text('Stok Karantina & Rusak / Afkir (Terpisah dari Stok Jual)',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 8),
        if (_quarantineProducts.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: AppTheme.cardDecoration(),
            child: const Text(
              'Tidak ada stok berada di Karantina maupun bucket Rusak/Afkir.',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
            ),
          )
        else
          ..._quarantineProducts.map((p) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${p.name} (${p.code})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 10,
                        children: [
                          Text('Stok Jual: ${p.stock} ${p.baseUnit}', style: const TextStyle(fontSize: 12, color: AppTheme.primaryGreen)),
                          Text('Karantina: ${p.quarantineStock} ${p.baseUnit}',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.accentOrange)),
                          Text('Rusak/Afkir: ${p.damagedStock} ${p.baseUnit}',
                              style: const TextStyle(fontSize: 12, color: AppTheme.accentRed)),
                        ],
                      ),
                      if (p.quarantineStock > 0) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: () => _promptReleaseQuarantine(p, 'sellable'),
                              icon: const Icon(Icons.check_circle_outline_rounded, size: 16, color: AppTheme.primaryGreen),
                              label: const Text('Lulus -> Stok Jual', style: TextStyle(fontSize: 11.5)),
                            ),
                            OutlinedButton.icon(
                              onPressed: () => _promptReleaseQuarantine(p, 'damaged'),
                              icon: const Icon(Icons.report_problem_outlined, size: 16, color: AppTheme.accentRed),
                              label: const Text('Afkir -> Stok Rusak', style: TextStyle(fontSize: 11.5, color: AppTheme.accentRed)),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              )),
        const SizedBox(height: 16),
        const Text('Ledger Mutasi Stok (Inventory Movements)',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _movChip('', 'Semua'),
              const SizedBox(width: 6),
              _movChip(MovementTypes.returnIn, 'Retur Masuk'),
              const SizedBox(width: 6),
              _movChip(MovementTypes.exchangeOut, 'Tukar Keluar'),
              const SizedBox(width: 6),
              _movChip(MovementTypes.quarantineIn, 'Karantina'),
              const SizedBox(width: 6),
              _movChip(MovementTypes.damagedIn, 'Rusak'),
              const SizedBox(width: 6),
              _movChip(MovementTypes.returnVoidReverse, 'Void Retur'),
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (_movements.isEmpty)
          const Padding(
            padding: EdgeInsets.all(20),
            child: Center(child: Text('Belum ada catatan mutasi stok.', style: TextStyle(color: AppTheme.textMuted))),
          )
        else
          ..._movements.map((m) {
            final isPos = m.qtyDelta > 0;
            return Card(
              margin: const EdgeInsets.only(bottom: 6),
              child: ListTile(
                dense: true,
                title: Text(
                  '${m.productName} • ${MovementTypes.label(m.movementType)}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                ),
                subtitle: Text(
                  'Ref: ${m.referenceNumber} • Bucket: ${m.bucket} • Stok Jual: ${m.stockBefore} -> ${m.stockAfter}\n${m.userName} • ${DateHelper.formatFull(m.createdAt)}',
                  style: const TextStyle(fontSize: 11),
                ),
                trailing: Text(
                  '${isPos ? "+" : ""}${m.qtyDelta.toStringAsFixed(m.qtyDelta.truncateToDouble() == m.qtyDelta ? 0 : 1)}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: isPos ? AppTheme.primaryGreen : (m.qtyDelta < 0 ? AppTheme.accentRed : AppTheme.textMuted),
                  ),
                ),
              ),
            );
          }),
      ],
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

  Widget _movChip(String typeKey, String label) {
    final selected = _movementFilter == typeKey;
    return ChoiceChip(
      label: Text(label, style: TextStyle(fontSize: 11.5, color: selected ? Colors.white : AppTheme.textDark)),
      selected: selected,
      selectedColor: AppTheme.accentBlue,
      onSelected: (_) {
        _movementFilter = typeKey;
        _loadAllData();
      },
    );
  }

  Widget _buildRefundChip(String method, String label, IconData icon) {
    final selected = _refundMethod == method;
    return InkWell(
      onTap: () => setState(() {
        _refundMethod = method;
        if (method == RefundMethods.potongPiutang && _effectiveCustomerId != null) {
          _diffOrExcessMethod = RefundMethods.saldoKredit;
        } else if (method != RefundMethods.tukarBarang) {
          _diffOrExcessMethod = method;
        }
      }),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primaryGreenSoft : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? AppTheme.primaryGreen : Colors.grey.shade300, width: selected ? 1.8 : 1),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 17, color: selected ? AppTheme.primaryGreen : AppTheme.textMuted),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, fontWeight: selected ? FontWeight.bold : FontWeight.normal),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
