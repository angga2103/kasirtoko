import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/transaction.dart';
import '../../database/db_helper.dart';
import '../../providers/settings_provider.dart';
import '../../providers/cash_flow_provider.dart';
import '../../services/whatsapp_service.dart';
import '../../services/excel_service.dart';
import '../../utils/app_theme.dart';
import '../../utils/currency_format.dart';
import '../../utils/date_format.dart';

class DailyReportScreen extends StatefulWidget {
  const DailyReportScreen({super.key});

  @override
  State<DailyReportScreen> createState() => _DailyReportScreenState();
}

class _DailyReportScreenState extends State<DailyReportScreen> {
  List<TransactionModel> _transactions = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final list = await DatabaseHelper.instance.getRecentTransactions(limit: 100);
    setState(() {
      _transactions = list;
      _isLoading = false;
    });
  }

  double get _totalSales =>
      _transactions.where((t) => t.status != 'voided').fold(0.0, (sum, t) => sum + t.grandTotal);

  double get _totalGrossProfit {
    double profit = 0.0;
    for (final t in _transactions.where((t) => t.status != 'voided')) {
      for (final item in t.items) {
        if (!item.isService) {
          profit += (item.unitPrice - item.costPrice) * item.qty;
        } else {
          profit += item.subtotal;
        }
      }
    }
    return profit;
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context);
    final cashFlow = Provider.of<CashFlowProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Laporan Penjualan'),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download_rounded),
            tooltip: 'Ekspor Excel',
            onPressed: () async {
              if (_transactions.isNotEmpty) {
                final path = await ExcelService.exportTransactionsToExcel(_transactions);
                if (path.isNotEmpty && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Laporan berhasil diekspor ke Excel!')),
                  );
                }
              }
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // KPI Cards
                  Row(
                    children: [
                      Expanded(
                        child: _buildMetricCard(
                          title: 'Total Penjualan',
                          value: CurrencyHelper.format(_totalSales),
                          icon: Icons.payments_rounded,
                          color: AppTheme.primaryGreen,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildMetricCard(
                          title: 'Estimasi Laba Kotor',
                          value: CurrencyHelper.format(_totalGrossProfit),
                          icon: Icons.trending_up_rounded,
                          color: Colors.teal,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  Row(
                    children: [
                      Expanded(
                        child: _buildMetricCard(
                          title: 'Total Transaksi',
                          value: '${_transactions.length} Nota',
                          icon: Icons.receipt_long_rounded,
                          color: Colors.blue,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildMetricCard(
                          title: 'Kas di Laci',
                          value: cashFlow.isShiftOpen
                              ? CurrencyHelper.format(cashFlow.currentShift!.expectedCash)
                              : 'Shift Tutup',
                          icon: Icons.point_of_sale_rounded,
                          color: Colors.deepOrange,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Send to WhatsApp Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green.shade700,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      icon: const Icon(Icons.share_rounded, color: Colors.white),
                      label: const Text(
                        'KIRIM LAPORAN KE WHATSAPP OWNER',
                        style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                      onPressed: () async {
                        if (cashFlow.currentShift != null) {
                          await WhatsAppService.sendShiftReportToAdmin(
                            shift: cashFlow.currentShift!,
                            ownerPhone: settings.ownerPhone,
                            storeName: settings.storeName,
                            totalTransactions: _transactions.length,
                            totalGrossProfit: _totalGrossProfit,
                          );
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Buka shift terlebih dahulu untuk mengirim laporan lengkap.')),
                          );
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Recent Transactions List
                  const Text('Daftar Transaksi Terakhir:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 8),

                  if (_transactions.isEmpty)
                    const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Belum ada transaksi.')))
                  else
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _transactions.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (context, index) {
                        final t = _transactions[index];
                        final isVoid = t.status == 'voided';
                        final isReturn = t.status == 'partial_return' || t.status == 'returned';

                        return Card(
                          child: ListTile(
                            title: Text(
                              t.invoiceNumber,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                decoration: isVoid ? TextDecoration.lineThrough : null,
                              ),
                            ),
                            subtitle: Text(
                              '${DateHelper.formatReceipt(t.date)} • ${t.paymentMethod.toUpperCase()} • Kasir: ${t.cashierName}\nPelanggan: ${t.customerName}',
                              style: const TextStyle(fontSize: 11),
                            ),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  CurrencyHelper.format(t.grandTotal),
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: isVoid ? Colors.grey : AppTheme.primaryGreen,
                                  ),
                                ),
                                if (isReturn)
                                  const Text('ADA RETUR', style: TextStyle(fontSize: 9, color: Colors.orange, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
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
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
