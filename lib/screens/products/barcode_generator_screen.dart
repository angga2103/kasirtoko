import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/printer_device.dart';
import '../../models/product.dart';
import '../../providers/printer_provider.dart';
import '../../providers/product_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/printer/printer_manager.dart';
import '../../services/thermal_printer_service.dart';
import '../../utils/app_theme.dart';
import '../../utils/currency_format.dart';
import '../../widgets/quantity_stepper.dart';

class BarcodeGeneratorScreen extends StatefulWidget {
  const BarcodeGeneratorScreen({super.key});

  @override
  State<BarcodeGeneratorScreen> createState() => _BarcodeGeneratorScreenState();
}

class _BarcodeGeneratorScreenState extends State<BarcodeGeneratorScreen> {
  ProductModel? _selectedProduct;
  final TextEditingController _customNameCtrl = TextEditingController(text: 'Produk Contoh');
  final TextEditingController _customBarcodeCtrl = TextEditingController(text: '8992345001');
  final TextEditingController _customSkuCtrl = TextEditingController(text: 'PRD-001');
  final TextEditingController _customPriceCtrl = TextEditingController(text: '15000');

  bool _isQrCode = false;
  bool _showStoreName = true;
  bool _showPrice = true;
  bool _showSku = true;
  int _copyCount = 5;
  String _labelPreset = '40x30'; // '40x30' | '50x30' | '58mm' | 'a4_grid'
  int? _selectedPrinterId;
  bool _printing = false;

