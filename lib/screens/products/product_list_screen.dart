import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/product_provider.dart';
import '../../models/product.dart';
import '../../services/excel_service.dart';
import '../../utils/app_theme.dart';
import '../../utils/currency_format.dart';
import 'product_form_screen.dart';
import 'barcode_generator_screen.dart';

class ProductListScreen extends StatefulWidget {
  const ProductListScreen({super.key});

  @override
  State<ProductListScreen> createState() => _ProductListScreenState();
}

class _ProductListScreenState extends State<ProductListScreen> {
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final productProv = Provider.of<ProductProvider>(context);

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
          // Search & Filter
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: Colors.white,
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Cari kode, nama, atau barcode...',
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

          // Categories Chips
          Container(
            height: 44,
            padding: const EdgeInsets.symmetric(vertical: 4),
            color: Colors.white,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: productProv.categories.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (context, index) {
                final cat = productProv.categories[index];
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

          // Product List
          Expanded(
            child: productProv.isLoading
                ? const Center(child: CircularProgressIndicator())
                : productProv.products.isEmpty
                    ? const Center(child: Text('Belum ada produk.'))
                    : ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: productProv.products.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final p = productProv.products[index];
                          return InkWell(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ProductFormScreen(productToEdit: p),
                                ),
                              );
                            },
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: p.isLowStock
                                      ? AppTheme.accentOrange.withOpacity(0.5)
                                      : Colors.grey.shade200,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: p.isService
                                          ? Colors.purple.withOpacity(0.12)
                                          : AppTheme.primaryGreen.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Icon(
                                      p.isService ? Icons.build_circle_rounded : Icons.inventory_2_rounded,
                                      color: p.isService ? Colors.purple : AppTheme.primaryGreen,
                                      size: 22,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          p.name,
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                        ),
                                        Text(
                                          '${p.code} • ${p.category} • ${p.baseUnit}',
                                          style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
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
                                          fontSize: 13,
                                          color: AppTheme.primaryGreen,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: p.isService
                                              ? Colors.purple.shade50
                                              : (p.isLowStock
                                                  ? AppTheme.accentOrange.withOpacity(0.15)
                                                  : Colors.grey.shade100),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          p.isService
                                              ? 'JASA'
                                              : (p.isLowStock
                                                  ? 'Sisa ${p.stock.toInt()} (Rendah)'
                                                  : 'Stok: ${p.stock.toInt()}'),
                                          style: TextStyle(
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.bold,
                                            color: p.isService
                                                ? Colors.purple
                                                : (p.isLowStock
                                                    ? AppTheme.accentOrange
                                                    : AppTheme.textMuted),
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
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppTheme.primaryGreen,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Tambah Produk', style: TextStyle(color: Colors.white)),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ProductFormScreen()),
          );
        },
      ),
    );
  }
}
