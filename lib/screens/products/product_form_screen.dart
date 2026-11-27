import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../database/db_helper.dart';
import '../../models/product.dart';
import '../../models/product_batch.dart';
import '../../models/product_unit.dart';
import '../../models/tiered_price.dart';
import '../../models/user.dart';
import '../../providers/auth_provider.dart';
import '../../providers/product_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/image_media_service.dart';
import '../../utils/app_theme.dart';
import '../../utils/currency_format.dart';
import '../../utils/date_format.dart';
import '../../widgets/image_picker_cropper.dart';
import '../scanner/barcode_scanner_screen.dart';

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
  late TextEditingController _brandCtrl;
  late TextEditingController _modelCtrl;
  late TextEditingController _imeiCtrl;
  late TextEditingController _warrantyCtrl;
  late TextEditingController _descCtrl;

  bool _isService = false;
  bool _trackStock = true;
  String _conditionType = 'baru';
  String? _imagePath;
  BarcodeConflictResult? _barcodeConflict;

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
    _brandCtrl = TextEditingController(text: p?.brand ?? '');
    _modelCtrl = TextEditingController(text: p?.model ?? '');
    _imeiCtrl = TextEditingController(text: p?.imeiOrSn ?? '');
    _warrantyCtrl = TextEditingController(text: p?.warrantyInfo ?? '');
    _descCtrl = TextEditingController(text: p?.description ?? '');

    _isService = p?.isService ?? false;
    _trackStock = p?.trackStock ?? !_isService;
    _conditionType = p?.conditionType ?? 'baru';
    _imagePath = p?.imagePath;
    _units = p != null ? List.from(p.units) : [];
    _tieredPrices = p != null ? List.from(p.tieredPrices) : [];
    _batches = p != null ? List.from(p.batches) : [];
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _nameCtrl.dispose();
    _categoryCtrl.dispose();
    _barcodeCtrl.dispose();
    _baseUnitCtrl.dispose();
    _costPriceCtrl.dispose();
    _sellingPriceCtrl.dispose();
    _stockCtrl.dispose();
    _minStockCtrl.dispose();
    _brandCtrl.dispose();
    _modelCtrl.dispose();
    _imeiCtrl.dispose();
    _warrantyCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _validateBarcodeDuplicate(String code) async {
    final trimmed = code.trim();
    if (trimmed.isEmpty) {
      if (mounted) setState(() => _barcodeConflict = null);
      return;
    }
    final productProv = Provider.of<ProductProvider>(context, listen: false);
    final conflict = await productProv.checkBarcodeConflict(
      trimmed,
      excludeProductId: widget.productToEdit?.id,
    );
    if (!mounted) return;
    setState(() => _barcodeConflict = conflict);
    if (conflict != null) {
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: AppTheme.accentRed),
              SizedBox(width: 8),
              Text('Barcode Duplikat!'),
            ],
          ),
          content: Text(
            'Barcode "$trimmed" sudah digunakan oleh produk:\n\n'
            'Nama: ${conflict.conflictingProduct.name}\n'
            'Kode: ${conflict.conflictingProduct.code}\n\n'
            'Sistem tidak akan menimpa barcode produk lain. Silakan gunakan barcode berbeda.',
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Mengerti'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _scanBarcodeIntoField() async {
    final scanned = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => const BarcodeScannerScreen(
          title: 'Scan Barcode Produk',
          helperText: 'Arahkan kamera ke barcode kemasan produk',
          continuousMode: false,
        ),
      ),
    );
    if (scanned != null && scanned.isNotEmpty && mounted) {
      setState(() {
        _barcodeCtrl.text = scanned;
      });
      await _validateBarcodeDuplicate(scanned);
    }
  }

  Future<void> _generateRandomBarcode() async {
    final rand = Random().nextInt(90000000) + 10000000;
    final code = '899$rand';
    setState(() {
      _barcodeCtrl.text = code;
    });
    await _validateBarcodeDuplicate(code);
  }

  Future<void> _pickProductPhoto() async {
    final path = await ImagePickerHelper.pickAndCropImage(
      context,
      prefix: 'prd',
      title: 'Foto Produk',
    );
    if (path != null && mounted) {
      setState(() => _imagePath = path);
    }
  }

  void _addUnitDialog() {
    final unitCtrl = TextEditingController();
    final factorCtrl = TextEditingController();
    final priceCtrl = TextEditingController();
    final unitBarcodeCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Tambah Multi Satuan'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: unitCtrl,
                  decoration: const InputDecoration(labelText: 'Nama Satuan (Dus, Pack, Lusin) *'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: factorCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Isi Konversi ke ${_baseUnitCtrl.text} *',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: priceCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Harga Jual Satuan Ini (Rp) *'),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: unitBarcodeCtrl,
                        decoration: const InputDecoration(labelText: 'Barcode Satuan (Opsional)'),
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton.filledTonal(
                      icon: const Icon(Icons.qr_code_scanner_rounded),
                      tooltip: 'Scan Barcode Satuan',
                      onPressed: () async {
                        final scanned = await Navigator.push<String>(
                          ctx,
                          MaterialPageRoute(
                            builder: (_) => const BarcodeScannerScreen(
                              title: 'Scan Barcode Satuan',
                              continuousMode: false,
                            ),
                          ),
                        );
                        if (scanned != null && scanned.isNotEmpty) {
                          unitBarcodeCtrl.text = scanned;
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
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
                        barcode: unitBarcodeCtrl.text.trim(),
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
    ).then((_) {
      unitCtrl.dispose();
      factorCtrl.dispose();
      priceCtrl.dispose();
      unitBarcodeCtrl.dispose();
    });
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
    ).then((_) {
      minQtyCtrl.dispose();
      priceCtrl.dispose();
    });
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
    ).then((_) {
      batchCtrl.dispose();
      stockCtrl.dispose();
    });
  }

  Future<void> _saveProduct() async {
    if (!_formKey.currentState!.validate()) return;

    final productProv = Provider.of<ProductProvider>(context, listen: false);
    final auth = Provider.of<AuthProvider>(context, listen: false);

    // Check duplicate barcode before saving permanently!
    final barcodeVal = _barcodeCtrl.text.trim();
    if (barcodeVal.isNotEmpty) {
      await _validateBarcodeDuplicate(barcodeVal);
      if (_barcodeConflict != null) return;
    }

    final canEditCost = auth.hasPermission(AppPermissions.viewCostPrice);
    final cost = canEditCost
        ? (double.tryParse(_costPriceCtrl.text) ?? 0.0)
        : (widget.productToEdit?.costPrice ?? 0.0);
    final sell = double.tryParse(_sellingPriceCtrl.text) ?? 0.0;
    final stock = double.tryParse(_stockCtrl.text) ?? 0.0;
    final minStock = double.tryParse(_minStockCtrl.text) ?? 5.0;

    final product = ProductModel(
      id: widget.productToEdit?.id,
      code: _codeCtrl.text.trim(),
      name: _nameCtrl.text.trim(),
      category: _categoryCtrl.text.trim(),
      barcode: barcodeVal,
      isService: _isService,
      trackStock: _isService ? false : _trackStock,
      baseUnit: _baseUnitCtrl.text.trim(),
      costPrice: cost,
      sellingPrice: sell,
      stock: stock,
      minStockAlert: minStock,
      imagePath: _imagePath,
      brand: _brandCtrl.text.trim(),
      model: _modelCtrl.text.trim(),
      conditionType: _conditionType,
      imeiOrSn: _imeiCtrl.text.trim(),
      warrantyInfo: _warrantyCtrl.text.trim(),
      description: _descCtrl.text.trim(),
      units: _units,
      tieredPrices: _tieredPrices,
      batches: _batches,
    );

    try {
      await productProv.saveProduct(product);
      await auth.logAction(
        widget.productToEdit == null ? 'produk_tambah' : 'produk_ubah',
        '${widget.productToEdit == null ? "Menambah" : "Mengubah"} produk ${product.name} (${product.code})',
      );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Produk "${product.name}" berhasil disimpan.')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menyimpan produk (kode/barcode mungkin sudah dipakai): $e'), backgroundColor: AppTheme.accentRed),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final settings = Provider.of<SettingsProvider>(context);
    final canSeeCost = auth.hasPermission(AppPermissions.viewCostPrice);
    final isEdit = widget.productToEdit != null;
    final imgFile = (_imagePath != null && _imagePath!.isNotEmpty) ? File(_imagePath!) : null;
    final hasImage = imgFile != null && imgFile.existsSync();

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
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Photo + Service Toggle
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GestureDetector(
                        onTap: _pickProductPhoto,
                        child: Container(
                          width: 90,
                          height: 90,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppTheme.borderLight),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: hasImage
                              ? Image.file(imgFile, fit: BoxFit.cover)
                              : const Padding(
                                  padding: EdgeInsets.all(6),
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.add_a_photo_rounded, color: AppTheme.primaryGreen, size: 28),
                                        SizedBox(height: 4),
                                        Text('Foto Produk', style: TextStyle(fontSize: 10, color: AppTheme.textMuted)),
                                      ],
                                    ),
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: _isService ? Colors.purple.shade50 : Colors.teal.shade50,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: _isService ? Colors.purple : AppTheme.primaryGreen),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _isService ? 'PRODUK JASA' : 'BARANG FISIK',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12.5,
                                            color: _isService ? Colors.purple.shade800 : AppTheme.primaryGreen,
                                          ),
                                        ),
                                        Text(
                                          _isService ? 'Tanpa potong stok' : 'Stok terkelola otomatis',
                                          style: const TextStyle(fontSize: 10, color: AppTheme.textMuted),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Switch(
                                    value: _isService,
                                    activeColor: Colors.purple,
                                    onChanged: (val) => setState(() {
                                      _isService = val;
                                      if (val) _trackStock = false;
                                      else if (widget.productToEdit == null) _trackStock = true;
                                    }),
                                  ),
                                ],
                              ),
                            ),
                            if (hasImage)
                              TextButton.icon(
                                onPressed: () async {
                                  await ImageMediaService.deleteLocalMedia(_imagePath);
                                  if (mounted) setState(() => _imagePath = null);
                                },
                                icon: const Icon(Icons.delete_outline, size: 15, color: AppTheme.accentRed),
                                label: const Text('Hapus Foto', style: TextStyle(fontSize: 11, color: AppTheme.accentRed)),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Basic Info
                  TextFormField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(labelText: 'Nama Produk / Jasa *'),
                    validator: (val) => val == null || val.trim().isEmpty ? 'Nama produk wajib diisi' : null,
                  ),
                  const SizedBox(height: 10),

                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _codeCtrl,
                          decoration: const InputDecoration(labelText: 'Kode SKU *'),
                          validator: (val) => val == null || val.trim().isEmpty ? 'Kode wajib diisi' : null,
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
                  const SizedBox(height: 12),

                  // Barcode Input + Mandatory SCAN Button + Random Generator
                  const Text('Nomor Barcode:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _barcodeCtrl,
                          decoration: InputDecoration(
                            hintText: 'Scan atau masukkan barcode...',
                            prefixIcon: const Icon(Icons.qr_code_rounded, size: 20),
                            errorText: _barcodeConflict != null
                                ? 'Sudah dipakai: ${_barcodeConflict!.conflictingProduct.name}'
                                : null,
                          ),
                          onChanged: (_) {
                            if (_barcodeConflict != null) {
                              setState(() => _barcodeConflict = null);
                            }
                          },
                          onEditingComplete: () => _validateBarcodeDuplicate(_barcodeCtrl.text),
                        ),
                      ),
                      const SizedBox(width: 6),
                      ElevatedButton.icon(
                        onPressed: _scanBarcodeIntoField,
                        icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                        label: const Text('SCAN'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                        ),
                      ),
                      const SizedBox(width: 6),
                      OutlinedButton(
                        onPressed: _generateRandomBarcode,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
                        ),
                        child: const Icon(Icons.auto_fix_high_rounded, size: 18),
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
                          decoration: const InputDecoration(labelText: 'Satuan Dasar (Pcs, Unit, Kg)'),
                        ),
                      ),
                      if (canSeeCost) ...[
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextFormField(
                            controller: _costPriceCtrl,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'Harga Modal (HPP)',
                              prefixText: settings.currencySymbol,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 10),

                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _sellingPriceCtrl,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'Harga Jual *',
                            prefixText: settings.currencySymbol,
                          ),
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
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: const Text('Kelola & Validasi Stok Produk', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        _trackStock
                            ? 'Stok berkurang saat terjual dan diblokir jika habis'
                            : 'Non-stok (stok tidak dibatasi & tidak dipotong saat kasir)',
                        style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                      ),
                      value: _trackStock,
                      onChanged: (val) => setState(() => _trackStock = val),
                    ),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _minStockCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Peringatan Stok Minimum (Low Stock Alert)',
                        hintText: '5',
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),

                  // Universal Device / Elektronik / HP Baru & Bekas Info
                  ExpansionTile(
                    initiallyExpanded: settings.businessType.showImeiDeviceFields,
                    tilePadding: EdgeInsets.zero,
                    title: const Text(
                      'Info Tambahan (Merek, Kondisi Baru/Bekas, IMEI/SN, Garansi)',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _brandCtrl,
                              decoration: const InputDecoration(labelText: 'Merek / Brand'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _modelCtrl,
                              decoration: const InputDecoration(labelText: 'Tipe / Model'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      AppBreakpoints.buildResponsivePair(
                        minPairWidth: 360,
                        spacing: 8,
                        first: DropdownButtonFormField<String>(
                          value: _conditionType,
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: 'Kondisi Produk'),
                          items: const [
                            DropdownMenuItem(value: 'baru', child: Text('Baru (New / BNIB)', maxLines: 1, overflow: TextOverflow.ellipsis)),
                            DropdownMenuItem(value: 'bekas', child: Text('Bekas / Second', maxLines: 1, overflow: TextOverflow.ellipsis)),
                          ],
                          onChanged: (v) => setState(() => _conditionType = v ?? 'baru'),
                        ),
                        second: TextField(
                          controller: _imeiCtrl,
                          decoration: const InputDecoration(labelText: 'IMEI / Serial Number'),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _warrantyCtrl,
                        decoration: const InputDecoration(labelText: 'Keterangan Garansi (Misal: Resmi 1 Tahun / 7 Hari)'),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),

                  const Divider(height: 20),

                  // Multi Satuan
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Expanded(
                        child: Text(
                          'Multi Satuan (Dus, Pack, Box):',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: TextButton.icon(
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Tambah Satuan', overflow: TextOverflow.ellipsis),
                          onPressed: _addUnitDialog,
                        ),
                      ),
                    ],
                  ),
                  if (_units.isEmpty)
                    const Text('Hanya satuan dasar.', style: TextStyle(fontSize: 11, color: AppTheme.textMuted))
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: _units.map((u) {
                        return Chip(
                          label: Text(
                            '${u.unitName} (${u.conversionFactor.toInt()} ${_baseUnitCtrl.text}) • ${CurrencyHelper.format(u.sellingPrice)}${u.barcode.isNotEmpty ? " [${u.barcode}]" : ""}',
                          ),
                          onDeleted: () => setState(() => _units.remove(u)),
                        );
                      }).toList(),
                    ),
                  const Divider(height: 24),

                  // Tiered Pricing
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Expanded(
                        child: Text(
                          'Harga Bertingkat (Grosir):',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: TextButton.icon(
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Tambah Tingkatan', overflow: TextOverflow.ellipsis),
                          onPressed: _addTieredPriceDialog,
                        ),
                      ),
                    ],
                  ),
                  if (_tieredPrices.isEmpty)
                    const Text('Belum ada harga bertingkat.', style: TextStyle(fontSize: 11, color: AppTheme.textMuted))
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

                  if (!_isService) ...[
                    const Divider(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Expanded(
                          child: Text(
                            'Batch & Kadaluarsa:',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: TextButton.icon(
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Tambah Batch', overflow: TextOverflow.ellipsis),
                            onPressed: _addBatchDialog,
                          ),
                        ),
                      ],
                    ),
                    if (_batches.isEmpty)
                      const Text('Belum ada catatan batch.', style: TextStyle(fontSize: 11, color: AppTheme.textMuted))
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: _batches.map((b) {
                          return Chip(
                            avatar: Icon(Icons.event_busy, size: 16, color: b.isExpired ? Colors.red : Colors.orange),
                            label: Text('${b.batchNumber} • Exp: ${DateHelper.formatShort(b.expiryDate)}'),
                            onDeleted: () => setState(() => _batches.remove(b)),
                          );
                        }).toList(),
                      ),
                  ],

                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _saveProduct,
                      icon: const Icon(Icons.save_rounded),
                      label: const Text('SIMPAN PRODUK', style: TextStyle(fontSize: 15)),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
