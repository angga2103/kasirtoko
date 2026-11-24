import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/cash_flow_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/whatsapp_service.dart';
import '../../utils/app_theme.dart';
import '../../utils/currency_format.dart';
import '../../utils/date_format.dart';

class ShiftScreen extends StatefulWidget {
  const ShiftScreen({super.key});

  @override
  State<ShiftScreen> createState() => _ShiftScreenState();
}

class _ShiftScreenState extends State<ShiftScreen> {
  final TextEditingController _startingCashCtrl = TextEditingController(text: '100000');
  final TextEditingController _actualCashCtrl = TextEditingController();
  final TextEditingController _closeNoteCtrl = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final cashFlow = Provider.of<CashFlowProvider>(context);
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final settings = Provider.of<SettingsProvider>(context, listen: false);

    final shift = cashFlow.currentShift;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manajemen Shift Kasir'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: cashFlow.isShiftOpen
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Active Shift Summary Card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.primaryGreen.withOpacity(0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Shift Aktif',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.green.shade100,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'TERBUKA',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green.shade800,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text('Kasir: ${shift!.cashierName}', style: const TextStyle(fontSize: 13)),
                        Text('Mulai: ${DateHelper.formatFull(shift.startTime)}',
                            style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                        const Divider(height: 20),

                        _buildShiftRow('Modal Awal (Kas Floating)', CurrencyHelper.format(shift.startingCash)),
                        _buildShiftRow('Penjualan Tunai', CurrencyHelper.format(shift.totalSalesCash)),
                        _buildShiftRow('Kas Masuk Lain', '+${CurrencyHelper.format(shift.totalCashIn)}'),
                        _buildShiftRow('Pengeluaran Operasional', '-${CurrencyHelper.format(shift.totalCashOut)}'),
                        _buildShiftRow('Retur Tunai', '-${CurrencyHelper.format(shift.totalReturnCash)}'),
                        const Divider(height: 16),
                        _buildShiftRow(
                          'TOTAL KAS SISTEM DI LACI',
                          CurrencyHelper.format(shift.expectedCash),
                          isBold: true,
                          highlightColor: AppTheme.primaryGreen,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Close Shift Form (Blind Count)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Tutup Shift (Blind Cash Count):',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Hitung seluruh uang fisik di laci kasir dan masukkan nominalnya di bawah ini.',
                          style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _actualCashCtrl,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          decoration: const InputDecoration(
                            labelText: 'Uang Fisik Dihitung Kasir *',
                            prefixText: 'Rp ',
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _closeNoteCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Catatan Kasir / Keterangan Selisih (Opsional)',
                          ),
                        ),
                        const SizedBox(height: 16),

                        if (_actualCashCtrl.text.isNotEmpty) ...[
                          Builder(
                            builder: (context) {
                              final count = double.tryParse(_actualCashCtrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0.0;
                              final diff = count - shift.expectedCash;
                              final isBalanced = diff == 0;
                              final isOver = diff > 0;

                              return Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: isBalanced
                                      ? Colors.green.shade50
                                      : (isOver ? Colors.blue.shade50 : Colors.red.shade50),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: isBalanced
                                        ? Colors.green
                                        : (isOver ? Colors.blue : Colors.red),
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text('Status Selisih:', style: TextStyle(fontWeight: FontWeight.bold)),
                                    Text(
                                      isBalanced
                                          ? 'SESUAI (Rp 0)'
                                          : (isOver
                                              ? 'LEBIH (+${CurrencyHelper.format(diff)})'
                                              : 'KURANG (${CurrencyHelper.format(diff)})'),
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                        color: isBalanced
                                            ? Colors.green.shade800
                                            : (isOver ? Colors.blue.shade800 : Colors.red.shade800),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 16),
                        ],

                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accentOrange),
                            onPressed: _actualCashCtrl.text.isEmpty
                                ? null
                                : () async {
                                    final count = double.tryParse(
                                            _actualCashCtrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ??
                                        0.0;

                                    final shiftCopy = shift;

                                    await cashFlow.endShift(
                                      actualCashCount: count,
                                      note: _closeNoteCtrl.text,
                                    );

                                    // Audit log
                                    await auth.logAction(
                                      'tutup_shift',
                                      'Tutup shift kasir ${shiftCopy.cashierName}: Fisik: ${CurrencyHelper.format(count)}, Selisih: ${CurrencyHelper.format(count - shiftCopy.expectedCash)}',
                                    );

                                    if (!mounted) return;

                                    // Prompt to send shift report to WhatsApp
                                    showDialog(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        title: const Text('Shift Telah Ditutup'),
                                        content: const Text(
                                            'Ingin langsung kirim ringkasan laporan shift ini ke WhatsApp Owner?'),
                                        actions: [
                                          TextButton(
                                            onPressed: () {
                                              Navigator.pop(ctx);
                                              Navigator.pop(context);
                                            },
                                            child: const Text('Nanti'),
                                          ),
                                          ElevatedButton.icon(
                                            icon: const Icon(Icons.share_rounded),
                                            label: const Text('Kirim ke WA Owner'),
                                            onPressed: () async {
                                              Navigator.pop(ctx);
                                              await WhatsAppService.sendShiftReportToAdmin(
                                                shift: shiftCopy,
                                                ownerPhone: settings.ownerPhone,
                                                storeName: settings.storeName,
                                                totalTransactions: 0,
                                                totalGrossProfit: 0.0,
                                              );
                                              if (mounted) Navigator.pop(context);
                                            },
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                            child: const Text('TUTUP SHIFT KASIR SEKARANG'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              )
            : Center(
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.point_of_sale_rounded, size: 54, color: AppTheme.primaryGreen),
                      const SizedBox(height: 12),
                      const Text(
                        'Shift Kasir Sedang Tertutup',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Masukkan modal uang kembalian awal di laci untuk memulai penjualan hari ini.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _startingCashCtrl,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        decoration: const InputDecoration(
                          labelText: 'Modal Awal Kas (Laci)',
                          prefixText: 'Rp ',
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () async {
                            final startCash = double.tryParse(
                                    _startingCashCtrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ??
                                0.0;
                            final user = auth.currentUser;
                            await cashFlow.startShift(
                              cashierId: user?.id ?? 1,
                              cashierName: user?.name ?? 'Kasir',
                              startingCash: startCash,
                            );

                            await auth.logAction(
                              'buka_shift',
                              'Buka shift kasir ${user?.name} dengan modal: ${CurrencyHelper.format(startCash)}',
                            );
                          },
                          child: const Text('BUKA SHIFT SEKARANG', style: TextStyle(fontSize: 16)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildShiftRow(String label, String value, {bool isBold = false, Color? highlightColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: isBold ? 13 : 12,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: isBold ? 14 : 12,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              color: highlightColor ?? AppTheme.textDark,
            ),
          ),
        ],
      ),
    );
  }
}
