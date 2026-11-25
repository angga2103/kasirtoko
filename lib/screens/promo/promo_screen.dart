import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/product.dart';
import '../../models/promo.dart';
import '../../database/db_helper.dart';
import '../../providers/product_provider.dart';
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
    final list = await DatabaseHelper.instance.getActivePromos(includeInactive: true);
    if (!mounted) return;
    setState(() {
      _promos = list;
      _isLoading = false;
    });
  }

  void _showAddPromoDialog() {
    final productProv = Provider.of<ProductProvider>(context, listen: false);
    final products = productProv.allProducts.where((p) => !p.isService).toList();
    final nameCtrl = TextEditingController();
    String promoType = 'diskon_persen';
    ProductModel? targetProduct;
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
                      const SizedBox(height: 10),
                      DropdownButtonFormField<ProductModel?>(
                        value: targetProduct,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Produk Target (Opsional)',
                          hintText: 'Semua produk / Pilih spesifik',
                        ),
                        items: [
                          const DropdownMenuItem<ProductModel?>(
                            value: null,
                            child: Text('Berlaku Otomatis / Item Termurah'),
                          ),
                          ...products.map((p) => DropdownMenuItem<ProductModel?>(
                                value: p,
                                child: Text(p.name, overflow: TextOverflow.ellipsis),
                              )),
                        ],
                        onChanged: (val) => setDialogState(() => targetProduct = val),
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

                    // Date range picker
                    InkWell(
                      onTap: () async {
                        final range = await showDateRangePicker(
                          context: context,
                          firstDate: DateTime(2024),
                          lastDate: DateTime(2035),
                          initialDateRange: DateTimeRange(start: startDate, end: endDate),
                        );
                        if (range != null) {
                          setDialogState(() {
                            startDate = range.start;
                            endDate = range.end;
                          });
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Berlaku: ${DateHelper.formatShort(startDate)} - ${DateHelper.formatShort(endDate)}',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                            ),
                            const Icon(Icons.calendar_today_rounded, size: 15, color: AppTheme.primaryGreen),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
                ElevatedButton(
                  onPressed: () async {
                    if (nameCtrl.text.trim().isEmpty) return;

                    final promo = PromoModel(
                      name: nameCtrl.text.trim(),
                      promoType: promoType,
                      minPurchase: double.tryParse(minPurchaseCtrl.text) ?? 0.0,
                      discountValue: double.tryParse(discountValCtrl.text) ?? 0.0,
                      buyQty: int.tryParse(buyQtyCtrl.text),
                      getQty: int.tryParse(getQtyCtrl.text),
                      targetProductId: targetProduct?.id,
                      targetProductName: targetProduct?.name,
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
    ).whenComplete(() {
      Future.delayed(const Duration(milliseconds: 300), () {
        nameCtrl.dispose();
        minPurchaseCtrl.dispose();
        discountValCtrl.dispose();
        buyQtyCtrl.dispose();
        getQtyCtrl.dispose();
      });
    });
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
                      final targetLabel = (p.targetProductName?.isNotEmpty == true)
                          ? ' (${p.targetProductName})'
                          : '';
                      desc = 'Beli ${p.buyQty} Gratis ${p.getQty}$targetLabel';
                    }

                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: p.isRunning ? Colors.pinkAccent : Colors.grey.shade400,
                          child: const Icon(Icons.discount_rounded, color: Colors.white),
                        ),
                        title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(
                          '$desc\nPeriode: ${DateHelper.formatShort(p.startDate)} s/d ${DateHelper.formatShort(p.endDate)}',
                          style: const TextStyle(fontSize: 11),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Switch(
                              value: p.isActive,
                              onChanged: p.id == null
                                  ? null
                                  : (val) async {
                                      await DatabaseHelper.instance.togglePromoActive(p.id!, val);
                                      await _loadPromos();
                                    },
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline_rounded, color: AppTheme.accentRed, size: 20),
                              tooltip: 'Hapus Promo',
                              onPressed: p.id == null
                                  ? null
                                  : () async {
                                      await DatabaseHelper.instance.deletePromo(p.id!);
                                      await _loadPromos();
                                    },
                            ),
                          ],
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