  final List<EscPosLabelItemAdapter> _labelQueue = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final prods = Provider.of<ProductProvider>(context, listen: false).allProducts;
      final printerProv = Provider.of<PrinterProvider>(context, listen: false);
      if (prods.isNotEmpty) {
        _onProductSelected(prods.first);
      }
      if (mounted && printerProv.defaultPrinter != null) {
        setState(() => _selectedPrinterId = printerProv.defaultPrinter!.id);
      }
    });
  }

  @override
  void dispose() {
    _customNameCtrl.dispose();
    _customBarcodeCtrl.dispose();
    _customSkuCtrl.dispose();
    _customPriceCtrl.dispose();
    super.dispose();
  }

  void _onProductSelected(ProductModel? prod) {
    if (prod != null) {
      setState(() {
        _selectedProduct = prod;
        _customNameCtrl.text = prod.name;
        _customSkuCtrl.text = prod.code;
        _customBarcodeCtrl.text = prod.barcode.isNotEmpty ? prod.barcode : prod.code;
        _customPriceCtrl.text = prod.sellingPrice.toInt().toString();
      });
    }
  }

  void _addToQueue() {
    final code = _customBarcodeCtrl.text.trim();
    final name = _customNameCtrl.text.trim();
    if (code.isEmpty || name.isEmpty) return;
    final price = double.tryParse(_customPriceCtrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0.0;
    setState(() {
      _labelQueue.add(
        EscPosLabelItemAdapter(
          name: name,
          sku: _customSkuCtrl.text.trim(),
          barcodeData: code,
          price: price,
          copyCount: _copyCount,
        ),
      );
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$name ($_copyCount label) ditambahkan ke antrean cetak.')),
    );
  }

  Future<void> _printLabels(SettingsProvider settings, List<PrinterDeviceModel> printers) async {
    if (_printing) return;
    final barcodeText = _customBarcodeCtrl.text.trim().isEmpty ? '8992345001' : _customBarcodeCtrl.text.trim();
    final priceVal = double.tryParse(_customPriceCtrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0.0;

    final itemsToPrint = _labelQueue.isNotEmpty
        ? _labelQueue
        : [
            EscPosLabelItemAdapter(
              name: _customNameCtrl.text.trim().isEmpty ? 'Produk' : _customNameCtrl.text.trim(),
              sku: _customSkuCtrl.text.trim(),
              barcodeData: barcodeText,
              price: priceVal,
              copyCount: _copyCount,
            ),
          ];

    final isA4 = _labelPreset == 'a4_grid';
    final w = _labelPreset == '58mm' ? 56.0 : (_labelPreset == '50x30' ? 50.0 : 40.0);
    final h = _labelPreset == '58mm' ? 35.0 : 30.0;

    final selectedPrinter = printers.cast<PrinterDeviceModel?>().firstWhere(
          (p) => p?.id == _selectedPrinterId,
          orElse: () => null,
        );

    setState(() => _printing = true);
    try {
      final res = await PrinterManager.printProductLabels(
        printer: isA4 ? null : selectedPrinter,
        items: itemsToPrint,
        storeName: settings.storeName,
        isQrCode: _isQrCode,
        showPrice: _showPrice,
        showStoreName: _showStoreName,
        showSku: _showSku,
        labelWidthMm: w,
        labelHeightMm: h,
        isA4StickerGrid: isA4,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res.message),
          backgroundColor: res.success ? AppTheme.success : AppTheme.accentOrange,
        ),
      );
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final prodProv = Provider.of<ProductProvider>(context);
    final settings = Provider.of<SettingsProvider>(context);
    final printerProv = Provider.of<PrinterProvider>(context);

    final barcodeText = _customBarcodeCtrl.text.trim().isEmpty ? '8992345001' : _customBarcodeCtrl.text.trim();
    final priceVal = double.tryParse(_customPriceCtrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0.0;
    final totalQueuedCopies = _labelQueue.fold<int>(0, (sum, e) => sum + e.copyCount);

    return Scaffold(
      appBar: AppBar(title: const Text('Cetak Label Barcode & QR')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 780),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<ProductModel>(
                  value: prodProv.allProducts.contains(_selectedProduct) ? _selectedProduct : null,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Pilih dari Produk Toko'),
                  items: prodProv.allProducts
                      .map((p) => DropdownMenuItem(
                            value: p,
                            child: Text('${p.name} (${p.code})', overflow: TextOverflow.ellipsis),
                          ))
                      .toList(),
                  onChanged: _onProductSelected,
                ),
                const SizedBox(height: 10),

                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _customNameCtrl,
                        decoration: const InputDecoration(labelText: 'Nama Produk di Stiker'),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _customSkuCtrl,
                        decoration: const InputDecoration(labelText: 'SKU'),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _customBarcodeCtrl,
                        decoration: const InputDecoration(labelText: 'Data Barcode / QR *'),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _customPriceCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Harga', prefixText: 'Rp '),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                Row(
                  children: [
                    Expanded(
                      child: ChoiceChip(
                        label: const Center(child: Text('Barcode 1D')),
                        selected: !_isQrCode,
                        selectedColor: AppTheme.primaryGreenSoft,
                        onSelected: (val) => setState(() => _isQrCode = !val),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ChoiceChip(
                        label: const Center(child: Text('QR Code 2D')),
                        selected: _isQrCode,
                        selectedColor: AppTheme.primaryGreenSoft,
                        onSelected: (val) => setState(() => _isQrCode = val),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                DropdownButtonFormField<String>(
                  value: _labelPreset,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Ukuran Kertas & Mode Layout'),
                  items: const [
                    DropdownMenuItem(value: '40x30', child: Text('40 × 30 mm (Stiker Thermal)')),
                    DropdownMenuItem(value: '50x30', child: Text('50 × 30 mm (Stiker Thermal Lebar)')),
                    DropdownMenuItem(value: '58mm', child: Text('58 × 35 mm (Roll Thermal 58mm)')),
                    DropdownMenuItem(value: 'a4_grid', child: Text('Kertas Stiker A4 Grid 3×7 (Laser / Inkjet PDF)')),
                  ],
                  onChanged: (v) => setState(() => _labelPreset = v ?? '40x30'),
                ),
                if (_labelPreset != 'a4_grid') ...[
                  const SizedBox(height: 10),
                  DropdownButtonFormField<int?>(
                    value: printerProv.printers.any((p) => p.id == _selectedPrinterId) ? _selectedPrinterId : null,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Printer Tujuan Cetak Label'),
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('Android Print Service / PDF Roll'),
                      ),
                      ...printerProv.printers.map((p) => DropdownMenuItem<int?>(
                            value: p.id,
                            child: Text('${p.name} (${p.connectionType.toUpperCase()} • ${p.paperSize})', overflow: TextOverflow.ellipsis),
                          )),
                    ],
                    onChanged: (id) => setState(() => _selectedPrinterId = id),
                  ),
                ],
                const SizedBox(height: 8),

                Wrap(
                  spacing: 8,
                  children: [
                    FilterChip(
                      label: const Text('Nama Toko', style: TextStyle(fontSize: 12)),
                      selected: _showStoreName,
                      onSelected: (v) => setState(() => _showStoreName = v),
                    ),
                    FilterChip(
                      label: const Text('SKU', style: TextStyle(fontSize: 12)),
                      selected: _showSku,
                      onSelected: (v) => setState(() => _showSku = v),
                    ),
                    FilterChip(
                      label: const Text('Harga Jual', style: TextStyle(fontSize: 12)),
                      selected: _showPrice,
                      onSelected: (v) => setState(() => _showPrice = v),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    const Text('Salinan Label Ini:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    QuantityStepper(
                      value: _copyCount.toDouble(),
                      minValue: 1,
                      maxValue: 200,
                      unitLabel: 'Pcs',
                      compact: true,
                      onChanged: (v) => setState(() => _copyCount = v.toInt()),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Responsive Label Preview
                Center(
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 260),
                    padding: const EdgeInsets.all(14),
                    decoration: AppTheme.cardDecoration(),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_showStoreName)
                          Text(
                            settings.storeName,
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                            textAlign: TextAlign.center,
                          ),
                        Text(
                          _customNameCtrl.text,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (_showSku && _customSkuCtrl.text.trim().isNotEmpty)
                          Text(
                            'SKU: ${_customSkuCtrl.text.trim()}',
                            style: const TextStyle(fontSize: 10, color: AppTheme.textMuted),
                          ),
                        const SizedBox(height: 8),
                        if (_isQrCode)
                          BarcodeWidget(
                            barcode: Barcode.qrCode(),
                            data: barcodeText,
                            width: 84,
                            height: 84,
                          )
                        else
                          BarcodeWidget(
                            barcode: Barcode.code128(),
                            data: barcodeText,
                            width: 210,
                            height: 50,
                            drawText: true,
                            style: const TextStyle(fontSize: 10),
                          ),
                        if (_showPrice) ...[
                          const SizedBox(height: 6),
                          Text(
                            CurrencyHelper.format(priceVal),
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Multi-Product Queue Controls
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _addToQueue,
                        icon: const Icon(Icons.playlist_add_rounded),
                        label: const Text('+ Antrekan Multi-Produk'),
                      ),
                    ),
                  ],
                ),
                if (_labelQueue.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryGreenSoft,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                'Antrean Cetak (${_labelQueue.length} item, $totalQueuedCopies stiker)',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            TextButton(
                              onPressed: () => setState(() => _labelQueue.clear()),
                              child: const Text('Hapus Antrean', style: TextStyle(fontSize: 11, color: AppTheme.accentRed)),
                            ),
                          ],
                        ),
                        ..._labelQueue.asMap().entries.map((e) => Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '• ${e.value.name} (${e.value.copyCount}x)',
                                    style: const TextStyle(fontSize: 11.5),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.close, size: 15, color: AppTheme.accentRed),
                                  onPressed: () => setState(() => _labelQueue.removeAt(e.key)),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                ),
                              ],
                            )),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.print_rounded),
                    label: Text(
                      _printing
                          ? 'MENGIRIM...'
                          : _labelQueue.isNotEmpty
                              ? 'CETAK $totalQueuedCopies LABEL ANTREAN'
                              : 'CETAK $_copyCount LABEL SEKARANG',
                      style: const TextStyle(fontSize: 14),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onPressed: _printing ? null : () => _printLabels(settings, printerProv.printers),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
