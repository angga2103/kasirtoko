import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/transaction.dart';
import '../../models/return_order.dart';
import '../../models/return_item.dart';
import '../../database/db_helper.dart';
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

class _ReturnScreenState extends State<ReturnScreen> {
  final TextEditingController _invoiceCtrl = TextEditingController();
  TransactionModel? _selectedTransaction;
  bool _isLoading = false;

  // Track returned item selections: map of item index -> { 'selected': bool, 'qty': double, 'maxQty': double, 'alreadyReturned': double, 'condition': 'baik'/'rusak' }
  final Map<int, Map<String, dynamic>> _itemReturnState = {};
  String _refundMethod = 'tunai';
  final TextEditingController _returnNoteCtrl = TextEditingController();

  @override
  void dispose() {
    _invoiceCtrl.dispose();
    _returnNoteCtrl.dispose();
    super.dispose();
  }

  Future<void> _scanReceiptQr() async {
    final res = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => const BarcodeScannerScreen(
          title: 'Scan QR Footer Struk',
          helperText: 'Arahkan kamera ke QR Code di bagian bawah struk',
          continuousMode: false,
        ),
      ),
    );
    if (res != null && res.isNotEmpty && mounted) {
      await _searchInvoice(res);
    }
  }

  Future<void> _searchInvoice(String rawInput) async {
    String cleanInvoice = rawInput.trim();
    // If input is from QR Code scan (TRX|INV-...|total), parse it
    if (cleanInvoice.startsWith('TRX|')) {
      final parts = cleanInvoice.split('|');
      if (parts.length >= 2) {
        cleanInvoice = parts[1].trim();
      }
    }

    if (cleanInvoice.isEmpty) return;

    setState(() {
      _isLoading = true;
      _selectedTransaction = null;
      _itemReturnState.clear();
    });

    final trx = await DatabaseHelper.instance.getTransactionByInvoice(cleanInvoice);
    Map<String, double> returnedMap = {};
    if (trx != null && trx.id != null) {
      returnedMap = await DatabaseHelper.instance.getReturnedQuantitiesForTransaction(trx.id!);
    }

    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _selectedTransaction = trx;
      if (trx != null) {
        _invoiceCtrl.text = trx.invoiceNumber;
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
            'condition': 'baik', // 'baik' or 'rusak'
          };
        }
      }
    });

    if (trx == null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nomor nota transaksi tidak ditemukan.'),
          backgroundColor: AppTheme.accentRed,
        ),
      );
    } else if (trx != null && (trx.status == 'void' || trx.status == 'voided') && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Transaksi ini sudah dibatalkan (VOID) sehingga tidak dapat diretur.'),
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
    if (_selectedTransaction == null) return;
    final totalRefund = _totalRefundAmount;
    if (totalRefund <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pilih minimal 1 barang untuk diretur.')),
      );
      return;
    }

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final productProv = Provider.of<ProductProvider>(context, listen: false);
    final cashFlow = Provider.of<CashFlowProvider>(context, listen: false);
    final debtProv = Provider.of<DebtProvider>(context, listen: false);
    final cashier = auth.currentUser;

    final returnNumber = 'RET-${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}';

    List<ReturnItemModel> returnItems = [];
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
      note: _returnNoteCtrl.text,
      items: returnItems,
    );

    await DatabaseHelper.instance.insertReturnOrder(
      returnOrder,
      shiftId: cashFlow.currentShift?.id,
    );

    // Audit log
    await auth.logAction(
      'retur_transaksi',
      'Retur nota #${_selectedTransaction!.invoiceNumber}: ${returnItems.length} item, Total Pengembalian: ${CurrencyHelper.format(totalRefund)}',
    );

    // Reload products stock, cashflow shift & debts
    await productProv.loadProducts();
    await cashFlow.checkOpenShift();
    await debtProv.loadDebts();

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
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
              Text('Nota Asli: ${_selectedTransaction!.invoiceNumber}'),
              Text('Total Pengembalian: ${CurrencyHelper.format(totalRefund)}',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryGreen)),
              Text('Metode Refund: ${_refundMethod.toUpperCase()}'),
              const SizedBox(height: 8),
              const Text(
                'Barang kondisi BAIK telah otomatis dikembalikan ke stok rak aktif.',
                style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.pop(context); // back to home
              },
              child: const Text('SELESAI'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Retur Produk'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Search / Scan QR Header
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Pencarian Nota Transaksi:',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _invoiceCtrl,
                          decoration: const InputDecoration(
                            hintText: 'Scan QR di footer struk / ketik No. Nota',
                            hintStyle: TextStyle(fontSize: 12),
                            prefixIcon: Icon(Icons.receipt_rounded, size: 20),
                          ),
                          onSubmitted: _searchInvoice,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Tooltip(
                        message: 'Scan QR Struk',
                        child: OutlinedButton(
                          onPressed: _scanReceiptQr,
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                          ),
                          child: const Icon(Icons.qr_code_scanner_rounded, size: 20),
                        ),
                      ),
                      const SizedBox(width: 6),
                      ElevatedButton(
                        onPressed: () => _searchInvoice(_invoiceCtrl.text),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                        ),
                        child: const Text('CARI'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else if (_selectedTransaction != null) ...[
              // Transaction Details Card
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
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
                      'Pelanggan: ${_selectedTransaction!.customerName}',
                      style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                    ),
                    const Divider(height: 16),
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
              const SizedBox(height: 16),

              // Items to Return Selector
              const Text(
                'Pilih Barang yang Diretur & Kondisinya:',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textDark),
              ),
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
                  final canReturn = _selectedTransaction!.status != 'void' && _selectedTransaction!.status != 'voided' && maxQty > 0;
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
                                    ? (val) {
                                        setState(() {
                                          state['selected'] = val ?? false;
                                        });
                                      }
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
                                          ? 'Beli: ${item.qty} • Sisa bisa diretur: $maxQty ${item.unitName} @ ${CurrencyHelper.format(item.unitPrice)}'
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
                                const Text(
                                  'Habis Diretur',
                                  style: TextStyle(fontSize: 11, color: AppTheme.textMuted, fontStyle: FontStyle.italic),
                                ),
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
                                // Quantity adjustment
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

                                // Condition Selector (Baik vs Rusak)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                  decoration: BoxDecoration(
                                    color: condition == 'baik' ? Colors.green.shade50 : Colors.red.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: condition == 'baik' ? Colors.green : Colors.red,
                                      width: 0.8,
                                    ),
                                  ),
                                  child: DropdownButton<String>(
                                    value: condition,
                                    underline: const SizedBox(),
                                    isDense: true,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: condition == 'baik' ? Colors.green.shade800 : Colors.red.shade800,
                                    ),
                                    items: const [
                                      DropdownMenuItem(
                                        value: 'baik',
                                        child: Text('Kondisi Baik (Kembali Rak)'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'rusak',
                                        child: Text('Rusak / Afkir (Gudang Rusak)'),
                                      ),
                                    ],
                                    onChanged: (val) {
                                      if (val != null) {
                                        setState(() => state['condition'] = val);
                                      }
                                    },
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
              const SizedBox(height: 16),

              // Refund Method & Total
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Metode Pengembalian Dana (Refund):',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _buildRefundChip('tunai', 'Tunai (Kas Laci)', Icons.money_rounded),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildRefundChip('potong_piutang', 'Potong Kasbon', Icons.receipt_rounded),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildRefundChip('tukar_barang', 'Tukar Barang', Icons.swap_horiz_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _returnNoteCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Alasan Retur (Opsional)',
                        hintText: 'Misal: Salah beli ukuran, kemasan bocor...',
                        isDense: true,
                      ),
                    ),
                    const Divider(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('TOTAL PENGEMBALIAN DANA:',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        Text(
                          CurrencyHelper.format(_totalRefundAmount),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.accentRed,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Submit Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('PROSES RETUR SEKARANG', style: TextStyle(fontSize: 15)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accentRed,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: _totalRefundAmount > 0 ? _processReturn : null,
                ),
              ),
              const SizedBox(height: 24),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRefundChip(String method, String label, IconData icon) {
    final isSelected = _refundMethod == method;
    return InkWell(
      onTap: () => setState(() => _refundMethod = method),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryGreen.withOpacity(0.12) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? AppTheme.primaryGreen : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, size: 18, color: isSelected ? AppTheme.primaryGreen : AppTheme.textMuted),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? AppTheme.primaryGreen : AppTheme.textDark,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
            ),
          ],
        ),
      ),
    );
  }
}
