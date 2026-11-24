import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/product.dart';
import '../../models/product_unit.dart';
import '../../models/tiered_price.dart';
import '../../models/product_batch.dart';
import '../../providers/product_provider.dart';
import '../../utils/app_theme.dart';
import '../../utils/currency_format.dart';
import '../../utils/date_format.dart';

class ProductFormScreen extends StatefulWidget {
  final ProductModel? productToEdit;

  const ProductFormScreen({super.key, this.productToEdit});

  @override
  State<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends State<ProductFormScreen> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _codeCtrl;
  late TextEditingController _nameCtrl;
  late TextEditingController _categoryCtrl;
  late TextEditingController _barcodeCtrl;
  late TextEditingController _baseUnitCtrl;
  late TextEditingController _costPriceCtrl;
  late TextEditingController _sellingPriceCtrl;
  late TextEditingController _stockCtrl;
  late TextEditingController _minStockCtrl;

  bool _isService = false;
  List<ProductUnitModel> _units = [];
  List<TieredPriceModel> _tieredPrices = [];
  List<ProductBatchModel> _batches = [];

  @override
  void initState() {
    super.initState();
    final p = widget.productToEdit;

    _codeCtrl = TextEditingController(text: p?.code ?? 'PRD-${Random().nextInt(9000) + 1000}');
    _nameCtrl = TextEditingController(text: p?.name ?? '');
    _categoryCtrl = TextEditingController(text: p?.category ?? 'Umum');
    _barcodeCtrl = TextEditingController(text: p?.barcode ?? '');
    _baseUnitCtrl = TextEditingController(text: p?.baseUnit ?? 'Pcs');
    _costPriceCtrl = TextEditingController(text: p != null ? p.costPrice.toInt().toString() : '0');
    _sellingPriceCtrl = TextEditingController(text: p != null ? p.sellingPrice.toInt().toString() : '0');
    _stockCtrl = TextEditingController(text: p != null ? p.stock.toInt().toString() : '0');
    _minStockCtrl = TextEditingController(text: p != null ? p.minStockAlert.toInt().toString() : '5');

    _isService = p?.isService ?? false;
    _units = p != null ? List.from(p.units) : [];
    _tieredPrices = p != null ? List.from(p.tieredPrices) : [];
    _batches = p != null ? List.from(p.batches) : [];
  }

  void _generateRandomBarcode() {
    final rand = Random().nextInt(90000000) + 10000000;
    setState(() {
      _barcodeCtrl.text = '899$rand';
    });
  }

