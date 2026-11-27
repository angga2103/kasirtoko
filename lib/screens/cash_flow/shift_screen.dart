import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../database/db_helper.dart';
import '../../models/shift.dart';
import '../../providers/auth_provider.dart';
import '../../providers/cash_flow_provider.dart';
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
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      Provider.of<CashFlowProvider>(context, listen: false).checkOpenShift(
        cashierId: auth.currentUser?.id,
        terminalId: 'ADMIN',
      );
    });
  }

  @override
  void dispose() {
    _startingCashCtrl.dispose();
    _actualCashCtrl.dispose();
    _closeNoteCtrl.dispose();
    super.dispose();
  }

  Future<void> _showAdminCorrectDialog(ShiftModel closedShift) async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final cashFlow = Provider.of<CashFlowProvider>(context, listen: false);
    final admin = auth.currentUser;
    if (admin == null || !admin.isOwnerOrAdmin) return;

    final cashCtrl = TextEditingController(
      text: (closedShift.actualCash ?? closedShift.expectedCash).toInt().toString(),
    );
    final noteCtrl = TextEditingController();
    String? errMsg;
    bool saving = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.admin_panel_settings_rounded, color: AppTheme.accentOrange),
              SizedBox(width: 8),
              Expanded(child: Text('Koreksi Audit Shift Tertutup')),
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Shift #${closedShift.id} • Kasir: ${closedShift.cashierName}\nKas Sistem: ${CurrencyHelper.format(closedShift.expectedCash)}',
                    style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: cashCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Nominal Kas Fisik Terkoreksi (Rp) *',
                      prefixText: 'Rp ',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: noteCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Alasan Koreksi Owner/Admin *',
                      hintText: 'Wajib diisi untuk jejak audit',
                    ),
                  ),
                  if (errMsg != null) ...[
                    const SizedBox(height: 8),
                    Text(errMsg!, style: const TextStyle(color: AppTheme.accentRed, fontSize: 12)),
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
                      final newCash = double.tryParse(cashCtrl.text.replaceAll(RegExp(r'[^0-9]'), ''));
                      if (newCash == null) {
                        setDState(() => errMsg = 'Nominal kas tidak valid.');
                        return;
                      }
                      if (noteCtrl.text.trim().isEmpty) {
                        setDState(() => errMsg = 'Alasan koreksi wajib diisi.');
                        return;
                      }
                      setDState(() {
                        saving = true;
                        errMsg = null;
                      });
                      try {
                        await DatabaseHelper.instance.adminCorrectShift(
                          shiftId: closedShift.id!,
                          newActualCash: newCash,
                          correctionNote: noteCtrl.text.trim(),
                          admin: admin,
                        );
                        await cashFlow.checkOpenShift();
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) {
                          ScaffoldMessenger.of(this.context).showSnackBar(
                            const SnackBar(
                              content: Text('Koreksi shift tercatat dalam audit log.'),
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
              child: Text(saving ? 'Menyimpan...' : 'Simpan Koreksi'),
            ),
          ],
        ),
      ),
    ).then((_) {
      cashCtrl.dispose();
      noteCtrl.dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    final cashFlow = Provider.of<CashFlowProvider>(context);
    final auth = Provider.of<AuthProvider>(context);
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final shift = cashFlow.currentShift;
    final closedHistory = cashFlow.shiftHistory.where((s) => !s.isOpen).toList();
    final isOwnerOrAdmin = auth.currentUser?.isOwnerOrAdmin == true;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manajemen Shift Kasir'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (cashFlow.isShiftOpen && shift != null) ...[
                  // Active Shift Summary Card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.primaryGreen.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Expanded(
                              child: Text(
                                'Shift Aktif',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                            ),
                            const SizedBox(width: 8),
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
                        Text('Kasir: ${shift.cashierName}', style: const TextStyle(fontSize: 13)),
                        Text(
                          'Laci Kas: #${shift.cashRegisterId} • Terminal: ${shift.terminalId} • Mode: ${shift.drawerMode}',
                          style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                        ),
                        Text('Mulai: ${DateHelper.formatFull(shift.startTime)}',
                            style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                        const Divider(height: 20),

                        _buildShiftRow('Modal Awal (Kas Floating)', CurrencyHelper.format(shift.startingCash)),
                        _buildShiftRow('Penjualan Tunai', CurrencyHelper.format(shift.totalSalesCash)),
                        _buildShiftRow('Penjualan QRIS', CurrencyHelper.format(shift.totalSalesQris)),
                        _buildShiftRow('Penjualan Transfer', CurrencyHelper.format(shift.totalSalesTransfer)),
                        _buildShiftRow('Penjualan Kasbon', CurrencyHelper.format(shift.totalSalesKasbon)),
                        _buildShiftRow('Kas Masuk Lain', '+${CurrencyHelper.format(shift.totalCashIn)}'),
                        _buildShiftRow('Pengeluaran / Pembelian Kas Laci', '-${CurrencyHelper.format(shift.totalCashOut)}'),
                        _buildShiftRow('Retur Tunai', '-${CurrencyHelper.format(shift.totalReturnCash)}'),
                        const Divider(height: 16),
                        _buildShiftRow(
                          'Ekspektasi Uang Tunai di Laci',
                          CurrencyHelper.format(shift.expectedCash),
                          isBold: true,
                          highlightColor: AppTheme.primaryGreen,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Close Shift Card
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
                          'Rekonsiliasi Tutup Shift',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Hitung fisik uang tunai di laci kasir. Jika ada selisih dari kas sistem, catatan penjelasan wajib diisi.',
                          style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _actualCashCtrl,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          decoration: const InputDecoration(
                            labelText: 'Nominal Uang Tunai Fisik di Laci *',
                            prefixText: 'Rp ',
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 10),
                        Builder(
                          builder: (_) {
                            final count = double.tryParse(_actualCashCtrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0.0;
                            final hasDiff = _actualCashCtrl.text.isNotEmpty && (count - shift.expectedCash).abs() > 0.01;
                            return TextField(
                              controller: _closeNoteCtrl,
                              decoration: InputDecoration(
                                labelText: hasDiff
                                    ? 'Catatan Keterangan Selisih (WAJIB DIISI) *'
                                    : 'Catatan Kasir (Opsional)',
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 16),

                        if (_actualCashCtrl.text.isNotEmpty) ...[
                          Builder(
                            builder: (context) {
                              final count = double.tryParse(_actualCashCtrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0.0;
                              final diff = count - shift.expectedCash;
                              final isBalanced = diff.abs() <= 0.01;
                              final isOver = diff > 0;

                              return Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: isBalanced
                                      ? Colors.green.shade50
                                      : (isOver ? Colors.blue.shade50 : Colors.red.shade50),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: isBalanced ? Colors.green : (isOver ? Colors.blue : Colors.red),
                                  ),
                                ),
                                child: AppBreakpoints.spaceBetweenRow(
                                  const Text('Status Selisih:', style: TextStyle(fontWeight: FontWeight.bold)),
                                  Text(
                                    isBalanced
                                        ? 'SESUAI (Rp 0)'
                                        : (isOver
                                            ? 'LEBIH (+${CurrencyHelper.format(diff)})'
                                            : 'KURANG (${CurrencyHelper.format(diff)})'),
                                    textAlign: TextAlign.right,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: isBalanced
                                          ? Colors.green.shade800
                                          : (isOver ? Colors.blue.shade800 : Colors.red.shade800),
                                    ),
                                  ),
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
                            onPressed: _actualCashCtrl.text.trim().isEmpty
                                ? null
                                : () async {
                                    final count = double.tryParse(
                                            _actualCashCtrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ??
                                        0.0;
                                    final diff = count - shift.expectedCash;
                                    if (diff.abs() > 0.01 && _closeNoteCtrl.text.trim().isEmpty) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('Terdapat selisih kas laci. Catatan penjelasan wajib diisi sebelum menutup shift.'),
                                          backgroundColor: AppTheme.accentRed,
                                        ),
                                      );
                                      return;
                                    }

                                    try {
                                      final endResult = await cashFlow.endShift(
                                        actualCashCount: count,
                                        note: _closeNoteCtrl.text.trim(),
                                      );
                                      if (endResult == null) return;

                                      final closedShift = endResult['shift'] as ShiftModel;
                                      final totalTrx = (endResult['totalTransactions'] as int?) ?? 0;
                                      final totalGrossProfit =
                                          (endResult['totalGrossProfit'] as num?)?.toDouble() ?? 0.0;

                                      await auth.logAction(
                                        'tutup_shift',
                                        'Tutup shift kasir ${closedShift.cashierName}: Fisik: ${CurrencyHelper.format(count)}, Selisih: ${CurrencyHelper.format(closedShift.difference ?? 0.0)}',
                                        module: 'shift',
                                        objectId: 'SHIFT-${closedShift.id}',
                                      );

                                      _actualCashCtrl.clear();
                                      _closeNoteCtrl.clear();

                                      if (!mounted) return;
                                      showDialog(
                                        context: context,
                                        builder: (ctx) => AlertDialog(
                                          title: const Text('Shift Telah Ditutup'),
                                          content: Text(
                                            'Total $totalTrx transaksi tercatat.\nIngin langsung kirim ringkasan laporan shift ini ke WhatsApp Owner?',
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () {
                                                Navigator.pop(ctx);
                                              },
                                              child: const Text('Tutup'),
                                            ),
                                            ElevatedButton.icon(
                                              icon: const Icon(Icons.share_rounded),
                                              label: const Text('Kirim ke WA Owner'),
                                              onPressed: () async {
                                                Navigator.pop(ctx);
                                                await WhatsAppService.sendShiftReportToAdmin(
                                                  shift: closedShift,
                                                  ownerPhone: settings.ownerPhone,
                                                  storeName: settings.storeName,
                                                  totalTransactions: totalTrx,
                                                  totalGrossProfit: totalGrossProfit,
                                                );
                                              },
                                            ),
                                          ],
                                        ),
                                      );
                                    } catch (e) {
                                      if (mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text(e.toString().replaceFirst('Bad state: ', '').replaceFirst('ArgumentError: ', '')),
                                            backgroundColor: AppTheme.accentRed,
                                          ),
                                        );
                                      }
                                    }
                                  },
                            child: const Text('TUTUP SHIFT KASIR SEKARANG'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  Container(
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
                              try {
                                await cashFlow.startShift(
                                  cashierId: user?.id ?? 1,
                                  cashierName: user?.name ?? 'Kasir',
                                  startingCash: startCash,
                                );

                                await auth.logAction(
                                  'buka_shift',
                                  'Buka shift kasir ${user?.name} dengan modal: ${CurrencyHelper.format(startCash)}',
                                  module: 'shift',
                                );
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
                            },
                            child: const Text('BUKA SHIFT SEKARANG', style: TextStyle(fontSize: 16)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 24),
                const Text(
                  'Riwayat Shift Tertutup',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                ),
                const SizedBox(height: 8),
                if (closedHistory.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: AppTheme.cardDecoration(),
                    child: const Text('Belum ada riwayat shift yang ditutup.', textAlign: TextAlign.center, style: TextStyle(color: AppTheme.textMuted)),
                  )
                else
                  ...closedHistory.map((s) {
                    final diff = s.difference ?? 0.0;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    'Shift #${s.id} • ${s.cashierName}',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade200,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text('TERTUTUP (TERKUNCI)', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${DateHelper.formatFull(s.startTime)} → ${s.endTime != null ? DateHelper.formatFull(s.endTime!) : "-"}',
                              style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 14,
                              runSpacing: 4,
                              children: [
                                Text('Omzet Total: ${CurrencyHelper.format(s.totalAllSales)}', style: const TextStyle(fontSize: 11.5)),
                                Text('Kas Sistem: ${CurrencyHelper.format(s.expectedCash)}', style: const TextStyle(fontSize: 11.5)),
                                Text('Kas Fisik: ${CurrencyHelper.format(s.actualCash ?? 0)}', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
                                Text(
                                  'Selisih: ${diff >= 0 ? "+" : ""}${CurrencyHelper.format(diff)}',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.bold,
                                    color: diff.abs() <= 0.01 ? AppTheme.primaryGreen : AppTheme.accentRed,
                                  ),
                                ),
                              ],
                            ),
                            if (s.note.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text('Catatan: ${s.note}', style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic)),
                            ],
                            if (isOwnerOrAdmin)
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton.icon(
                                  onPressed: () => _showAdminCorrectDialog(s),
                                  icon: const Icon(Icons.edit_note_rounded, size: 17, color: AppTheme.accentOrange),
                                  label: const Text('Koreksi Audit Owner/Admin', style: TextStyle(fontSize: 11.5, color: AppTheme.accentOrange)),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  }),
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
      child: AppBreakpoints.spaceBetweenRow(
        Text(
          label,
          style: TextStyle(
            fontSize: isBold ? 13 : 12,
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        Text(
          value,
          textAlign: TextAlign.right,
          style: TextStyle(
            fontSize: isBold ? 14 : 12,
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            color: highlightColor ?? AppTheme.textDark,
          ),
        ),
      ),
    );
  }
}
