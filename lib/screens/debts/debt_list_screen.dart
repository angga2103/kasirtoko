import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/cash_flow_provider.dart';
import '../../providers/debt_provider.dart';
import '../../providers/printer_provider.dart';
import '../../providers/settings_provider.dart';
import '../../models/customer_debt.dart';
import '../../services/printer/printer_manager.dart';
import '../../services/whatsapp_service.dart';
import '../../utils/app_theme.dart';
import '../../utils/currency_format.dart';
import '../../utils/date_format.dart';

class DebtListScreen extends StatefulWidget {
  const DebtListScreen({super.key});

  @override
  State<DebtListScreen> createState() => _DebtListScreenState();
}

class _DebtListScreenState extends State<DebtListScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<DebtProvider>(context, listen: false).loadDebts();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _showPaymentDialog(CustomerDebtModel debt) {
    final payCtrl = TextEditingController(text: debt.remainingDebt.toInt().toString());
    final noteCtrl = TextEditingController();
    final cashFlow = Provider.of<CashFlowProvider>(context, listen: false);
    final auth = Provider.of<AuthProvider>(context, listen: false);
    String method = 'tunai';
    String? errMsg;
    bool saving = false;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDState) => AlertDialog(
            title: Text('Pelunasan Kasbon: ${debt.customerName}'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('No. Nota: ${debt.invoiceNumber}'),
                  Text('Total Tagihan: ${CurrencyHelper.format(debt.totalDebt)}'),
                  Text(
                    'Sisa Belum Bayar: ${CurrencyHelper.format(debt.remainingDebt)}',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.accentRed),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: method,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Metode Pembayaran'),
                    items: const [
                      DropdownMenuItem(value: 'tunai', child: Text('Tunai (Masuk Kas Laci)', maxLines: 1, overflow: TextOverflow.ellipsis)),
                      DropdownMenuItem(value: 'transfer', child: Text('Transfer Bank', maxLines: 1, overflow: TextOverflow.ellipsis)),
                      DropdownMenuItem(value: 'qris', child: Text('QRIS', maxLines: 1, overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (v) => setDState(() => method = v ?? 'tunai'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: payCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Nominal Pembayaran Diterima',
                      prefixText: 'Rp ',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: noteCtrl,
                    decoration: const InputDecoration(labelText: 'Catatan Pembayaran (Opsional)'),
                  ),
                  if (errMsg != null) ...[
                    const SizedBox(height: 8),
                    Text(errMsg!, style: const TextStyle(color: AppTheme.accentRed, fontSize: 12)),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: saving ? null : () => Navigator.pop(ctx), child: const Text('Batal')),
              ElevatedButton(
                onPressed: saving
                    ? null
                    : () async {
                        final amount = double.tryParse(payCtrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0.0;
                        if (amount <= 0) {
                          setDState(() => errMsg = 'Nominal pembayaran harus lebih dari Rp 0.');
                          return;
                        }
                        if (method == 'tunai' && !cashFlow.isShiftOpen) {
                          setDState(() => errMsg = 'Shift kasir belum dibuka untuk menerima setoran tunai.');
                          return;
                        }
                        setDState(() {
                          saving = true;
                          errMsg = null;
                        });
                        try {
                          await Provider.of<DebtProvider>(context, listen: false).payDebt(
                            debt.id!,
                            amount,
                            paymentMethod: method,
                            shiftId: cashFlow.currentShift?.id,
                            cashierName: auth.currentUser?.name ?? 'Kasir',
                            note: noteCtrl.text.trim(),
                          );
                          await cashFlow.checkOpenShift();
                          await auth.logAction(
                            'bayar_kasbon',
                            'Pembayaran kasbon nota ${debt.invoiceNumber} (${debt.customerName}): ${CurrencyHelper.format(amount)} ($method)',
                            module: 'kasbon',
                            objectId: debt.invoiceNumber,
                          );
                          if (ctx.mounted) Navigator.pop(ctx);
                          if (mounted) {
                            ScaffoldMessenger.of(this.context).showSnackBar(
                              SnackBar(
                                content: Text('Pembayaran ${CurrencyHelper.format(amount)} berhasil dicatat.'),
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
                child: Text(saving ? 'Menyimpan...' : 'Simpan Pembayaran'),
              ),
            ],
          ),
        );
      },
    ).whenComplete(() {
      Future.delayed(const Duration(milliseconds: 300), () {
        payCtrl.dispose();
        noteCtrl.dispose();
      });
    });
  }

  Future<void> _showDebtPaymentHistory(CustomerDebtModel debt) async {
    final payments = await Provider.of<DebtProvider>(context, listen: false).getDebtPayments(debt.id!);
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        title: Text('Riwayat Cicilan • ${debt.invoiceNumber}', style: const TextStyle(fontSize: 16)),
        content: SizedBox(
          width: AppBreakpoints.boundedDialogWidth(ctx, maxWidth: 420),
          height: payments.isEmpty ? null : (MediaQuery.sizeOf(ctx).height * 0.5).clamp(160.0, 360.0),
          child: payments.isEmpty
              ? const Text('Belum ada pembayaran atau pemotongan saldo pada kasbon ini.')
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: payments.length,
                  separatorBuilder: (_, __) => const Divider(height: 10),
                  itemBuilder: (_, i) {
                    final pay = payments[i];
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        CurrencyHelper.format(pay.amount),
                        style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryGreen),
                      ),
                      subtitle: Text(
                        '${DateHelper.formatFull(pay.date)} • ${pay.paymentMethod.toUpperCase()} • ${pay.cashierName}'
                        '${pay.note.isNotEmpty ? "\n${pay.note}" : ""}',
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

  @override
  Widget build(BuildContext context) {
    final debtProv = Provider.of<DebtProvider>(context);
    final settings = Provider.of<SettingsProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Buku Kasbon & Surat Tagihan'),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: AppTheme.accentOrange,
          tabs: [
            Tab(text: 'Semua (${debtProv.debts.length})'),
            Tab(text: 'Lewat Tempo (${debtProv.overdueCount})'),
            Tab(text: 'Belum Lunas (${debtProv.unpaidDebts.length})'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildDebtList(debtProv.debts, settings),
          _buildDebtList(debtProv.overdueDebts, settings),
          _buildDebtList(debtProv.unpaidDebts, settings),
        ],
      ),
    );
  }

  Widget _buildDebtList(List<CustomerDebtModel> list, SettingsProvider settings) {
    if (list.isEmpty) {
      return const Center(
        child: Text('Tidak ada catatan kasbon pada kategori ini.'),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: list.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final d = list[index];
        final isOverdue = d.isOverdue;

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      d.customerName,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: d.isPaidOff
                            ? Colors.green.shade100
                            : (isOverdue ? Colors.red.shade100 : Colors.amber.shade100),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        d.isPaidOff ? 'LUNAS' : (isOverdue ? 'JATUH TEMPO LEWAT' : 'BELUM LUNAS'),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: d.isPaidOff
                              ? Colors.green.shade800
                              : (isOverdue ? Colors.red.shade800 : Colors.amber.shade900),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Nota: ${d.invoiceNumber} • No. WA: ${d.customerPhone.isNotEmpty ? d.customerPhone : "-"}',
                  style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                ),
                Text(
                  'Tgl Nota: ${DateHelper.formatShort(d.transactionDate)} • Jatuh Tempo: ${DateHelper.formatShort(d.dueDate)}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: isOverdue ? FontWeight.bold : FontWeight.normal,
                    color: isOverdue ? AppTheme.accentRed : AppTheme.textMuted,
                  ),
                ),
                const Divider(height: 16),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Sisa Tagihan:', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                        Text(
                          CurrencyHelper.format(d.remainingDebt),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: d.isPaidOff ? AppTheme.primaryGreen : AppTheme.accentRed,
                          ),
                        ),
                      ],
                    ),
                    Wrap(
                      spacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        // History Cicilan
                        IconButton(
                          icon: const Icon(Icons.history_rounded, color: AppTheme.textSecondary),
                          tooltip: 'Riwayat Cicilan Kasbon',
                          onPressed: () => _showDebtPaymentHistory(d),
                        ),
                        // WhatsApp Reminder
                        IconButton(
                          icon: const Icon(Icons.share_rounded, color: Colors.green),
                          tooltip: 'Kirim Tagihan via WhatsApp',
                          onPressed: () async {
                            final ok = await WhatsAppService.sendDebtReminder(
                              debt: d,
                              storeName: settings.storeName,
                              storePhone: settings.storePhone,
                            );
                            if (!ok && context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Nomor WA pelanggan tidak valid.')),
                              );
                            }
                          },
                        ),
                        // Invoice Penagihan Print (Adapter-Aware)
                        IconButton(
                          icon: const Icon(Icons.print_rounded, color: Colors.blue),
                          tooltip: 'Cetak Surat Invoice Penagihan',
                          onPressed: () async {
                            final printerProv = Provider.of<PrinterProvider>(context, listen: false);
                            final res = await PrinterManager.printDebtInvoice(
                              printer: printerProv.defaultPrinter,
                              debt: d,
                              storeName: settings.storeName,
                              storeAddress: settings.storeAddress,
                              storePhone: settings.storePhone,
                              logoPath: settings.logoPath,
                            );
                            if (!res.success && context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(res.message), backgroundColor: AppTheme.accentOrange),
                              );
                            }
                          },
                        ),
                        if (!d.isPaidOff)
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            ),
                            onPressed: () => _showPaymentDialog(d),
                            child: const Text('Bayar'),
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
    );
  }
}
