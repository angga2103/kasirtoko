import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/product.dart';
import '../../models/purchase.dart';
import '../../models/user.dart';
import '../../providers/auth_provider.dart';
import '../../providers/cash_flow_provider.dart';
import '../../providers/product_provider.dart';
import '../../providers/purchase_provider.dart';
import '../../utils/app_theme.dart';
import '../../utils/currency_format.dart';
import '../../utils/date_format.dart';
import '../../widgets/quantity_stepper.dart';

class PurchaseListScreen extends StatefulWidget {
  const PurchaseListScreen({super.key});

  @override
  State<PurchaseListScreen> createState() => _PurchaseListScreenState();
}

class _PurchaseListScreenState extends State<PurchaseListScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<PurchaseProvider>(context, listen: false).loadPurchases();
      Provider.of<CashFlowProvider>(context, listen: false).checkOpenShift();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _openCreatePurchase() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PurchaseFormScreen()),
    ).then((_) {
      if (mounted) {
        Provider.of<PurchaseProvider>(context, listen: false).loadPurchases();
        Provider.of<CashFlowProvider>(context, listen: false).checkOpenShift();
      }
    });
  }

  Future<void> _confirmVoidPurchase(PurchaseModel p) async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final cashFlow = Provider.of<CashFlowProvider>(context, listen: false);
    final prov = Provider.of<PurchaseProvider>(context, listen: false);
    final prodProv = Provider.of<ProductProvider>(context, listen: false);

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Batalkan (Void) Pembelian?'),
        content: Text(
          'Pembelian #${p.purchaseNumber} (${p.supplierName}) senilai ${CurrencyHelper.format(p.totalAmount)} akan dibatalkan.\n\n'
          '• Stok produk yang bertambah akan dikurangi kembali.\n'
          '• Kas yang keluar dari laci akan dikembalikan.\n'
          '• Hutang supplier terkait (jika ada) akan dibatalkan.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Tidak')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accentRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ya, Batalkan Pembelian'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    try {
      await prov.voidPurchase(
        p.id!,
        shiftId: cashFlow.currentShift?.id,
        cancelledBy: auth.currentUser?.name ?? 'Admin',
      );
      await prodProv.loadProducts();
      await cashFlow.checkOpenShift();
      await auth.logAction(
        'pembelian_void',
        'Membatalkan pembelian #${p.purchaseNumber} (${p.supplierName}) senilai ${CurrencyHelper.format(p.totalAmount)}',
        module: 'pembelian',
        objectId: p.purchaseNumber,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pembelian berhasil dibatalkan dan stok/kas telah dikembalikan.'), backgroundColor: AppTheme.success),
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

  void _showPurchaseDetail(PurchaseModel p, bool canVoid) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Expanded(child: Text('Detail #${p.purchaseNumber}', style: const TextStyle(fontSize: 16))),
            if (p.isVoided)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: AppTheme.accentRedSoft, borderRadius: BorderRadius.circular(8)),
                child: const Text('VOID', style: TextStyle(fontSize: 10, color: AppTheme.accentRed, fontWeight: FontWeight.bold)),
              ),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Supplier: ${p.supplierName}${p.supplierPhone.isNotEmpty ? " (${p.supplierPhone})" : ""}'),
                Text('Tanggal: ${DateHelper.formatFull(p.date)}', style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                Text('Metode: ${_paymentLabel(p.paymentMethod)}', style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                if (p.cashPaid > 0) Text('Tunai Laci: ${CurrencyHelper.format(p.cashPaid)}', style: const TextStyle(fontSize: 12)),
                if (p.transferPaid > 0)
                  Text('Transfer (${p.transferAccount.isNotEmpty ? p.transferAccount : "Bank"}): ${CurrencyHelper.format(p.transferPaid)}', style: const TextStyle(fontSize: 12)),
                if (p.creditAmount > 0)
                  Text('Hutang Tempo: ${CurrencyHelper.format(p.creditAmount)}${p.dueDate != null ? " (JT: ${DateHelper.formatShort(p.dueDate!)})" : ""}', style: const TextStyle(fontSize: 12, color: AppTheme.accentRed)),
                if (p.note.isNotEmpty) Text('Catatan: ${p.note}', style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
                const Divider(height: 16),
                const Text('Item Pembelian:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 6),
                ...p.items.map((item) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${item.productName}\n${item.qty == item.qty.truncateToDouble() ? item.qty.toInt() : item.qty} ${item.unitName} × ${CurrencyHelper.format(item.costPrice)}',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                          Text(CurrencyHelper.format(item.subtotal), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        ],
                      ),
                    )),
                const Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('TOTAL', style: TextStyle(fontWeight: FontWeight.bold)),
                    Text(CurrencyHelper.format(p.totalAmount), style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryGreen)),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          if (!p.isVoided && canVoid)
            TextButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                _confirmVoidPurchase(p);
              },
              icon: const Icon(Icons.cancel_outlined, color: AppTheme.accentRed, size: 18),
              label: const Text('Void Pembelian', style: TextStyle(color: AppTheme.accentRed)),
            ),
          ElevatedButton(onPressed: () => Navigator.pop(ctx), child: const Text('Tutup')),
        ],
      ),
    );
  }

  Future<void> _showPaySupplierDebtDialog(SupplierDebtModel debt) async {
    final prov = Provider.of<PurchaseProvider>(context, listen: false);
    final cashFlow = Provider.of<CashFlowProvider>(context, listen: false);
    final auth = Provider.of<AuthProvider>(context, listen: false);

    final amountCtrl = TextEditingController(text: debt.remainingDebt.toInt().toString());
    final accountCtrl = TextEditingController(text: 'Transfer BCA');
    final refCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    String source = 'kas_laci';
    bool saving = false;
    String? errMsg;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDState) => AlertDialog(
          title: Text('Bayar Utang: ${debt.supplierName}', style: const TextStyle(fontSize: 16)),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('No. PO: ${debt.purchaseNumber}', style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                  Text(
                    'Sisa Utang: ${CurrencyHelper.format(debt.remainingDebt)}',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.accentRed),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: source,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Sumber Dana Pembayaran'),
                    items: const [
                      DropdownMenuItem(value: 'kas_laci', child: Text('Kas Laci Kasir (Tunai)', maxLines: 1, overflow: TextOverflow.ellipsis)),
                      DropdownMenuItem(value: 'transfer', child: Text('Transfer Bank / Rekening', maxLines: 1, overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (v) => setDState(() => source = v ?? 'kas_laci'),
                  ),
                  if (source == 'kas_laci') ...[
                    const SizedBox(height: 6),
                    Text(
                      cashFlow.isShiftOpen
                          ? 'Saldo Laci Aktif: ${CurrencyHelper.format(cashFlow.currentShift?.expectedCash ?? 0)}'
                          : 'Perhatian: Shift kasir belum dibuka.',
                      style: TextStyle(
                        fontSize: 11,
                        color: cashFlow.isShiftOpen ? AppTheme.primaryGreen : AppTheme.accentRed,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  if (source == 'transfer') ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: accountCtrl,
                      decoration: const InputDecoration(labelText: 'Nama Bank / Rekening Pengirim *'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: refCtrl,
                      decoration: const InputDecoration(labelText: 'No. Referensi / Bukti Transfer'),
                    ),
                  ],
                  const SizedBox(height: 10),
                  TextField(
                    controller: amountCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Nominal Bayar (Rp) *', prefixText: 'Rp '),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: noteCtrl,
                    decoration: const InputDecoration(labelText: 'Catatan (Opsional)'),
                  ),
                  if (errMsg != null) ...[
                    const SizedBox(height: 8),
                    Text(errMsg!, style: const TextStyle(color: AppTheme.accentRed, fontSize: 12, fontWeight: FontWeight.w600)),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: saving ? null : () => Navigator.pop(ctx), child: const Text('Batal')),
            ElevatedButton(
              onPressed: saving
                  ? null
                  : () async {
                      final amount = double.tryParse(amountCtrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0.0;
                      if (amount <= 0) {
                        setDState(() => errMsg = 'Nominal pembayaran harus lebih dari Rp 0.');
                        return;
                      }
                      if (amount > debt.remainingDebt + 0.01) {
                        setDState(() => errMsg = 'Nominal melebihi sisa utang (${CurrencyHelper.format(debt.remainingDebt)}).');
                        return;
                      }
                      if (source == 'kas_laci') {
                        if (!cashFlow.isShiftOpen) {
                          setDState(() => errMsg = 'Shift kasir belum dibuka untuk mengambil uang dari Kas Laci.');
                          return;
                        }
                        final avail = cashFlow.currentShift?.expectedCash ?? 0.0;
                        if (amount > avail + 0.01) {
                          setDState(() => errMsg = 'Saldo Kas Laci (${CurrencyHelper.format(avail)}) tidak mencukupi.');
                          return;
                        }
                      } else if (accountCtrl.text.trim().isEmpty) {
                        setDState(() => errMsg = 'Isi nama bank / rekening untuk transfer.');
                        return;
                      }
                      setDState(() {
                        saving = true;
                        errMsg = null;
                      });
                      try {
                        await prov.paySupplierDebt(
                          supplierDebtId: debt.id!,
                          amount: amount,
                          paymentSource: source,
                          accountName: source == 'kas_laci' ? 'Laci Kasir' : accountCtrl.text.trim(),
                          referenceNumber: refCtrl.text.trim(),
                          shiftId: cashFlow.currentShift?.id,
                          paidBy: auth.currentUser?.name ?? 'Admin',
                          note: noteCtrl.text.trim(),
                        );
                        await cashFlow.checkOpenShift();
                        await auth.logAction(
                          'bayar_utang_supplier',
                          'Bayar utang ${debt.supplierName} (#${debt.purchaseNumber}): ${CurrencyHelper.format(amount)} via ${source == "kas_laci" ? "Kas Laci" : accountCtrl.text.trim()}',
                          module: 'pembelian',
                          objectId: debt.purchaseNumber,
                        );
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) {
                          ScaffoldMessenger.of(this.context).showSnackBar(
                            SnackBar(
                              content: Text('Pembayaran utang supplier ${CurrencyHelper.format(amount)} tercatat.'),
                              backgroundColor: AppTheme.success,
                            ),
                          );
                        }
                      } catch (e) {
                        setDState(() {
                          saving = false;
                          errMsg = e.toString().replaceFirst('Bad state: ', '').replaceFirst('ArgumentError: ', '');
                        });
                      }
                    },
              child: Text(saving ? 'Menyimpan...' : 'Bayar Sekarang'),
            ),
          ],
        ),
      ),
    ).then((_) {
      amountCtrl.dispose();
      accountCtrl.dispose();
      refCtrl.dispose();
      noteCtrl.dispose();
    });
  }

  Future<void> _showSupplierDebtHistory(SupplierDebtModel debt) async {
    final payments = await Provider.of<PurchaseProvider>(context, listen: false).getSupplierDebtPayments(debt.id!);
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Riwayat Bayar • ${debt.purchaseNumber}', style: const TextStyle(fontSize: 16)),
        content: SizedBox(
          width: 400,
          child: payments.isEmpty
              ? const Text('Belum ada riwayat cicilan / pembayaran.')
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: payments.length,
                  separatorBuilder: (_, __) => const Divider(height: 10),
                  itemBuilder: (_, i) {
                    final pay = payments[i];
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(CurrencyHelper.format(pay.amount), style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryGreen)),
                      subtitle: Text(
                        '${DateHelper.formatFull(pay.date)} • ${pay.paymentSource == "kas_laci" ? "Kas Laci" : "Transfer (${pay.accountName})"}\nOleh: ${pay.paidBy}${pay.note.isNotEmpty ? " • ${pay.note}" : ""}',
                        style: const TextStyle(fontSize: 11),
                      ),
                    );
                  },
                ),
        ),
        actions: [ElevatedButton(onPressed: () => Navigator.pop(ctx), child: const Text('Tutup'))],
      ),
    );
  }

  String _paymentLabel(String m) {
    switch (m) {
      case 'kas_laci':
        return 'Kas Laci (Tunai)';
      case 'transfer':
        return 'Transfer Bank';
      case 'hutang':
        return 'Hutang Tempo';
      case 'campuran':
        return 'Campuran';
      default:
        return m.toUpperCase();
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    if (!auth.hasPermission(AppPermissions.managePurchases)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Pembelian Stok Masuk')),
        body: const Center(child: Text('Anda tidak memiliki izin mengelola pembelian supplier.')),
      );
    }

    final prov = Provider.of<PurchaseProvider>(context);
    final canVoid = auth.currentUser?.isOwnerOrAdmin == true;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pembelian & Utang Supplier'),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: AppTheme.accentOrange,
          tabs: [
            Tab(text: 'Pembelian (${prov.purchases.length})'),
            Tab(text: 'Utang Supplier (${prov.activeSupplierDebts.length})'),
          ],
        ),
      ),
      body: prov.isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                prov.purchases.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.inventory_rounded, size: 54, color: AppTheme.textMuted),
                            const SizedBox(height: 12),
                            const Text('Belum ada riwayat pembelian stok.'),
                            const SizedBox(height: 12),
                            ElevatedButton.icon(
                              onPressed: _openCreatePurchase,
                              icon: const Icon(Icons.add),
                              label: const Text('Catat Pembelian Stok'),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(14),
                        itemCount: prov.purchases.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, index) {
                          final p = prov.purchases[index];
                          return Card(
                            child: ListTile(
                              onTap: () => _showPurchaseDetail(p, canVoid),
                              leading: CircleAvatar(
                                backgroundColor: p.isVoided ? AppTheme.accentRedSoft : AppTheme.primaryGreenSoft,
                                child: Icon(
                                  p.isVoided ? Icons.cancel_rounded : Icons.local_mall_rounded,
                                  color: p.isVoided ? AppTheme.accentRed : AppTheme.primaryGreen,
                                ),
                              ),
                              title: Text(
                                '${p.purchaseNumber} • ${p.supplierName}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13.5,
                                  decoration: p.isVoided ? TextDecoration.lineThrough : null,
                                ),
                              ),
                              subtitle: Text(
                                '${DateHelper.formatFull(p.date)} • ${p.items.length} Produk • ${_paymentLabel(p.paymentMethod)}${p.isVoided ? " [DIBATALKAN]" : ""}',
                                style: const TextStyle(fontSize: 11.5),
                              ),
                              trailing: Text(
                                CurrencyHelper.format(p.totalAmount),
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: p.isVoided ? AppTheme.textMuted : AppTheme.primaryGreen,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                Column(
                  children: [
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.all(14),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppTheme.accentRed.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.accentRed.withValues(alpha: 0.25)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Total Sisa Utang Supplier Aktif', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                              Text('Kewajiban bayar jatuh tempo & berjalan', style: TextStyle(fontSize: 10.5, color: AppTheme.textMuted)),
                            ],
                          ),
                          Text(
                            CurrencyHelper.format(prov.totalActiveSupplierDebt),
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.accentRed),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: prov.supplierDebts.isEmpty
                          ? const Center(child: Text('Belum ada catatan utang supplier.'))
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(14, 0, 14, 80),
                              itemCount: prov.supplierDebts.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 8),
                              itemBuilder: (_, idx) {
                                final d = prov.supplierDebts[idx];
                                return Card(
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Expanded(
                                              child: Text('${d.supplierName} • #${d.purchaseNumber}',
                                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                            ),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: d.isCancelled
                                                    ? Colors.grey.shade200
                                                    : (d.isPaidOff
                                                        ? Colors.green.shade100
                                                        : (d.isOverdue ? AppTheme.accentRedSoft : Colors.orange.shade100)),
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: Text(
                                                d.isCancelled
                                                    ? 'DIBATALKAN'
                                                    : (d.isPaidOff
                                                        ? 'LUNAS'
                                                        : (d.isOverdue ? 'JATUH TEMPO' : d.status.toUpperCase())),
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  color: d.isPaidOff ? Colors.green.shade800 : AppTheme.textDark,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Tgl Beli: ${DateHelper.formatShort(d.purchaseDate)}${d.dueDate != null ? " • Tempo: ${DateHelper.formatShort(d.dueDate!)}" : ""}',
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            color: d.isOverdue ? AppTheme.accentRed : AppTheme.textMuted,
                                          ),
                                        ),
                                        const Divider(height: 14),
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'Total: ${CurrencyHelper.format(d.totalDebt)} • Terbayar: ${CurrencyHelper.format(d.paidDebt)}',
                                                  style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                                                ),
                                                Text(
                                                  'Sisa: ${CurrencyHelper.format(d.remainingDebt)}',
                                                  style: TextStyle(
                                                    fontSize: 15,
                                                    fontWeight: FontWeight.bold,
                                                    color: d.isPaidOff ? AppTheme.primaryGreen : AppTheme.accentRed,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            Wrap(
                                              spacing: 6,
                                              children: [
                                                OutlinedButton(
                                                  onPressed: () => _showSupplierDebtHistory(d),
                                                  child: const Text('Riwayat', style: TextStyle(fontSize: 12)),
                                                ),
                                                if (!d.isPaidOff && !d.isCancelled)
                                                  ElevatedButton(
                                                    onPressed: () => _showPaySupplierDebtDialog(d),
                                                    child: const Text('Bayar', style: TextStyle(fontSize: 12)),
                                                  ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppTheme.primaryGreen,
        foregroundColor: Colors.white,
        onPressed: _openCreatePurchase,
        icon: const Icon(Icons.add_shopping_cart_rounded),
        label: const Text('Pembelian Baru'),
      ),
    );
  }
}

class PurchaseFormScreen extends StatefulWidget {
  const PurchaseFormScreen({super.key});

  @override
  State<PurchaseFormScreen> createState() => _PurchaseFormScreenState();
}

class _PurchaseFormScreenState extends State<PurchaseFormScreen> {
  final TextEditingController _noCtrl = TextEditingController();
  final TextEditingController _supplierCtrl = TextEditingController();
  final TextEditingController _phoneCtrl = TextEditingController();
  final TextEditingController _noteCtrl = TextEditingController();
  final TextEditingController _transferAccountCtrl = TextEditingController(text: 'Transfer Bank');
  final TextEditingController _transferRefCtrl = TextEditingController();
  final TextEditingController _splitCashCtrl = TextEditingController(text: '0');
  final TextEditingController _splitTransferCtrl = TextEditingController(text: '0');
  final TextEditingController _splitCreditCtrl = TextEditingController(text: '0');

  String _paymentMethod = 'kas_laci';
  DateTime _dueDate = DateTime.now().add(const Duration(days: 14));
  bool _updateCost = true;
  bool _saving = false;

  final List<PurchaseItemModel> _items = [];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _noCtrl.text = 'PO-${now.year}${now.month.toString().padLeft(2, '0')}-${Random().nextInt(9000) + 1000}';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<CashFlowProvider>(context, listen: false).checkOpenShift();
    });
  }

  @override
  void dispose() {
    _noCtrl.dispose();
    _supplierCtrl.dispose();
    _phoneCtrl.dispose();
    _noteCtrl.dispose();
    _transferAccountCtrl.dispose();
    _transferRefCtrl.dispose();
    _splitCashCtrl.dispose();
    _splitTransferCtrl.dispose();
    _splitCreditCtrl.dispose();
    super.dispose();
  }

  void _addProductPicker() {
    final products = Provider.of<ProductProvider>(context, listen: false)
        .allProducts
        .where((p) => !p.isService)
        .toList();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pilih Produk Restock'),
        content: SizedBox(
          width: 400,
          height: 360,
          child: ListView.builder(
            itemCount: products.length,
            itemBuilder: (_, i) {
              final ProductModel p = products[i];
              return ListTile(
                title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                subtitle: Text('Stok saat ini: ${p.stock.toInt()} ${p.baseUnit} • HPP: ${CurrencyHelper.format(p.costPrice)}'),
                onTap: () {
                  setState(() {
                    _items.add(
                      PurchaseItemModel(
                        productId: p.id!,
                        productName: p.name,
                        qty: 1,
                        unitName: p.baseUnit,
                        conversionFactor: 1.0,
                        costPrice: p.costPrice,
                        subtotal: p.costPrice,
                      ),
                    );
                  });
                  Navigator.pop(ctx);
                },
              );
            },
          ),
        ),
      ),
    );
  }

  double get _totalAmount => _items.fold(0.0, (s, e) => s + e.subtotal);

  double _parseNum(TextEditingController ctrl) =>
      double.tryParse(ctrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0.0;

  Future<void> _save() async {
    if (_supplierCtrl.text.trim().isEmpty || _items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Isi nama supplier dan pilih minimal 1 produk.')),
      );
      return;
    }

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final cashFlow = Provider.of<CashFlowProvider>(context, listen: false);
    final purchaseProv = Provider.of<PurchaseProvider>(context, listen: false);
    final prodProv = Provider.of<ProductProvider>(context, listen: false);

    double cashPaid = 0.0;
    double transferPaid = 0.0;
    double creditAmount = 0.0;

    switch (_paymentMethod) {
      case 'kas_laci':
        cashPaid = _totalAmount;
        break;
      case 'transfer':
        transferPaid = _totalAmount;
        if (_transferAccountCtrl.text.trim().isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Isi nama bank / rekening pengirim transfer.'), backgroundColor: AppTheme.accentRed),
          );
          return;
        }
        break;
      case 'hutang':
        creditAmount = _totalAmount;
        break;
      case 'campuran':
        cashPaid = _parseNum(_splitCashCtrl);
        transferPaid = _parseNum(_splitTransferCtrl);
        creditAmount = _parseNum(_splitCreditCtrl);
        if ((cashPaid + transferPaid + creditAmount - _totalAmount).abs() > 1.0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Jumlah Kas + Transfer + Hutang harus sama dengan ${CurrencyHelper.format(_totalAmount)}.'),
              backgroundColor: AppTheme.accentRed,
            ),
          );
          return;
        }
        if (transferPaid > 0 && _transferAccountCtrl.text.trim().isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Isi nama rekening transfer untuk porsi pembayaran transfer.'), backgroundColor: AppTheme.accentRed),
          );
          return;
        }
        break;
    }

    if (cashPaid > 0) {
      if (!cashFlow.isShiftOpen) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Pembayaran via Kas Laci membutuhkan shift kasir aktif.'),
            backgroundColor: AppTheme.accentRed,
          ),
        );
        return;
      }
      final availCash = cashFlow.currentShift?.expectedCash ?? 0.0;
      if (cashPaid > availCash + 0.01) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Saldo Kas Laci (${CurrencyHelper.format(availCash)}) tidak cukup untuk bayar ${CurrencyHelper.format(cashPaid)}. Gunakan Transfer / Hutang / Campuran.',
            ),
            backgroundColor: AppTheme.accentRed,
          ),
        );
        return;
      }
    }

    setState(() => _saving = true);

    final purchase = PurchaseModel(
      purchaseNumber: _noCtrl.text.trim(),
      supplierName: _supplierCtrl.text.trim(),
      supplierPhone: _phoneCtrl.text.trim(),
      totalAmount: _totalAmount,
      paymentMethod: _paymentMethod,
      cashPaid: cashPaid,
      transferPaid: transferPaid,
      creditAmount: creditAmount,
      transferAccount: _transferAccountCtrl.text.trim(),
      transferRef: _transferRefCtrl.text.trim(),
      dueDate: creditAmount > 0 ? _dueDate : null,
      shiftId: cashPaid > 0 ? cashFlow.currentShift?.id : null,
      note: _noteCtrl.text.trim(),
      createdBy: auth.currentUser?.name ?? 'Admin',
      items: _items,
    );

    try {
      await purchaseProv.recordPurchase(
        purchase,
        shiftId: cashFlow.currentShift?.id,
        updateProductCost: _updateCost,
      );
      await prodProv.loadProducts();
      await cashFlow.checkOpenShift();
      await auth.logAction(
        'pembelian_stok',
        'Pembelian #${purchase.purchaseNumber} dari ${purchase.supplierName} senilai ${CurrencyHelper.format(purchase.totalAmount)} ($_paymentMethod)',
        module: 'pembelian',
        objectId: purchase.purchaseNumber,
      );

      if (!mounted) return;
      setState(() => _saving = false);
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pembelian & stok berhasil dicatat!'), backgroundColor: AppTheme.success),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
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
    final drawerCash = cashFlow.currentShift?.expectedCash ?? 0.0;

    return Scaffold(
      appBar: AppBar(title: const Text('Catat Pembelian Supplier')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(controller: _noCtrl, decoration: const InputDecoration(labelText: 'No. Pembelian / PO')),
                const SizedBox(height: 10),
                AppBreakpoints.buildResponsivePair(
                  minPairWidth: 360,
                  spacing: 10,
                  first: TextField(
                    controller: _supplierCtrl,
                    decoration: const InputDecoration(labelText: 'Nama Supplier / Agen *'),
                  ),
                  second: TextField(
                    controller: _phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'No. WA Supplier'),
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: _paymentMethod,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Sumber Dana / Metode Pembayaran'),
                  items: const [
                    DropdownMenuItem(value: 'kas_laci', child: Text('Kas Laci Kasir (Tunai)', maxLines: 1, overflow: TextOverflow.ellipsis)),
                    DropdownMenuItem(value: 'transfer', child: Text('Transfer Bank / E-Wallet', maxLines: 1, overflow: TextOverflow.ellipsis)),
                    DropdownMenuItem(value: 'hutang', child: Text('Hutang / Tempo Supplier', maxLines: 1, overflow: TextOverflow.ellipsis)),
                    DropdownMenuItem(value: 'campuran', child: Text('Campuran (Tunai + Transfer + Tempo)', maxLines: 1, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) => setState(() => _paymentMethod = v ?? 'kas_laci'),
                ),
                if (_paymentMethod == 'kas_laci' || _paymentMethod == 'campuran') ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: cashFlow.isShiftOpen ? AppTheme.primaryGreenSoft : AppTheme.accentRedSoft,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      cashFlow.isShiftOpen
                          ? 'Saldo Kas Laci Aktif saat ini: ${CurrencyHelper.format(drawerCash)}'
                          : 'Perhatian: Shift kasir belum dibuka! Buka shift dulu untuk mengambil dana dari Kas Laci.',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: cashFlow.isShiftOpen ? AppTheme.primaryGreen : AppTheme.accentRed,
                      ),
                    ),
                  ),
                ],
                if (_paymentMethod == 'transfer' || _paymentMethod == 'campuran') ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _transferAccountCtrl,
                          decoration: const InputDecoration(labelText: 'Bank / Rekening Sumber *'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _transferRefCtrl,
                          decoration: const InputDecoration(labelText: 'No. Referensi (Opsional)'),
                        ),
                      ),
                    ],
                  ),
                ],
                if (_paymentMethod == 'hutang' || _paymentMethod == 'campuran') ...[
                  const SizedBox(height: 10),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: const BorderSide(color: AppTheme.borderLight),
                    ),
                    tileColor: Colors.white,
                    leading: const Icon(Icons.event_rounded, color: AppTheme.accentOrange),
                    title: const Text('Tanggal Jatuh Tempo Supplier', style: TextStyle(fontSize: 13)),
                    subtitle: Text(DateHelper.formatShort(_dueDate), style: const TextStyle(fontWeight: FontWeight.bold)),
                    trailing: TextButton(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _dueDate,
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
                        );
                        if (picked != null) setState(() => _dueDate = picked);
                      },
                      child: const Text('Ubah'),
                    ),
                  ),
                ],
                if (_paymentMethod == 'campuran') ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _splitCashCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Tunai Laci', prefixText: 'Rp '),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _splitTransferCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Transfer', prefixText: 'Rp '),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _splitCreditCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Sisa Hutang', prefixText: 'Rp '),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 8),
                TextField(
                  controller: _noteCtrl,
                  decoration: const InputDecoration(labelText: 'Catatan Pembelian (Opsional)'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Update HPP / Harga Modal Produk Otomatis'),
                  value: _updateCost,
                  onChanged: (v) => setState(() => _updateCost = v),
                ),
                const Divider(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Daftar Barang Dibeli', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    ElevatedButton.icon(
                      onPressed: _addProductPicker,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Tambah Produk'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (_items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: Text('Belum ada item dipilih.', style: TextStyle(color: AppTheme.textMuted))),
                  )
                else
                  ..._items.asMap().entries.map((e) {
                    final idx = e.key;
                    final item = e.value;
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(item.productName,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, color: AppTheme.accentRed),
                                  onPressed: () => setState(() => _items.removeAt(idx)),
                                ),
                              ],
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                QuantityStepper(
                                  value: item.qty,
                                  minValue: 1,
                                  allowDecimal: true,
                                  unitLabel: item.unitName,
                                  onChanged: (q) {
                                    setState(() {
                                      _items[idx] = PurchaseItemModel(
                                        productId: item.productId,
                                        productName: item.productName,
                                        qty: q,
                                        unitName: item.unitName,
                                        conversionFactor: item.conversionFactor,
                                        costPrice: item.costPrice,
                                        subtotal: q * item.costPrice,
                                      );
                                    });
                                  },
                                ),
                                TextButton(
                                  onPressed: () {
                                    final costCtrl = TextEditingController(text: item.costPrice.toInt().toString());
                                    showDialog(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        title: Text('Harga Beli / HPP (${item.productName})'),
                                        content: TextField(
                                          controller: costCtrl,
                                          keyboardType: TextInputType.number,
                                          decoration: const InputDecoration(labelText: 'Harga per Satuan (Rp)', prefixText: 'Rp '),
                                        ),
                                        actions: [
                                          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
                                          ElevatedButton(
                                            onPressed: () {
                                              final c = double.tryParse(costCtrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? item.costPrice;
                                              setState(() {
                                                _items[idx] = PurchaseItemModel(
                                                  productId: item.productId,
                                                  productName: item.productName,
                                                  qty: item.qty,
                                                  unitName: item.unitName,
                                                  conversionFactor: item.conversionFactor,
                                                  costPrice: c,
                                                  subtotal: item.qty * c,
                                                );
                                              });
                                              Navigator.pop(ctx);
                                            },
                                            child: const Text('Terapkan'),
                                          ),
                                        ],
                                      ),
                                    ).then((_) => costCtrl.dispose());
                                  },
                                  child: Text(
                                    CurrencyHelper.format(item.subtotal),
                                    style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryGreen),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  }),

                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: AppTheme.cardDecoration(),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('TOTAL PEMBELIAN', style: TextStyle(fontWeight: FontWeight.bold)),
                      Text(
                        CurrencyHelper.format(_totalAmount),
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primaryGreen),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: const Icon(Icons.check_circle_rounded),
                    label: Text(_saving ? 'MENYIMPAN...' : 'SIMPAN PEMBELIAN & TAMBAH STOK'),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
