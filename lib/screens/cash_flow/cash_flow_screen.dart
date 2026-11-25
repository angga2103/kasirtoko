import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/cash_flow_provider.dart';
import '../../providers/auth_provider.dart';
import '../../utils/app_theme.dart';
import '../../utils/currency_format.dart';
import '../../utils/date_format.dart';

class CashFlowScreen extends StatefulWidget {
  const CashFlowScreen({super.key});

  @override
  State<CashFlowScreen> createState() => _CashFlowScreenState();
}

class _CashFlowScreenState extends State<CashFlowScreen> {
  final TextEditingController _amountCtrl = TextEditingController();
  final TextEditingController _noteCtrl = TextEditingController();
  String _type = 'out'; // 'in' or 'out'
  String _category = 'Operasional Toko';

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  final List<String> _expenseCategories = [
    'Operasional Toko',
    'Beli Kantong Plastik',
    'Iuran Kebersihan / Keamanan',
    'Listrik & Air Toko',
    'Beli Air Galon',
    'Prive / Ambil Kas Owner',
    'Lain-lain',
  ];

  final List<String> _incomeCategories = [
    'Modal Tambahan',
    'Pelunasan Kasbon',
    'Komisi / Penitipan Barang',
    'Lain-lain',
  ];

  Future<void> _submitFlow() async {
    final amount = double.tryParse(_amountCtrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0.0;
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nominal harus lebih dari Rp 0')),
      );
      return;
    }

    final cashFlow = Provider.of<CashFlowProvider>(context, listen: false);
    final auth = Provider.of<AuthProvider>(context, listen: false);

    await cashFlow.recordCashFlow(
      type: _type,
      category: _category,
      amount: amount,
      note: _noteCtrl.text,
      cashierName: auth.currentUser?.name ?? 'Kasir',
    );

    await auth.logAction(
      _type == 'out' ? 'kas_keluar' : 'kas_masuk',
      '${_type == 'out' ? "Pengeluaran" : "Pemasukan"} $_category: ${CurrencyHelper.format(amount)} (${_noteCtrl.text})',
    );

    _amountCtrl.clear();
    _noteCtrl.clear();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Catatan arus kas berhasil disimpan!'),
        backgroundColor: _type == 'in' ? AppTheme.primaryGreen : AppTheme.accentOrange,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cashFlow = Provider.of<CashFlowProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Arus Kas (Masuk & Keluar)'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Entry Form Card
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
                  const Text('Catat Kas Laci:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 12),

                  // In / Out Toggle
                  Row(
                    children: [
                      Expanded(
                        child: ChoiceChip(
                          label: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.arrow_upward_rounded, size: 16, color: Colors.red),
                              SizedBox(width: 6),
                              Text('Pengeluaran (Kas Keluar)'),
                            ],
                          ),
                          selected: _type == 'out',
                          selectedColor: Colors.red.shade100,
                          onSelected: (val) {
                            if (val) {
                              setState(() {
                                _type = 'out';
                                _category = _expenseCategories.first;
                              });
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ChoiceChip(
                          label: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.arrow_downward_rounded, size: 16, color: Colors.green),
                              SizedBox(width: 6),
                              Text('Pemasukan (Kas Masuk)'),
                            ],
                          ),
                          selected: _type == 'in',
                          selectedColor: Colors.green.shade100,
                          onSelected: (val) {
                            if (val) {
                              setState(() {
                                _type = 'in';
                                _category = _incomeCategories.first;
                              });
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Category Dropdown
                  const Text('Kategori:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: _category,
                        items: (_type == 'out' ? _expenseCategories : _incomeCategories).map((c) {
                          return DropdownMenuItem(value: c, child: Text(c, style: const TextStyle(fontSize: 13)));
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) setState(() => _category = val);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Amount
                  TextField(
                    controller: _amountCtrl,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    decoration: const InputDecoration(
                      labelText: 'Nominal Kas *',
                      prefixText: 'Rp ',
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Note
                  TextField(
                    controller: _noteCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Keterangan Tambahan (Opsional)',
                      hintText: 'Misal: Beli plastik 1 ikat...',
                    ),
                  ),
                  const SizedBox(height: 16),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _type == 'out' ? AppTheme.accentRed : AppTheme.primaryGreen,
                      ),
                      onPressed: _submitFlow,
                      child: Text(_type == 'out' ? 'CATAT PENGELUARAN' : 'CATAT PEMASUKAN'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // History List
            const Text(
              'Riwayat Kas Masuk & Keluar Shift Ini:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 8),

            if (cashFlow.cashFlows.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Belum ada catatan kas masuk / keluar pada shift ini.'),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: cashFlow.cashFlows.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (context, index) {
                  final flow = cashFlow.cashFlows[index];
                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: flow.isIn ? Colors.green.shade100 : Colors.red.shade100,
                        child: Icon(
                          flow.isIn ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                          color: flow.isIn ? Colors.green : Colors.red,
                        ),
                      ),
                      title: Text(
                        flow.category,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      subtitle: Text(
                        '${DateHelper.formatTime(flow.date)} • ${flow.note.isNotEmpty ? flow.note : "-"} • Oleh: ${flow.cashierName}',
                        style: const TextStyle(fontSize: 11),
                      ),
                      trailing: Text(
                        '${flow.isIn ? "+" : "-"}${CurrencyHelper.format(flow.amount)}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: flow.isIn ? Colors.green : Colors.red,
                        ),
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
}