  void _addUnitDialog() {
    final unitCtrl = TextEditingController();
    final factorCtrl = TextEditingController();
    final priceCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Tambah Multi Satuan'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: unitCtrl,
                decoration: const InputDecoration(labelText: 'Nama Satuan (misal: Dus, Pack, Lusin)'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: factorCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Konversi ke ${_baseUnitCtrl.text} (misal: 1 Dus = 24 ${_baseUnitCtrl.text})',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: priceCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Harga Jual Khusus Satuan Ini (Rp)',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
            ElevatedButton(
              onPressed: () {
                final factor = double.tryParse(factorCtrl.text) ?? 1.0;
                final price = double.tryParse(priceCtrl.text) ?? 0.0;
                if (unitCtrl.text.isNotEmpty && factor > 1) {
                  setState(() {
                    _units.add(
                      ProductUnitModel(
                        productId: widget.productToEdit?.id ?? 0,
                        unitName: unitCtrl.text.trim(),
                        conversionFactor: factor,
                        sellingPrice: price,
                      ),
                    );
                  });
                  Navigator.pop(ctx);
                }
              },
              child: const Text('Simpan'),
            ),
          ],
        );
      },
    );
  }

  void _addTieredPriceDialog() {
    final minQtyCtrl = TextEditingController();
    final priceCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Tambah Harga Bertingkat (Grosir)'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: minQtyCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: 'Beli Minimal Berapa (${_baseUnitCtrl.text})'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: priceCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Harga per Satuan (Rp)'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
            ElevatedButton(
              onPressed: () {
                final minQty = double.tryParse(minQtyCtrl.text) ?? 0.0;
                final price = double.tryParse(priceCtrl.text) ?? 0.0;
                if (minQty > 1 && price > 0) {
                  setState(() {
                    _tieredPrices.add(
                      TieredPriceModel(
                        productId: widget.productToEdit?.id ?? 0,
                        minQty: minQty,
                        price: price,
                      ),
                    );
                  });
                  Navigator.pop(ctx);
                }
              },
              child: const Text('Simpan'),
            ),
          ],
        );
      },
    );
  }

  void _addBatchDialog() {
    final batchCtrl = TextEditingController(text: 'BATCH-${DateTime.now().year}');
    final stockCtrl = TextEditingController(text: '10');
    DateTime selectedDate = DateTime.now().add(const Duration(days: 90));

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Tambah Batch & Kadaluarsa'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: batchCtrl,
                    decoration: const InputDecoration(labelText: 'Nomor Batch / Lot'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: stockCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Stok pada Batch Ini'),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Tgl Expired: ${DateHelper.formatShort(selectedDate)}'),
                      TextButton(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: selectedDate,
                            firstDate: DateTime.now().subtract(const Duration(days: 365)),
                            lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
                          );
                          if (picked != null) {
                            setDialogState(() => selectedDate = picked);
                          }
                        },
                        child: const Text('Ubah Tgl'),
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
                ElevatedButton(
                  onPressed: () {
                    final qty = double.tryParse(stockCtrl.text) ?? 0.0;
                    if (batchCtrl.text.isNotEmpty) {
                      setState(() {
                        _batches.add(
                          ProductBatchModel(
                            productId: widget.productToEdit?.id ?? 0,
                            batchNumber: batchCtrl.text.trim(),
                            expiryDate: selectedDate,
                            stockQty: qty,
                          ),
                        );
                      });
                      Navigator.pop(ctx);
                    }
                  },
                  child: const Text('Simpan'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _saveProduct() async {
    if (!_formKey.currentState!.validate()) return;

    final cost = double.tryParse(_costPriceCtrl.text) ?? 0.0;
    final sell = double.tryParse(_sellingPriceCtrl.text) ?? 0.0;
    final stock = double.tryParse(_stockCtrl.text) ?? 0.0;
    final minStock = double.tryParse(_minStockCtrl.text) ?? 5.0;

    final product = ProductModel(
      id: widget.productToEdit?.id,
      code: _codeCtrl.text.trim(),
      name: _nameCtrl.text.trim(),
      category: _categoryCtrl.text.trim(),
      barcode: _barcodeCtrl.text.trim(),
      isService: _isService,
      baseUnit: _baseUnitCtrl.text.trim(),
      costPrice: cost,
      sellingPrice: sell,
      stock: stock,
      minStockAlert: minStock,
      units: _units,
      tieredPrices: _tieredPrices,
      batches: _batches,
    );

    final productProv = Provider.of<ProductProvider>(context, listen: false);
    await productProv.saveProduct(product);

    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Produk "${product.name}" berhasil disimpan.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.productToEdit != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? 'Ubah Produk' : 'Tambah Produk Baru'),
        actions: [
          if (isEdit)
            IconButton(
              icon: const Icon(Icons.delete_forever_rounded, color: Colors.white),
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Hapus Produk?'),
                    content: Text('Apakah Anda yakin ingin menghapus "${widget.productToEdit!.name}"?'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accentRed),
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Hapus'),
                      ),
                    ],
                  ),
                );
                if (confirm == true && mounted) {
                  await Provider.of<ProductProvider>(context, listen: false)
                      .deleteProduct(widget.productToEdit!.id!);
                  if (mounted) Navigator.pop(context);
                }
              },
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Service Toggle Card
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: _isService ? Colors.purple.shade50 : Colors.teal.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _isService ? Colors.purple : AppTheme.primaryGreen),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isService ? 'Tipe: PRODUK JASA (Tanpa Stok)' : 'Tipe: BARANG FISIK (Berstok)',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: _isService ? Colors.purple.shade800 : AppTheme.primaryGreen,
                          ),
                        ),
                        Text(
                          _isService
                              ? 'Tidak memotong inventori gudang'
                              : 'Stok akan otomatis berkurang saat transaksi',
                          style: const TextStyle(fontSize: 10, color: AppTheme.textMuted),
                        ),
                      ],
                    ),
                    Switch(
                      value: _isService,
                      activeColor: Colors.purple,
                      onChanged: (val) => setState(() => _isService = val),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Basic Info
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'Nama Produk / Jasa *'),
                validator: (val) => val == null || val.isEmpty ? 'Nama produk wajib diisi' : null,
              ),
              const SizedBox(height: 10),

              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _codeCtrl,
                      decoration: const InputDecoration(labelText: 'Kode SKU *'),
                      validator: (val) => val == null || val.isEmpty ? 'Kode wajib diisi' : null,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: _categoryCtrl,
                      decoration: const InputDecoration(labelText: 'Kategori'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Barcode with Generator Button
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _barcodeCtrl,
                      decoration: const InputDecoration(labelText: 'Barcode (1D / EAN-13)'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.auto_fix_high_rounded, size: 16),
                    label: const Text('Buat Acak'),
                    onPressed: _generateRandomBarcode,
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Pricing & Stock
              const Text('Harga & Satuan Dasar:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _baseUnitCtrl,
                      decoration: const InputDecoration(labelText: 'Satuan Dasar (Pcs, Kg, Dus)'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: _costPriceCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Harga Modal (HPP)', prefixText: 'Rp '),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _sellingPriceCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Harga Jual *', prefixText: 'Rp '),
                      validator: (val) => val == null || val.isEmpty ? 'Harga jual wajib diisi' : null,
                    ),
                  ),
                  if (!_isService) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: _stockCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Stok Awal'),
                      ),
                    ),
                  ],
                ],
              ),
              if (!_isService) ...[
                const SizedBox(height: 10),
                TextFormField(
                  controller: _minStockCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Peringatan Stok Minimum (Low Stock Alert)',
                    hintText: '5',
                  ),
                ),
              ],
              const SizedBox(height: 20),

              // Multi Satuan Section
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Multi Satuan (Dus, Pack, Renceng):',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  TextButton.icon(
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Tambah Satuan'),
                    onPressed: _addUnitDialog,
                  ),
                ],
              ),
              if (_units.isEmpty)
                const Text('Belum ada satuan tambahan (hanya satuan dasar).',
                    style: TextStyle(fontSize: 11, color: AppTheme.textMuted))
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: _units.map((u) {
                    return Chip(
                      label: Text('${u.unitName} (Isi ${u.conversionFactor.toInt()} ${_baseUnitCtrl.text}) : ${CurrencyHelper.format(u.sellingPrice)}'),
                      onDeleted: () => setState(() => _units.remove(u)),
                    );
                  }).toList(),
                ),
              const Divider(height: 24),

              // Tiered Pricing Section
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Harga Bertingkat (Grosir):',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  TextButton.icon(
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Tambah Tingkatan'),
                    onPressed: _addTieredPriceDialog,
                  ),
                ],
              ),
              if (_tieredPrices.isEmpty)
                const Text('Belum ada harga grosir/bertingkat.',
                    style: TextStyle(fontSize: 11, color: AppTheme.textMuted))
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: _tieredPrices.map((tp) {
                    return Chip(
                      label: Text('Beli >= ${tp.minQty.toInt()} ${_baseUnitCtrl.text} @ ${CurrencyHelper.format(tp.price)}'),
                      onDeleted: () => setState(() => _tieredPrices.remove(tp)),
                    );
                  }).toList(),
                ),
              const Divider(height: 24),

              // Product Batches & Expiry Dates Section
              if (!_isService) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Batch & Tanggal Kadaluarsa (Expired):',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    TextButton.icon(
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Tambah Batch'),
                      onPressed: _addBatchDialog,
                    ),
                  ],
                ),
                if (_batches.isEmpty)
                  const Text('Tidak ada batch kadaluarsa.',
                      style: TextStyle(fontSize: 11, color: AppTheme.textMuted))
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: _batches.map((b) {
                      return Chip(
                        avatar: Icon(Icons.event_busy, size: 16, color: b.isExpired ? Colors.red : Colors.orange),
                        label: Text('${b.batchNumber} - Exp: ${DateHelper.formatShort(b.expiryDate)} (${b.stockQty.toInt()} ${_baseUnitCtrl.text})'),
                        onDeleted: () => setState(() => _batches.remove(b)),
                      );
                    }).toList(),
                  ),
                const SizedBox(height: 24),
              ],

              // Save Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saveProduct,
                  child: const Text('SIMPAN PRODUK', style: TextStyle(fontSize: 16)),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
