import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/product_provider.dart';
import '../../providers/auth_provider.dart';
import '../../models/product.dart';
import '../../models/stock_opname.dart';
import '../../database/db_helper.dart';
import '../../utils/app_theme.dart';
import '../../utils/date_format.dart';

class StockOpnameScreen extends StatefulWidget {
  const StockOpnameScreen({super.key});

  @override
  State<StockOpnameScreen> createState() => _StockOpnameScreenState();
}

class _StockOpnameScreenState extends State<StockOpnameScreen> {
  ProductModel? _selectedProduct;
  final TextEditingController _physicalStockCtrl = TextEditingController();
  final TextEditingController _noteCtrl = TextEditingController();
  List<StockOpnameModel> _opnameHistory = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _physicalStockCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final list = await DatabaseHelper.instance.getStockOpnames();
    setState(() {
      _opnameHistory = list;
      _isLoading = false;
    });
  }

  void _onProductSelected(ProductModel? prod) {
    if (prod != null) {
      setState(() {
        _selectedProduct = prod;
        _physicalStockCtrl.text = prod.stock.toInt().toString();
      });
    }
  }

  Future<void> _submitOpname() async {
    if (_selectedProduct == null) return;
    final physical = double.tryParse(_physicalStockCtrl.text) ?? 0.0;
    final system = _selectedProduct!.stock;
    final diff = physical - system;

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final productProv = Provider.of<ProductProvider>(context, listen: false);

    final opname = StockOpnameModel(
      date: DateTime.now(),
      productId: _selectedProduct!.id!,
      productCode: _selectedProduct!.code,
      productName: _selectedProduct!.name,
      systemStock: system,
      physicalStock: physical,
      difference: diff,
      note: _noteCtrl.text,
      auditedBy: auth.currentUser?.name ?? 'Petugas Gudang',
    );

    await DatabaseHelper.instance.insertStockOpname(opname);

    await auth.logAction(
      'stok_opname',
      'Stok opname ${_selectedProduct!.name}: Sistem ${system.toInt()} -> Fisik ${physical.toInt()} (Selisih: ${diff.toInt()})',
    );

    await productProv.loadProducts();
    await _loadHistory();

    setState(() {
      _selectedProduct = null;
      _physicalStockCtrl.clear();
      _noteCtrl.clear();
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Penyesuaian stok opname berhasil disimpan!')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final productProv = Provider.of<ProductProvider>(context);

    final physicalVal = double.tryParse(_physicalStockCtrl.text) ?? 0.0;
    final systemVal = _selectedProduct?.stock ?? 0.0;
    final diffVal = physicalVal - systemVal;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Stok Opname (Audit Fisik)'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Opname Input Card
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
                  const Text('Formulir Perhitungan Fisik:',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),

                  // Select Product
                  DropdownButtonFormField<ProductModel>(
                    isExpanded: true,
                    value: _selectedProduct,
                    decoration: const InputDecoration(labelText: 'Pilih Produk untuk Di-audit *'),
                    items: productProv.allProducts.where((p) => !p.isService).map((p) {
                      return DropdownMenuItem(
                        value: p,
                        child: Text('${p.name} (Stok Sistem: ${p.stock.toInt()} ${p.baseUnit})'),
                      );
                    }).toList(),
                    onChanged: _onProductSelected,
                  ),
                  const SizedBox(height: 12),

                  if (_selectedProduct != null) ...[
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Stok di Sistem:', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                                Text(
                                  '${systemVal.toInt()} ${_selectedProduct!.baseUnit}',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _physicalStockCtrl,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            decoration: InputDecoration(
                              labelText: 'Hasil Hitung Fisik *',
                              suffixText: _selectedProduct!.baseUnit,
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Discrepancy indicator
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: diffVal == 0
                            ? Colors.green.shade50
                            : (diffVal > 0 ? Colors.blue.shade50 : Colors.red.shade50),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: diffVal == 0
                              ? Colors.green
                              : (diffVal > 0 ? Colors.blue : Colors.red),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Selisih Barang:', style: TextStyle(fontWeight: FontWeight.bold)),
                          Text(
                            diffVal == 0
                                ? 'COCOK (0)'
                                : (diffVal > 0 ? 'LEBIH (+${diffVal.toInt()})' : 'KURANG (${diffVal.toInt()})'),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: diffVal == 0
                                  ? Colors.green.shade800
                                  : (diffVal > 0 ? Colors.blue.shade800 : Colors.red.shade800),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    TextField(
                      controller: _noteCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Alasan Selisih (Opsional)',
                        hintText: 'Misal: Rusak basah, terselip di rak bawah, hilang...',
                      ),
                    ),
                    const SizedBox(height: 16),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _submitOpname,
                        child: const Text('SESUAIKAN STOK SEKARANG'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),

            // History of Opname
            const Text('Riwayat Stok Opname:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),

            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else if (_opnameHistory.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Belum ada riwayat stok opname.'),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _opnameHistory.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (context, index) {
                  final o = _opnameHistory[index];
                  final isMatch = o.difference == 0;

                  return Card(
                    child: ListTile(
                      title: Text(o.productName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      subtitle: Text(
                        '${DateHelper.formatReceipt(o.date)} • Sistem: ${o.systemStock.toInt()} -> Fisik: ${o.physicalStock.toInt()}\nOleh: ${o.auditedBy} • Ket: ${o.note.isNotEmpty ? o.note : "-"}',
                        style: const TextStyle(fontSize: 11),
                      ),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: isMatch ? Colors.green.shade100 : Colors.red.shade100,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          isMatch ? 'PAS' : '${o.difference > 0 ? "+" : ""}${o.difference.toInt()}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isMatch ? Colors.green.shade800 : Colors.red.shade800,
                          ),
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
