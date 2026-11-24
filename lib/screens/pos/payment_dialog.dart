import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/pos_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/product_provider.dart';
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
  final TextEditingController _customerNameCtrl = TextEditingController(text: 'Pelanggan Umum');
  final TextEditingController _customerPhoneCtrl = TextEditingController();
  final TextEditingController _noteCtrl = TextEditingController();

  String _paymentMethod = 'tunai';
  double _paidAmount = 0.0;

  @override
  void initState() {
    super.initState();
    final pos = Provider.of<PosProvider>(context, listen: false);
    _paidAmount = pos.grandTotal;
    _cashCtrl.text = _paidAmount.toInt().toString();
  }

  void _setQuickCash(double amount) {
    setState(() {
      _paidAmount = amount;
      _cashCtrl.text = amount.toInt().toString();
    });
  }

  @override
  Widget build(BuildContext context) {
    final pos = Provider.of<PosProvider>(context);
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final productProv = Provider.of<ProductProvider>(context, listen: false);

    final double change = (_paidAmount >= pos.grandTotal) ? (_paidAmount - pos.grandTotal) : 0.0;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Pembayaran',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(),

              // Total to Pay
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.primaryGreen.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.primaryGreen.withOpacity(0.2)),
                ),
                child: Column(
                  children: [
                    const Text('TOTAL TAGIHAN', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                    const SizedBox(height: 4),
                    Text(
                      CurrencyHelper.format(pos.grandTotal),
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryGreen,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Payment Method Selector
              const Text('Metode Pembayaran:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _buildMethodButton('tunai', 'Tunai', Icons.payments_rounded),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildMethodButton('transfer', 'QRIS / Transfer', Icons.qr_code_rounded),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildMethodButton('kasbon', 'Kasbon (Tempo)', Icons.hourglass_top_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Cash Payment Fields
              if (_paymentMethod == 'tunai') ...[
                const Text('Uang Diterima:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                TextField(
                  controller: _cashCtrl,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  decoration: const InputDecoration(
                    prefixText: 'Rp ',
                    prefixStyle: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  onChanged: (val) {
                    setState(() {
                      _paidAmount = double.tryParse(val.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0.0;
                    });
                  },
                ),
                const SizedBox(height: 8),

                // Quick Cash Buttons
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
                const SizedBox(height: 12),

                // Kembalian
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(10),
                  ),
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
                const SizedBox(height: 16),
              ],

              // Customer Info
              const Text('Informasi Pelanggan (Opsional / Kasbon):',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              TextField(
                controller: _customerNameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nama Pelanggan',
                  prefixIcon: Icon(Icons.person_rounded, size: 20),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _customerPhoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'No. WhatsApp / HP',
                  hintText: '08xxxxxxxxxx',
                  prefixIcon: Icon(Icons.phone_android_rounded, size: 20),
                ),
              ),
              const SizedBox(height: 16),

              // Checkout Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: (_paymentMethod == 'tunai' && _paidAmount < pos.grandTotal)
                      ? null
                      : () async {
                          pos.setCustomerInfo(_customerNameCtrl.text, _customerPhoneCtrl.text);
                          pos.setPaymentMethod(_paymentMethod);
                          pos.setAmountPaid(_paidAmount);

                          final cashier = auth.currentUser;
                          final transaction = await pos.checkout(
                            cashierId: cashier?.id ?? 1,
                            cashierName: cashier?.name ?? 'Kasir',
                            note: _noteCtrl.text,
                          );

                          // Reload products stock in background
                          productProv.loadProducts();

                          if (!mounted) return;
                          Navigator.pop(context); // Close PaymentDialog

                          // Open Receipt Dialog
                          showDialog(
                            context: context,
                            barrierDismissible: false,
                            builder: (_) => ReceiptDialog(transaction: transaction),
                          );
                        },
                  child: const Text('SELESAIKAN TRANSAKSI', style: TextStyle(fontSize: 16)),
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
        });
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryGreen.withOpacity(0.12) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? AppTheme.primaryGreen : Colors.black12,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, color: isSelected ? AppTheme.primaryGreen : AppTheme.textMuted, size: 22),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
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
