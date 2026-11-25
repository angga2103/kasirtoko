import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../providers/auth_provider.dart';
import '../../providers/cash_flow_provider.dart';
import '../../providers/debt_provider.dart';
import '../../providers/printer_provider.dart';
import '../../providers/product_provider.dart';
import '../../providers/pos_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/printer/printer_manager.dart';
import '../../utils/app_theme.dart';
import '../../utils/currency_format.dart';
import 'receipt_dialog.dart';

class PaymentDialog extends StatefulWidget {
  const PaymentDialog({super.key});

  @override
  State<PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<PaymentDialog> {
  final TextEditingController _cashCtrl = TextEditingController();
  late TextEditingController _customerNameCtrl;
  late TextEditingController _customerPhoneCtrl;
  final TextEditingController _noteCtrl = TextEditingController();

  String _paymentMethod = 'tunai';
  double _paidAmount = 0.0;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    final pos = Provider.of<PosProvider>(context, listen: false);
    _paidAmount = pos.grandTotal;
    _cashCtrl.text = _paidAmount.toInt().toString();
    _customerNameCtrl = TextEditingController(text: pos.customerName);
    _customerPhoneCtrl = TextEditingController(text: pos.customerPhone);
  }

  @override
  void dispose() {
    _cashCtrl.dispose();
    _customerNameCtrl.dispose();
    _customerPhoneCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  void _setQuickCash(double amount) {
    setState(() {
      _paidAmount = amount;
      _cashCtrl.text = amount.toInt().toString();
    });
  }

  Future<void> _submitPayment() async {
    if (_isSubmitting) return;
    final pos = Provider.of<PosProvider>(context, listen: false);
    if (pos.isEmpty || pos.isCheckingOut) return;

    if (_paymentMethod == 'tunai' && _paidAmount < pos.grandTotal) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nominal uang diterima kurang dari total tagihan!')),
      );
      return;
    }

