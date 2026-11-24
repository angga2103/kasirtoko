import 'package:flutter/material.dart';
import '../../models/promo.dart';
import '../../database/db_helper.dart';
import '../../utils/app_theme.dart';
import '../../utils/currency_format.dart';
import '../../utils/date_format.dart';

class PromoScreen extends StatefulWidget {
  const PromoScreen({super.key});

  @override
  State<PromoScreen> createState() => _PromoScreenState();
}

class _PromoScreenState extends State<PromoScreen> {
  List<PromoModel> _promos = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPromos();
  }

  Future<void> _loadPromos() async {
    final list = await DatabaseHelper.instance.getActivePromos();
    setState(() {
      _promos = list;
      _isLoading = false;
    });
  }

  void _showAddPromoDialog() {
    final nameCtrl = TextEditingController();
    String promoType = 'diskon_persen';
    final minPurchaseCtrl = TextEditingController(text: '50000');
    final discountValCtrl = TextEditingController(text: '10');
    final buyQtyCtrl = TextEditingController(text: '2');
    final getQtyCtrl = TextEditingController(text: '1');
    DateTime startDate = DateTime.now();
    DateTime endDate = DateTime.now().add(const Duration(days: 14));

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Buat Promo / Diskon Baru'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Nama Promo *',
                        hintText: 'Misal: Promo Akhir Pekan',
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Promo Type
                    const Text('Jenis Promo:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    DropdownButtonFormField<String>(
                      value: promoType,
                      isExpanded: true,
                      items: const [
                        DropdownMenuItem(value: 'diskon_persen', child: Text('Diskon Persen (%)')),
                        DropdownMenuItem(value: 'potongan_nominal', child: Text('Potongan Harga (Rp)')),
                        DropdownMenuItem(value: 'beli_x_gratis_y', child: Text('Beli X Gratis Y')),
                      ],
                      onChanged: (val) {
                        if (val != null) setDialogState(() => promoType = val);
                      },
                    ),
                    const SizedBox(height: 10),

                    if (promoType == 'beli_x_gratis_y') ...[
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: buyQtyCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(labelText: 'Beli Jumlah (X)'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: getQtyCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(labelText: 'Gratis Jumlah (Y)'),
                            ),
                          ),
                        ],
                      ),
                    ] else ...[
                      TextField(
                        controller: discountValCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: promoType == 'diskon_persen' ? 'Besar Diskon (%)' : 'Potongan Nominal (Rp)',
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: minPurchaseCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Minimal Total Belanja (Rp)',
                          prefixText: 'Rp ',
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),

                    // Date range
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Berlaku: ${DateHelper.formatShort(startDate)} - ${DateHelper.formatShort(endDate)}',
                            style: const TextStyle(fontSize: 11)),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
                ElevatedButton(
                  onPressed: () async {
                    if (nameCtrl.text.isEmpty) return;

                    final promo = PromoModel(
                      name: nameCtrl.text.trim(),
                      promoType: promoType,
                      minPurchase: double.tryParse(minPurchaseCtrl.text) ?? 0.0,
                      discountValue: double.tryParse(discountValCtrl.text) ?? 0.0,
                      buyQty: int.tryParse(buyQtyCtrl.text),
                      getQty: int.tryParse(getQtyCtrl.text),
                      startDate: startDate,
                      endDate: endDate,
                    );

                    await DatabaseHelper.instance.insertPromo(promo);
                    await _loadPromos();

                    if (!mounted) return;
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Promo "${promo.name}" aktif!')),
                    );
                  },
                  child: const Text('Simpan Promo'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Diskon & Promo Toko'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _promos.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.discount_outlined, size: 54, color: AppTheme.textMuted),
                      const SizedBox(height: 12),
                      const Text('Belum ada promo atau voucher aktif.'),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.add),
                        label: const Text('Buat Promo Baru'),
                        onPressed: _showAddPromoDialog,
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: _promos.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final p = _promos[index];

                    String desc = '';
                    if (p.promoType == 'diskon_persen') {
                      desc = 'Diskon ${p.discountValue.toInt()}% (Min. Belanja ${CurrencyHelper.format(p.minPurchase)})';
                    } else if (p.promoType == 'potongan_nominal') {
                      desc = 'Potongan ${CurrencyHelper.format(p.discountValue)} (Min. Belanja ${CurrencyHelper.format(p.minPurchase)})';
                    } else {
                      desc = 'Beli ${p.buyQty} Gratis ${p.getQty}';
                    }

                    return Card(
                      child: ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: Colors.pinkAccent,
                          child: Icon(Icons.discount_rounded, color: Colors.white),
                        ),
                        title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(
                          '$desc\nPeriode: ${DateHelper.formatShort(p.startDate)} s/d ${DateHelper.formatShort(p.endDate)}',
                          style: const TextStyle(fontSize: 11),
                        ),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: p.isRunning ? Colors.green.shade100 : Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            p.isRunning ? 'AKTIF' : 'BERAKHIR',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: p.isRunning ? Colors.green.shade800 : Colors.grey,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppTheme.primaryGreen,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Buat Promo', style: TextStyle(color: Colors.white)),
        onPressed: _showAddPromoDialog,
      ),
    );
  }
}
