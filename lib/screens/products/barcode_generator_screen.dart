import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/product.dart';
import '../../providers/product_provider.dart';
import '../../providers/settings_provider.dart';
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
  final TextEditingController _customNameCtrl = TextEditingController(text: 'Minyak Goreng Sania 2L');
  final TextEditingController _customBarcodeCtrl = TextEditingController(text: '8992345001');
  final TextEditingController _customPriceCtrl = TextEditingController(text: '34500');

  bool _isQrCode = false;
  bool _showStoreName = true;
  bool _showPrice = true;
  int _copyCount = 5;
  String _labelPreset = '40x30';

  @override
  void initState() {
    super.initState();
    final prods = Provider.of<ProductProvider>(context, listen: false).allProducts;
    if (prods.isNotEmpty) {
      _selectedProduct = prods.first;
      _customNameCtrl.text = _selectedProduct!.name;
      _customBarcodeCtrl.text = _selectedProduct!.barcode.isNotEmpty
          ? _selectedProduct!.barcode
          : _selectedProduct!.code;
      _customPriceCtrl.text = _selectedProduct!.sellingPrice.toInt().toString();
    }
  }

  @override
  void dispose() {
    _customNameCtrl.dispose();
    _customBarcodeCtrl.dispose();
    _customPriceCtrl.dispose();
    super.dispose();
  }

  void _onProductSelected(ProductModel? prod) {
    if (prod != null) {
      setState(() {
        _selectedProduct = prod;
        _customNameCtrl.text = prod.name;
        _customBarcodeCtrl.text = prod.barcode.isNotEmpty ? prod.barcode : prod.code;
        _customPriceCtrl.text = prod.sellingPrice.toInt().toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final productProv = Provider.of<ProductProvider>(context);
    final settings = Provider.of<SettingsProvider>(context);

    final barcodeText = _customBarcodeCtrl.text.isNotEmpty ? _customBarcodeCtrl.text : 'SAMPLE1234';
    final priceVal = double.tryParse(_customPriceCtrl.text) ?? 0.0;
    final items = productProv.allProducts;

    return Scaffold(
      appBar: AppBar(title: const Text('Buat & Cetak Barcode / QR Label')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Pilih Produk atau Isi Manual:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 6),
                DropdownButtonFormField<ProductModel>(
                  isExpanded: true,
                  value: items.contains(_selectedProduct) ? _selectedProduct : null,
                  hint: const Text('Pilih dari daftar produk...'),
                  items: items.map((p) {
                    return DropdownMenuItem(
                      value: p,
                      child: Text('${p.name} (${CurrencyHelper.format(p.sellingPrice)})'),
                    );
                  }).toList(),
                  onChanged: _onProductSelected,
                ),
                const SizedBox(height: 12),

                TextField(
                  controller: _customNameCtrl,
                  decoration: const InputDecoration(labelText: 'Nama Produk pada Label'),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _customBarcodeCtrl,
                        decoration: const InputDecoration(labelText: 'Isi Barcode / QR'),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _customPriceCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Harga Jual',
                          prefixText: settings.currencySymbol,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                Row(
                  children: [
                    Expanded(
                      child: ChoiceChip(
                        label: const Center(child: Text('Barcode 1D (Code128)')),
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
                  decoration: const InputDecoration(labelText: 'Ukuran Kertas Stiker'),
                  items: const [
                    DropdownMenuItem(value: '40x30', child: Text('40 x 30 mm (Standar Stiker Thermal)')),
                    DropdownMenuItem(value: '50x30', child: Text('50 x 30 mm (Lebar)')),
                    DropdownMenuItem(value: '58mm', child: Text('58 x 35 mm (Roll 58mm)')),
                  ],
                  onChanged: (v) => setState(() => _labelPreset = v ?? '40x30'),
                ),
                const SizedBox(height: 8),

                Row(
                  children: [
                    Checkbox(
                      value: _showStoreName,
                      onChanged: (val) => setState(() => _showStoreName = val ?? true),
                    ),
                    const Text('Nama Toko', style: TextStyle(fontSize: 12)),
                    const SizedBox(width: 14),
                    Checkbox(
                      value: _showPrice,
                      onChanged: (val) => setState(() => _showPrice = val ?? true),
                    ),
                    const Text('Harga Jual', style: TextStyle(fontSize: 12)),
                  ],
                ),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Jumlah Salinan Cetak:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
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
                const SizedBox(height: 16),

                Center(
                  child: Container(
                    width: 240,
                    padding: const EdgeInsets.all(12),
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
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                        if (_isQrCode)
                          BarcodeWidget(
                            barcode: Barcode.qrCode(),
                            data: barcodeText,
                            width: 80,
                            height: 80,
                          )
                        else
                          BarcodeWidget(
                            barcode: Barcode.code128(),
                            data: barcodeText,
                            width: 200,
                            height: 48,
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
                const SizedBox(height: 20),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.print_rounded),
                    label: Text('CETAK $_copyCount LEMBAR STIKER THERMAL', style: const TextStyle(fontSize: 15)),
                    onPressed: () async {
                      final w = _labelPreset == '58mm' ? 56.0 : (_labelPreset == '50x30' ? 50.0 : 40.0);
                      final h = _labelPreset == '58mm' ? 35.0 : 30.0;
                      final dummyProduct = ProductModel(
                        code: barcodeText,
                        name: _customNameCtrl.text,
                        barcode: barcodeText,
                        sellingPrice: priceVal,
                      );

                      await ThermalPrinterService.printProductLabel(
                        product: dummyProduct,
                        storeName: settings.storeName,
                        copyCount: _copyCount,
                        isQrCode: _isQrCode,
                        showPrice: _showPrice,
                        showStoreName: _showStoreName,
                        labelWidthMm: w,
                        labelHeightMm: h,
                      );
                    },
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
