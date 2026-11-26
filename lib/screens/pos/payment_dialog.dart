import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../database/db_helper.dart';
import '../../models/customer.dart';
import '../../providers/auth_provider.dart';
import '../../providers/cash_flow_provider.dart';
import '../../providers/customer_provider.dart';
import '../../providers/debt_provider.dart';
import '../../providers/printer_provider.dart';
import '../../providers/product_provider.dart';
import '../../providers/pos_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/printer/printer_manager.dart';
import '../../utils/app_theme.dart';
import '../../utils/currency_format.dart';
import '../../utils/quick_cash_helper.dart';
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
  int? _selectedCustomerId;
  double _customerCreditBalance = 0.0;
  bool _useCreditBalance = false;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    final pos = Provider.of<PosProvider>(context, listen: false);
    _paidAmount = pos.grandTotal;
    _cashCtrl.text = _paidAmount.toInt().toString();
    _selectedCustomerId = pos.customerId;
    _customerNameCtrl = TextEditingController(text: pos.customerName);
    _customerPhoneCtrl = TextEditingController(text: pos.customerPhone);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (_selectedCustomerId != null) {
        await _loadCustomerCredit(_selectedCustomerId);
      }
      if (!mounted) return;
      await Provider.of<CustomerProvider>(context, listen: false).loadCustomers();
    });
  }

  Future<void> _loadCustomerCredit(int? customerId) async {
    if (customerId == null) {
      if (!mounted) return;
      final pos = Provider.of<PosProvider>(context, listen: false);
      pos.setCreditUsed(0.0);
      setState(() {
        _customerCreditBalance = 0.0;
        _useCreditBalance = false;
        if (_paymentMethod != 'kasbon') {
          _paidAmount = pos.grandTotal;
          _cashCtrl.text = pos.grandTotal.toInt().toString();
        }
      });
      return;
    }
    final bal = await DatabaseHelper.instance.getCustomerCreditBalance(customerId);
    if (!mounted) return;
    final pos = Provider.of<PosProvider>(context, listen: false);
    final shouldUse = _useCreditBalance && bal > 0;
    final applied = shouldUse ? bal.clamp(0.0, pos.grandTotal) : 0.0;
    pos.setCreditUsed(applied);
    setState(() {
      _customerCreditBalance = bal;
      if (bal <= 0) _useCreditBalance = false;
      final netDue = (pos.grandTotal - applied).clamp(0.0, pos.grandTotal);
      if (_paymentMethod != 'kasbon') {
        _paidAmount = netDue;
        _cashCtrl.text = netDue.toInt().toString();
      }
    });
  }

  void _toggleUseCredit(bool enable) {
    final pos = Provider.of<PosProvider>(context, listen: false);
    final applied = (enable && _customerCreditBalance > 0)
        ? _customerCreditBalance.clamp(0.0, pos.grandTotal)
        : 0.0;
    pos.setCreditUsed(applied);
    final netDue = (pos.grandTotal - applied).clamp(0.0, pos.grandTotal);
    setState(() {
      _useCreditBalance = enable && _customerCreditBalance > 0;
      if (_paymentMethod != 'kasbon') {
        _paidAmount = netDue;
        _cashCtrl.text = netDue.toInt().toString();
      }
    });
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

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final productProv = Provider.of<ProductProvider>(context, listen: false);
    final cashFlow = Provider.of<CashFlowProvider>(context, listen: false);
    final debtProv = Provider.of<DebtProvider>(context, listen: false);
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final printerProv = Provider.of<PrinterProvider>(context, listen: false);

    if (!cashFlow.isShiftOpen) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Shift kasir belum dibuka! Buka shift terlebih dahulu sebelum transaksi.'),
          backgroundColor: AppTheme.accentRed,
        ),
      );
      return;
    }

    final double appliedCredit =
        (_useCreditBalance && _selectedCustomerId != null && _customerCreditBalance > 0)
            ? _customerCreditBalance.clamp(0.0, pos.grandTotal)
            : 0.0;
    final double netDue = (pos.grandTotal - appliedCredit).clamp(0.0, pos.grandTotal);

    if (_paymentMethod == 'tunai' && netDue > 0.01 && _paidAmount < netDue) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nominal uang diterima kurang dari sisa tagihan!')),
      );
      return;
    }

    final cleanCustName = _customerNameCtrl.text.trim();
    if (_paymentMethod == 'kasbon' &&
        (_selectedCustomerId == null ||
            cleanCustName.isEmpty ||
            cleanCustName.toLowerCase() == 'pelanggan umum')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Kasbon hanya untuk pelanggan terdaftar. Pilih atau daftarkan pelanggan terlebih dahulu.'),
          backgroundColor: AppTheme.accentRed,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    pos.setCustomerInfo(
      (_paymentMethod == 'kasbon' || appliedCredit > 0)
          ? cleanCustName
          : (cleanCustName.isEmpty ? 'Pelanggan Umum' : cleanCustName),
      _customerPhoneCtrl.text,
      customerId: _selectedCustomerId,
    );
    pos.setCreditUsed(appliedCredit);
    pos.setPaymentMethod(netDue <= 0.01 && appliedCredit > 0 ? 'saldo_kredit' : _paymentMethod);
    pos.setAmountPaid(_paymentMethod == 'tunai' || _paymentMethod == 'kasbon' ? _paidAmount : netDue);

    final cashier = auth.currentUser;
    final customInvoice = settings.generateTransactionNumber();

    try {
      final transaction = await pos.checkout(
        cashierId: cashier?.id ?? 1,
        cashierName: cashier?.name ?? 'Kasir',
        customInvoiceNumber: customInvoice,
        activeShiftId: cashFlow.currentShift?.id,
        terminalId: cashFlow.currentShift?.terminalId ?? 'ADMIN',
        cashRegisterId: cashFlow.currentShift?.cashRegisterId,
        idempotencyKey: 'ADMIN-$customInvoice',
        note: _noteCtrl.text.trim(),
        storeName: settings.storeName,
        storeAddress: settings.storeAddress,
        storePhone: settings.storePhone,
        receiptConfig: settings.receiptConfig,
      );

      if (transaction == null) {
        if (mounted) {
          setState(() => _isSubmitting = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Transaksi tidak dapat diproses. Periksa keranjang dan status shift.'),
              backgroundColor: AppTheme.accentRed,
            ),
          );
        }
        return;
      }

      await auth.logAction(
        'transaksi_selesai',
        'Transaksi ${transaction.invoiceNumber}: ${CurrencyHelper.format(transaction.grandTotal)} (${transaction.paymentMethod.toUpperCase()})',
        module: 'transaksi',
        objectId: transaction.invoiceNumber,
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
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceFirst('Bad state: ', '').replaceFirst('StateError: ', '')),
            backgroundColor: AppTheme.accentRed,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pos = Provider.of<PosProvider>(context);
    final custProv = Provider.of<CustomerProvider>(context);
    final cashFlow = Provider.of<CashFlowProvider>(context);
    final registeredCustomers = custProv.customers
        .where((c) => c.id != null && c.name.trim().toLowerCase() != 'pelanggan umum')
        .toList();
    final double appliedCredit =
        (_useCreditBalance && _selectedCustomerId != null && _customerCreditBalance > 0)
            ? _customerCreditBalance.clamp(0.0, pos.grandTotal)
            : 0.0;
    final double netDue = (pos.grandTotal - appliedCredit).clamp(0.0, pos.grandTotal);
    final double change = (_paidAmount >= netDue) ? (_paidAmount - netDue) : 0.0;
    final bool canPay = !_isSubmitting &&
        !pos.isEmpty &&
        cashFlow.isShiftOpen &&
        !(netDue > 0.01 && _paymentMethod == 'tunai' && _paidAmount < netDue);

    final quickNominals = QuickCashHelper.suggestNominals(netDue);
    final hasExactInNominals = quickNominals.any((n) => (n - netDue).abs() < 1);

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
                  const Expanded(
                    child: Text(
                      'Konfirmasi Pembayaran',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
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
                        Flexible(
                          child: Text(
                            '${pos.itemCount} Jenis (${pos.totalUnitsCount.toInt()} Item)',
                            style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'Subtotal: ${CurrencyHelper.format(pos.subtotal)}',
                            style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.end,
                          ),
                        ),
                      ],
                    ),
                    if (pos.cartDiscount > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Flexible(
                              child: Text('Diskon', style: TextStyle(fontSize: 12, color: Colors.pink)),
                            ),
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
                            Flexible(
                              child: Text('Pajak (${pos.taxRate.toStringAsFixed(0)}%)',
                                  style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                            ),
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
                    if (appliedCredit > 0) ...[
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Expanded(
                            child: Text(
                              'Potong Saldo Kredit Retur:',
                              style: TextStyle(fontSize: 12, color: AppTheme.accentBlue, fontWeight: FontWeight.w600),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '-${CurrencyHelper.format(appliedCredit)}',
                            style: const TextStyle(fontSize: 12, color: AppTheme.accentBlue, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Expanded(
                            child: Text(
                              'Sisa Harus Dibayar:',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            CurrencyHelper.format(netDue),
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.primaryGreen),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (_customerCreditBalance > 0 && _selectedCustomerId != null) ...[
                const SizedBox(height: 10),
                Material(
                  color: AppTheme.accentBlue.withValues(alpha: 0.08),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(color: AppTheme.accentBlue.withValues(alpha: 0.35)),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: CheckboxListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                    value: _useCreditBalance,
                    onChanged: (v) => _toggleUseCredit(v ?? false),
                    title: const Text('Gunakan Saldo Kredit Retur Pelanggan',
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                    subtitle: Text(
                      'Saldo tersedia: ${CurrencyHelper.format(_customerCreditBalance)}',
                      style: const TextStyle(fontSize: 11, color: AppTheme.accentBlue),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 14),

              if (netDue <= 0.01 && appliedCredit > 0) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryGreenSoft,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.primaryGreen.withValues(alpha: 0.4)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.account_balance_wallet_rounded, color: AppTheme.primaryGreen),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '100% dibayar menggunakan Saldo Kredit Retur pelanggan. Tidak ada kas laci masuk.',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.primaryGreen),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ] else ...[
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
                      if (!hasExactInNominals && netDue > 0)
                        _buildQuickCashChip('Uang Pas', netDue),
                      ...quickNominals.map((amt) {
                        final isExact = (amt - netDue).abs() < 1;
                        final formatted = CurrencyHelper.format(amt);
                        return _buildQuickCashChip(isExact ? '$formatted (Pas)' : formatted, amt);
                      }),
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
                            color: _paidAmount >= netDue ? AppTheme.primaryGreen : AppTheme.accentRed,
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
                            data: 'KASIRTOKO-QRIS|${netDue.toInt()}',
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
                                'Pastikan dana ${CurrencyHelper.format(netDue)} telah masuk sebelum menyelesaikan transaksi.',
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
              ],

              if (!cashFlow.isShiftOpen)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.accentRedSoft,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.accentRed.withValues(alpha: 0.4)),
                  ),
                  child: const Text(
                    'Shift kasir sedang tutup! Buka shift terlebih dahulu sebelum menyelesaikan transaksi.',
                    style: TextStyle(fontSize: 12, color: AppTheme.accentRed, fontWeight: FontWeight.w600),
                  ),
                ),

              if (_paymentMethod == 'kasbon') ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.accentOrange.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.accentOrange.withValues(alpha: 0.35)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.verified_user_rounded, size: 16, color: AppTheme.accentOrange),
                          const SizedBox(width: 6),
                          const Expanded(
                            child: Text(
                              'Pelanggan Terdaftar (Wajib untuk Kasbon) *',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.accentOrange),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () => _quickAddRegisteredCustomer(custProv),
                            icon: const Icon(Icons.person_add_alt_1_rounded, size: 15),
                            label: const Text('+ Daftar Baru', style: TextStyle(fontSize: 11)),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (registeredCustomers.isEmpty)
                        const Text(
                          'Belum ada pelanggan terdaftar. Tekan "+ Daftar Baru" di atas untuk mendaftarkan pelanggan.',
                          style: TextStyle(fontSize: 11.5, color: AppTheme.accentRed),
                        )
                      else
                        DropdownButtonFormField<int?>(
                          value: registeredCustomers.any((c) => c.id == _selectedCustomerId)
                              ? _selectedCustomerId
                              : null,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Pilih Pelanggan Terdaftar *',
                            prefixIcon: Icon(Icons.person_pin_rounded, size: 20),
                            filled: true,
                            fillColor: Colors.white,
                          ),
                          hint: const Text('Pilih pelanggan (Pelanggan Umum tidak diizinkan)'),
                          items: registeredCustomers
                              .map((c) => DropdownMenuItem<int?>(
                                    value: c.id,
                                    child: Text(
                                      c.phone.isNotEmpty ? '${c.name} (${c.phone})' : c.name,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ))
                              .toList(),
                          onChanged: (custId) {
                            final picked = registeredCustomers.cast<CustomerModel?>().firstWhere(
                                  (c) => c?.id == custId,
                                  orElse: () => null,
                                );
                            setState(() {
                              _selectedCustomerId = custId;
                              _customerNameCtrl.text = picked?.name ?? '';
                              _customerPhoneCtrl.text = picked?.phone ?? '';
                            });
                            _loadCustomerCredit(custId);
                          },
                        ),
                    ],
                  ),
                ),
              ] else ...[
                if (registeredCustomers.isNotEmpty) ...[
                  DropdownButtonFormField<int?>(
                    value: registeredCustomers.any((c) => c.id == _selectedCustomerId) ? _selectedCustomerId : null,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Pelanggan Terdaftar (Opsional)',
                      prefixIcon: Icon(Icons.people_outline_rounded, size: 20),
                    ),
                    items: [
                      const DropdownMenuItem<int?>(value: null, child: Text('Pelanggan Umum / Input Manual')),
                      ...registeredCustomers.map((c) => DropdownMenuItem<int?>(
                            value: c.id,
                            child: Text(c.phone.isNotEmpty ? '${c.name} (${c.phone})' : c.name, overflow: TextOverflow.ellipsis),
                          )),
                    ],
                    onChanged: (custId) {
                      setState(() {
                        _selectedCustomerId = custId;
                        if (custId == null) {
                          _customerNameCtrl.text = 'Pelanggan Umum';
                          _customerPhoneCtrl.clear();
                        } else {
                          final picked = registeredCustomers.firstWhere((c) => c.id == custId);
                          _customerNameCtrl.text = picked.name;
                          _customerPhoneCtrl.text = picked.phone;
                        }
                      });
                      _loadCustomerCredit(custId);
                    },
                  ),
                  const SizedBox(height: 8),
                ],
                TextField(
                  controller: _customerNameCtrl,
                  onChanged: (_) => _selectedCustomerId = null,
                  decoration: const InputDecoration(
                    labelText: 'Nama Pelanggan (Opsional)',
                    prefixIcon: Icon(Icons.person_rounded, size: 20),
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
              ],
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
          final net = pos.netPayable;
          if (method == 'kasbon') {
            _paidAmount = 0;
            _cashCtrl.text = '0';
          } else {
            _paidAmount = net;
            _cashCtrl.text = net.toInt().toString();
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

  Future<void> _quickAddRegisteredCustomer(CustomerProvider custProv) async {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final addressCtrl = TextEditingController();
    String? errText;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDState) => AlertDialog(
          title: const Text('Daftarkan Pelanggan Baru'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Nama Lengkap Pelanggan *'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'No. HP / WhatsApp *'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: addressCtrl,
                decoration: const InputDecoration(labelText: 'Alamat (Opsional)'),
              ),
              if (errText != null) ...[
                const SizedBox(height: 8),
                Text(errText!, style: const TextStyle(color: AppTheme.accentRed, fontSize: 12)),
              ],
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
            ElevatedButton(
              onPressed: () async {
                final cleanName = nameCtrl.text.trim();
                final cleanPhone = phoneCtrl.text.trim();
                if (cleanName.isEmpty || cleanName.toLowerCase() == 'pelanggan umum') {
                  setDState(() => errText = 'Masukkan nama pelanggan yang valid (bukan Pelanggan Umum).');
                  return;
                }
                if (cleanPhone.isEmpty) {
                  setDState(() => errText = 'Nomor HP/WA wajib diisi untuk pencatatan kasbon.');
                  return;
                }
                await custProv.saveCustomer(
                  CustomerModel(name: cleanName, phone: cleanPhone, address: addressCtrl.text.trim()),
                );
                final matched = custProv.customers.lastWhere(
                  (c) => c.name.trim().toLowerCase() == cleanName.toLowerCase(),
                  orElse: () => CustomerModel(name: cleanName, phone: cleanPhone),
                );
                if (mounted) {
                  setState(() {
                    _selectedCustomerId = matched.id;
                    _customerNameCtrl.text = matched.name;
                    _customerPhoneCtrl.text = matched.phone;
                  });
                  await _loadCustomerCredit(matched.id);
                }
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Simpan & Pilih'),
            ),
          ],
        ),
      ),
    ).then((_) {
      nameCtrl.dispose();
      phoneCtrl.dispose();
      addressCtrl.dispose();
    });
  }
}