    if (_paymentMethod == 'kasbon' && _customerNameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Isi nama pelanggan untuk transaksi Kasbon / Tempo!')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final productProv = Provider.of<ProductProvider>(context, listen: false);
    final cashFlow = Provider.of<CashFlowProvider>(context, listen: false);
    final debtProv = Provider.of<DebtProvider>(context, listen: false);
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final printerProv = Provider.of<PrinterProvider>(context, listen: false);

    pos.setCustomerInfo(_customerNameCtrl.text, _customerPhoneCtrl.text);
    pos.setPaymentMethod(_paymentMethod);
    pos.setAmountPaid(_paymentMethod == 'tunai' || _paymentMethod == 'kasbon' ? _paidAmount : pos.grandTotal);

    final cashier = auth.currentUser;
    final customInvoice = settings.generateTransactionNumber();

    final transaction = await pos.checkout(
      cashierId: cashier?.id ?? 1,
      cashierName: cashier?.name ?? 'Kasir',
      customInvoiceNumber: customInvoice,
      activeShiftId: cashFlow.currentShift?.id,
      note: _noteCtrl.text.trim(),
      storeName: settings.storeName,
      storeAddress: settings.storeAddress,
      storePhone: settings.storePhone,
      receiptConfig: settings.receiptConfig,
    );

    if (transaction == null) {
      if (mounted) setState(() => _isSubmitting = false);
      return;
    }

    await auth.logAction(
      'transaksi_selesai',
      'Transaksi ${transaction.invoiceNumber}: ${CurrencyHelper.format(transaction.grandTotal)} (${transaction.paymentMethod.toUpperCase()})',
    );

    // Sync background providers
    await productProv.loadProducts();
    await cashFlow.checkOpenShift();
    if (transaction.paymentMethod == 'kasbon') {
      await debtProv.loadDebts();
    }

    // Auto-print if configured
    if (settings.receiptConfig.autoPrint) {
      await PrinterManager.printTransactionReceipt(
        printer: printerProv.defaultPrinter,
        transaction: transaction,
        storeName: settings.storeName,
        storeAddress: settings.storeAddress,
        storePhone: settings.storePhone,
        receiptConfig: settings.receiptConfig,
        logoPath: settings.logoPath,
      );
    }

    if (!mounted) return;
    Navigator.pop(context); // Close PaymentDialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => ReceiptDialog(transaction: transaction),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pos = Provider.of<PosProvider>(context);
    final double change = (_paidAmount >= pos.grandTotal) ? (_paidAmount - pos.grandTotal) : 0.0;
    final bool canPay = !_isSubmitting &&
        !pos.isEmpty &&
        !(_paymentMethod == 'tunai' && _paidAmount < pos.grandTotal);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Konfirmasi Pembayaran', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: _isSubmitting ? null : () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(),

              // Summary Banner
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.primaryGreen.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.primaryGreen.withValues(alpha: 0.25)),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('${pos.itemCount} Jenis (${pos.totalUnitsCount.toInt()} Item)',
                            style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                        Text('Subtotal: ${CurrencyHelper.format(pos.subtotal)}',
                            style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                      ],
                    ),
                    if (pos.cartDiscount > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Diskon', style: TextStyle(fontSize: 12, color: Colors.pink)),
                            Text('-${CurrencyHelper.format(pos.cartDiscount)}',
                                style: const TextStyle(fontSize: 12, color: Colors.pink, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    if (pos.taxAmount > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Pajak (${pos.taxRate.toStringAsFixed(0)}%)',
                                style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                            Text(CurrencyHelper.format(pos.taxAmount),
                                style: const TextStyle(fontSize: 12)),
                          ],
                        ),
                      ),
                    const Divider(height: 14),
                    const Text('TOTAL TAGIHAN', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                    Text(
                      CurrencyHelper.format(pos.grandTotal),
                      style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: AppTheme.primaryGreen),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Payment Methods
              const Text('Metode Pembayaran:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: _buildMethodButton('tunai', 'Tunai', Icons.payments_rounded)),
                  const SizedBox(width: 6),
                  Expanded(child: _buildMethodButton('qris', 'QRIS', Icons.qr_code_2_rounded)),
                  const SizedBox(width: 6),
                  Expanded(child: _buildMethodButton('transfer', 'Transfer', Icons.account_balance_rounded)),
                  const SizedBox(width: 6),
                  Expanded(child: _buildMethodButton('kasbon', 'Kasbon', Icons.hourglass_top_rounded)),
                ],
              ),
              const SizedBox(height: 14),

              if (_paymentMethod == 'tunai') ...[
                const Text('Uang Diterima:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                TextField(
                  controller: _cashCtrl,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  decoration: const InputDecoration(prefixText: 'Rp '),
                  onChanged: (val) {
                    setState(() {
                      _paidAmount = double.tryParse(val.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0.0;
                    });
                  },
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _buildQuickCashChip('Uang Pas', pos.grandTotal),
                    _buildQuickCashChip('10 rb', 10000),
                    _buildQuickCashChip('20 rb', 20000),
                    _buildQuickCashChip('50 rb', 50000),
                    _buildQuickCashChip('100 rb', 100000),
                    _buildQuickCashChip('200 rb', 200000),
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(10)),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Kembalian:', style: TextStyle(fontWeight: FontWeight.bold)),
                      Text(
                        CurrencyHelper.format(change),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: _paidAmount >= pos.grandTotal ? AppTheme.primaryGreen : AppTheme.accentRed,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ] else if (_paymentMethod == 'qris') ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                        child: QrImageView(
                          data: 'KASIRTOKO-QRIS|${pos.grandTotal.toInt()}',
                          size: 64,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Pembayaran QRIS',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            Text(
                              'Pastikan dana ${CurrencyHelper.format(pos.grandTotal)} telah masuk sebelum menyelesaikan transaksi.',
                              style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ] else if (_paymentMethod == 'kasbon') ...[
                TextField(
                  controller: _cashCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Uang Muka / DP (Isi 0 jika full tempo)',
                    prefixText: 'Rp ',
                  ),
                  onChanged: (val) {
                    setState(() {
                      _paidAmount = double.tryParse(val.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0.0;
                    });
                  },
                ),
                const SizedBox(height: 12),
              ],

              TextField(
                controller: _customerNameCtrl,
                decoration: InputDecoration(
                  labelText: _paymentMethod == 'kasbon' ? 'Nama Pelanggan *' : 'Nama Pelanggan (Opsional)',
                  prefixIcon: const Icon(Icons.person_rounded, size: 20),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _customerPhoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'No. WhatsApp Pelanggan',
                  hintText: '08xxxxxxxxxx',
                  prefixIcon: Icon(Icons.phone_android_rounded, size: 20),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _noteCtrl,
                decoration: const InputDecoration(labelText: 'Catatan Nota (Opsional)'),
              ),
              const SizedBox(height: 16),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: canPay ? _submitPayment : null,
                  child: Text(
                    _isSubmitting ? 'MEMPROSES TRANSAKSI...' : 'SELESAIKAN TRANSAKSI',
                    style: const TextStyle(fontSize: 15),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMethodButton(String method, String label, IconData icon) {
    final isSelected = _paymentMethod == method;
    return InkWell(
      onTap: () {
        setState(() {
          _paymentMethod = method;
          final pos = Provider.of<PosProvider>(context, listen: false);
          if (method == 'kasbon') {
            _paidAmount = 0;
            _cashCtrl.text = '0';
          } else {
            _paidAmount = pos.grandTotal;
            _cashCtrl.text = pos.grandTotal.toInt().toString();
          }
        });
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryGreen.withValues(alpha: 0.12) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? AppTheme.primaryGreen : Colors.black12,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, color: isSelected ? AppTheme.primaryGreen : AppTheme.textMuted, size: 20),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10.5,
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

  Widget _buildQuickCashChip(String label, double amount) {
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      onPressed: () => _setQuickCash(amount),
      backgroundColor: Colors.grey.shade100,
    );
  }
}
