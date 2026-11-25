import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/user.dart';
import '../../providers/auth_provider.dart';
import '../../providers/product_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/excel_service.dart';
import '../../utils/app_theme.dart';
import '../../utils/currency_format.dart';
import '../scanner/barcode_scanner_screen.dart';
import 'barcode_generator_screen.dart';
import 'product_form_screen.dart';

class ProductListScreen extends StatefulWidget {
  const ProductListScreen({super.key});

  @override
  State<ProductListScreen> createState() => _ProductListScreenState();
}

class _ProductListScreenState extends State<ProductListScreen> {
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _scanToSearch(ProductProvider productProv) async {
    final code = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => const BarcodeScannerScreen(
          title: 'Cari Produk via Barcode',
          continuousMode: false,
        ),
      ),
    );
    if (code != null && code.isNotEmpty && mounted) {
      _searchCtrl.text = code;
      await productProv.loadProducts(query: code);
    }
  }

  @override
  Widget build(BuildContext context) {
    final productProv = Provider.of<ProductProvider>(context);
    final auth = Provider.of<AuthProvider>(context);
    final settings = Provider.of<SettingsProvider>(context);

    final canManage = auth.hasPermission(AppPermissions.manageProducts);
    final canSeeCost = auth.hasPermission(AppPermissions.viewCostPrice);
    final categories = productProv.categoriesForBusiness(settings.businessType);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Master Produk & Stok'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (val) async {
              if (val == 'import_excel') {
                final list = await ExcelService.pickAndParseProductsExcel();
                if (list.isNotEmpty && context.mounted) {
                  final count = await productProv.importProducts(list);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Berhasil mengimpor $count produk dari Excel!')),
                  );
                }
              } else if (val == 'export_excel') {
                final path = await ExcelService.exportProductsToExcel(productProv.products);
                if (path.isNotEmpty && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('File Excel berhasil diekspor & dibagikan.')),
                  );
                }
              } else if (val == 'cetak_barcode') {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const BarcodeGeneratorScreen()),
                );
              }
            },
            itemBuilder: (ctx) => [
              if (canManage)
                const PopupMenuItem(
                  value: 'import_excel',
                  child: Row(
                    children: [
                      Icon(Icons.file_upload_rounded, color: Colors.green, size: 20),
                      SizedBox(width: 8),
                      Text('Impor Massal Excel (.xlsx)'),
                    ],
                  ),
                ),
              const PopupMenuItem(
                value: 'export_excel',
                child: Row(
                  children: [
                    Icon(Icons.file_download_rounded, color: Colors.blue, size: 20),
                    SizedBox(width: 8),
                    Text('Ekspor Katalog ke Excel'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'cetak_barcode',
                child: Row(
                  children: [
                    Icon(Icons.qr_code_2_rounded, color: Colors.cyan, size: 20),
                    SizedBox(width: 8),
                    Text('Cetak Label Barcode'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: Colors.white,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      hintText: 'Cari kode, nama, IMEI, atau barcode...',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _searchCtrl.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchCtrl.clear();
                                productProv.loadProducts(query: '');
                              },
                            )
                          : null,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    onChanged: (val) => productProv.loadProducts(query: val),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  onPressed: () => _scanToSearch(productProv),
                  icon: const Icon(Icons.qr_code_scanner_rounded, color: AppTheme.primaryGreen),
                  tooltip: 'Scan Barcode',
                ),
              ],
            ),
          ),

          Container(
            height: 44,
            padding: const EdgeInsets.symmetric(vertical: 4),
            color: Colors.white,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: categories.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (context, index) {
                final cat = categories[index];
                final isSelected = cat == productProv.selectedCategory;
                return ChoiceChip(
                  label: Text(cat, style: TextStyle(fontSize: 12, color: isSelected ? Colors.white : AppTheme.textDark)),
                  selected: isSelected,
                  selectedColor: AppTheme.primaryGreen,
                  backgroundColor: AppTheme.lightGreyBg,
                  onSelected: (_) => productProv.loadProducts(category: cat),
                );
              },
            ),
          ),
          const Divider(height: 1),

          Expanded(
            child: productProv.isLoading
                ? const Center(child: CircularProgressIndicator())
                : productProv.products.isEmpty
                    ? const Center(child: Text('Belum ada produk ditemukan.'))
                    : ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: productProv.products.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final p = productProv.products[index];
                          final hasImg = p.imagePath != null &&
                              p.imagePath!.isNotEmpty &&
                              File(p.imagePath!).existsSync();

                          return InkWell(
                            onTap: canManage
                                ? () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(builder: (_) => ProductFormScreen(productToEdit: p)),
                                    );
                                  }
                                : null,
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: AppTheme.cardDecoration(
                                borderColor: p.isLowStock
                                    ? AppTheme.accentOrange.withValues(alpha: 0.6)
                                    : AppTheme.borderLight,
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 50,
                                    height: 50,
                                    decoration: BoxDecoration(
                                      color: p.isService
                                          ? Colors.purple.withValues(alpha: 0.12)
                                          : AppTheme.primaryGreen.withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    clipBehavior: Clip.antiAlias,
                                    child: hasImg
                                        ? Image.file(File(p.imagePath!), fit: BoxFit.cover)
                                        : Icon(
                                            p.isService ? Icons.build_circle_rounded : Icons.inventory_2_rounded,
                                            color: p.isService ? Colors.purple : AppTheme.primaryGreen,
                                            size: 24,
                                          ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          p.name,
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                                        ),
                                        Text(
                                          '${p.code} • ${p.category} • ${p.baseUnit}${p.barcode.isNotEmpty ? " • [${p.barcode}]" : ""}',
                                          style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                                        ),
                                        if (p.conditionType == 'bekas' || p.imeiOrSn.isNotEmpty)
                                          Text(
                                            '${p.conditionType.toUpperCase()}${p.imeiOrSn.isNotEmpty ? " • SN/IMEI: ${p.imeiOrSn}" : ""}',
                                            style: const TextStyle(fontSize: 10.5, color: AppTheme.accentIndigo),
                                          ),
                                        if (p.units.isNotEmpty)
                                          Text(
                                            'Multi Satuan: ${p.units.map((u) => u.unitName).join(', ')}',
                                            style: const TextStyle(fontSize: 10, color: Colors.teal),
                                          ),
                                      ],
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        CurrencyHelper.format(p.sellingPrice),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13.5,
                                          color: AppTheme.primaryGreen,
                                        ),
                                      ),
                                      if (canSeeCost)
                                        Text(
                                          'HPP: ${CurrencyHelper.format(p.costPrice)}',
                                          style: const TextStyle(fontSize: 10, color: AppTheme.textMuted),
                                        ),
                                      const SizedBox(height: 3),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: p.isService
                                              ? Colors.purple.shade50
                                              : (p.isLowStock
                                                  ? AppTheme.accentOrange.withValues(alpha: 0.15)
                                                  : Colors.grey.shade100),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          p.isService
                                              ? 'JASA'
                                              : (p.isLowStock
                                                  ? 'Sisa ${p.stock.toInt()} (Menipis)'
                                                  : 'Stok: ${p.stock.toInt()}'),
                                          style: TextStyle(
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.bold,
                                            color: p.isService
                                                ? Colors.purple
                                                : (p.isLowStock ? AppTheme.accentOrange : AppTheme.textMuted),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              backgroundColor: AppTheme.primaryGreen,
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text('Tambah Produk', style: TextStyle(color: Colors.white)),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ProductFormScreen()),
                );
              },
            )
          : null,
    );
  }
}
