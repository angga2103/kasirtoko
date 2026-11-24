import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:barcode_widget/barcode_widget.dart';
import '../../models/product.dart';
import '../../providers/product_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/thermal_printer_service.dart';
import '../../utils/app_theme.dart';
import '../../utils/currency_format.dart';

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

  bool _isQrCode = false; // False = Barcode 1D, True = QR Code 2D
  bool _showStoreName = true;
  bool _showPrice = true;
  int _copyCount = 5;
  String _labelPreset = '40x30'; // '40x30', '50x30', '58mm'

  @override
  void initState() {
    super.initState();
    final prods = Provider.of<ProductProvider>(context, listen: false).products;
    if (prods.isNotEmpty) {
      _selectedProduct = prods.first;
      _customNameCtrl.text = _selectedProduct!.name;
      _customBarcodeCtrl.text = _selectedProduct!.barcode.isNotEmpty
          ? _selectedProduct!.barcode
          : _selectedProduct!.code;
      _customPriceCtrl.text = _selectedProduct!.sellingPrice.toInt().toString();
    }
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Buat & Cetak Barcode / QR'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Product Selection Dropdown
            const Text('Pilih Produk atau Masukkan Manual:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<ProductModel>(
                  isExpanded: true,
                  value: _selectedProduct,
                  hint: const Text('Pilih dari daftar produk...'),
                  items: productProv.products.map((p) {
                    return DropdownMenuItem(
                      value: p,
                      child: Text('${p.name} (${CurrencyHelper.format(p.sellingPrice)})'),
                    );
                  }).toList(),
                  onChanged: _onProductSelected,
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Text Inputs
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
                    decoration: const InputDecoration(labelText: 'Harga Jual (Rp)'),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Format & Settings
            const Text('Pengaturan Label Thermal:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ChoiceChip(
                    label: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.barcode_reader, size: 16),
                        SizedBox(width: 6),
                        Text('Barcode 1D'),
                      ],
                    ),
                    selected: !_isQrCode,
                    selectedColor: AppTheme.primaryGreenLight,
                    onSelected: (val) => setState(() => _isQrCode = !val),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ChoiceChip(
                    label: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.qr_code_2_rounded, size: 16),
                        SizedBox(width: 6),
                        Text('QR Code 2D'),
                      ],
                    ),
                    selected: _isQrCode,
                    selectedColor: AppTheme.primaryGreenLight,
                    onSelected: (val) => setState(() => _isQrCode = val),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Checkbox options
            Row(
              children: [
                Checkbox(
                  value: _showStoreName,
                  onChanged: (val) => setState(() => _showStoreName = val ?? true),
                ),
                const Text('Tampilkan Nama Toko', style: TextStyle(fontSize: 12)),
                const SizedBox(width: 16),
                Checkbox(
                  value: _showPrice,
                  onChanged: (val) => setState(() => _showPrice = val ?? true),
                ),
                const Text('Tampilkan Harga', style: TextStyle(fontSize: 12)),
              ],
            ),

            // Copy Count & Size
            Row(
              children: [
                const Text('Jumlah Salinan Cetak: ', style: TextStyle(fontSize: 12)),
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: _copyCount > 1 ? () => setState(() => _copyCount--) : null,
                ),
                Text('$_copyCount Pcs', style: const TextStyle(fontWeight: FontWeight.bold)),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: () => setState(() => _copyCount++),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Preview Box
            const Text('Pratinjau Hasil Cetak Stiker Thermal:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 8),
            Center(
              child: Container(
                width: 240,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.black26),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 4),
                  ],
                ),
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
            const SizedBox(height: 24),

            // Print Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.print_rounded),
                label: Text('CETAK $_copyCount LEMBAR STIKER THERMAL', style: const TextStyle(fontSize: 15)),
                onPressed: () async {
                  final dummyProduct = ProductModel(
                    code: _customBarcodeCtrl.text,
                    name: _customNameCtrl.text,
                    barcode: _customBarcodeCtrl.text,
                    sellingPrice: priceVal,
                  );

                  await ThermalPrinterService.printProductLabel(
                    product: dummyProduct,
                    storeName: settings.storeName,
                    copyCount: _copyCount,
                    isQrCode: _isQrCode,
                    showPrice: _showPrice,
                    showStoreName: _showStoreName,
                  );
                },
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
