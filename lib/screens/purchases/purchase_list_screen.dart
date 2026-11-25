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

class _PurchaseListScreenState extends State<PurchaseListScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<PurchaseProvider>(context, listen: false).loadPurchases();
    });
  }

  void _openCreatePurchase() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PurchaseFormScreen()),
    );
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

    return Scaffold(
      appBar: AppBar(title: const Text('Pembelian & Stok Masuk')),
      body: prov.isLoading
          ? const Center(child: CircularProgressIndicator())
          : prov.purchases.isEmpty
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
                        leading: const CircleAvatar(
                          backgroundColor: AppTheme.primaryGreenSoft,
                          child: Icon(Icons.local_mall_rounded, color: AppTheme.primaryGreen),
                        ),
                        title: Text(
                          '${p.purchaseNumber} • ${p.supplierName}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                        ),
                        subtitle: Text(
                          '${DateHelper.formatFull(p.date)} • ${p.items.length} Produk • ${p.paymentMethod.toUpperCase()}',
                          style: const TextStyle(fontSize: 11.5),
                        ),
                        trailing: Text(
                          CurrencyHelper.format(p.totalAmount),
                          style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryGreen),
                        ),
                      ),
                    );
                  },
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
  String _paymentMethod = 'kas_laci';
  bool _updateCost = true;
  bool _saving = false;

  final List<PurchaseItemModel> _items = [];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _noCtrl.text = 'PO-${now.year}${now.month.toString().padLeft(2, '0')}-${Random().nextInt(9000) + 1000}';
  }

  @override
  void dispose() {
    _noCtrl.dispose();
    _supplierCtrl.dispose();
    _phoneCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  void _addProductPicker() {
    final products = Provider.of<ProductProvider>(context, listen: false).allProducts.where((p) => !p.isService).toList();
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

  Future<void> _save() async {
    if (_supplierCtrl.text.trim().isEmpty || _items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Isi nama supplier dan pilih minimal 1 produk.')),
      );
      return;
    }

    setState(() => _saving = true);
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final cashFlow = Provider.of<CashFlowProvider>(context, listen: false);
    final purchaseProv = Provider.of<PurchaseProvider>(context, listen: false);
    final prodProv = Provider.of<ProductProvider>(context, listen: false);

    final purchase = PurchaseModel(
      purchaseNumber: _noCtrl.text.trim(),
      supplierName: _supplierCtrl.text.trim(),
      supplierPhone: _phoneCtrl.text.trim(),
      totalAmount: _totalAmount,
      paymentMethod: _paymentMethod,
      note: _noteCtrl.text.trim(),
      createdBy: auth.currentUser?.name ?? 'Admin',
      items: _items,
    );

    await purchaseProv.recordPurchase(
      purchase,
      shiftId: cashFlow.currentShift?.id,
      updateProductCost: _updateCost,
    );
    await prodProv.loadProducts();
    await cashFlow.checkOpenShift();
    await auth.logAction(
      'pembelian_stok',
      'Pembelian #${purchase.purchaseNumber} dari ${purchase.supplierName} senilai ${CurrencyHelper.format(purchase.totalAmount)}',
    );

    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Stok barang berhasil ditambahkan dari pembelian!')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Catat Pembelian / Restock')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: AppTheme.cardDecoration(),
                  child: Column(
                    children: [
                      TextField(
                        controller: _noCtrl,
                        decoration: const InputDecoration(labelText: 'No. Pembelian'),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _supplierCtrl,
                              decoration: const InputDecoration(labelText: 'Nama Supplier / Toko Grosir *'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _phoneCtrl,
                              keyboardType: TextInputType.phone,
                              decoration: const InputDecoration(labelText: 'Telp Supplier'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        value: _paymentMethod,
                        decoration: const InputDecoration(labelText: 'Sumber Pembayaran'),
                        items: const [
                          DropdownMenuItem(value: 'kas_laci', child: Text('Kas Laci (Otomatis Catat Pengeluaran)')),
                          DropdownMenuItem(value: 'transfer', child: Text('Transfer Bank / Modal Owner')),
                          DropdownMenuItem(value: 'hutang', child: Text('Tempo / Hutang Supplier')),
                        ],
                        onChanged: (v) => setState(() => _paymentMethod = v ?? 'kas_laci'),
                      ),
                      SwitchListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Perbarui HPP (Harga Modal) Produk Sesuai Pembelian Ini'),
                        value: _updateCost,
                        onChanged: (v) => setState(() => _updateCost = v),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Barang yang Dibeli:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    ElevatedButton.icon(
                      onPressed: _addProductPicker,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Pilih Produk'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                if (_items.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: Text('Belum ada produk dipilih untuk restock.')),
                    ),
                  )
                else
                  ..._items.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final item = entry.value;
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
                                Text(
                                  CurrencyHelper.format(item.subtotal),
                                  style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryGreen),
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
