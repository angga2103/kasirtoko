import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/debt_provider.dart';
import '../../providers/settings_provider.dart';
import '../../models/customer_debt.dart';
import '../../services/whatsapp_service.dart';
import '../../services/document_service.dart';
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

  void _showPaymentDialog(CustomerDebtModel debt) {
    final payCtrl = TextEditingController(text: debt.remainingDebt.toInt().toString());

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('Pelunasan Kasbon: ${debt.customerName}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('No. Nota: ${debt.invoiceNumber}'),
              Text('Total Tagihan: ${CurrencyHelper.format(debt.totalDebt)}'),
              Text('Sisa Belum Bayar: ${CurrencyHelper.format(debt.remainingDebt)}',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.accentRed)),
              const SizedBox(height: 12),
              TextField(
                controller: payCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Nominal Pembayaran Diterima',
                  prefixText: 'Rp ',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
            ElevatedButton(
              onPressed: () async {
                final amount = double.tryParse(payCtrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0.0;
                if (amount > 0) {
                  await Provider.of<DebtProvider>(context, listen: false).payDebt(debt.id!, amount);
                  if (mounted) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Pembayaran ${CurrencyHelper.format(amount)} berhasil dicatat.')),
                    );
                  }
                }
              },
              child: const Text('Simpan Pembayaran'),
            ),
          ],
        );
      },
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
                    Row(
                      children: [
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
                        // Invoice Penagihan PDF Print
                        IconButton(
                          icon: const Icon(Icons.print_rounded, color: Colors.blue),
                          tooltip: 'Cetak Surat Invoice Penagihan',
                          onPressed: () async {
                            await DocumentService.printDebtInvoice(
                              debt: d,
                              storeName: settings.storeName,
                              storeAddress: settings.storeAddress,
                              storePhone: settings.storePhone,
                            );
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
