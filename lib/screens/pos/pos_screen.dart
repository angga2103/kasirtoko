import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/pos_provider.dart';
import '../../providers/product_provider.dart';
import '../../providers/auth_provider.dart';
import '../../models/product.dart';
import '../../models/product_unit.dart';
import '../../utils/app_theme.dart';
import '../../utils/currency_format.dart';
import 'payment_dialog.dart';
import 'held_orders_dialog.dart';

class PosScreen extends StatefulWidget {
  const PosScreen({super.key});

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<ProductProvider>(context, listen: false).loadProducts();
    });
  }

  void _showUnitSelector(ProductModel product) {
    if (product.units.isEmpty) {
      Provider.of<PosProvider>(context, listen: false).addProduct(product);
      return;
    }

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pilih Satuan: ${product.name}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                ListTile(
                  leading: const Icon(Icons.check_circle_outline, color: AppTheme.primaryGreen),
                  title: Text('Satuan Dasar (${product.baseUnit})'),
                  subtitle: Text(CurrencyHelper.format(product.sellingPrice)),
                  onTap: () {
                    Provider.of<PosProvider>(context, listen: false).addProduct(product);
                    Navigator.pop(ctx);
                  },
                ),
                ...product.units.map((unit) {
                  return ListTile(
                    leading: const Icon(Icons.inventory_2_outlined, color: AppTheme.accentOrange),
                    title: Text('${unit.unitName} (Isi ${unit.conversionFactor.toInt()} ${product.baseUnit})'),
                    subtitle: Text(CurrencyHelper.format(unit.sellingPrice)),
                    onTap: () {
                      Provider.of<PosProvider>(context, listen: false).addProduct(product, selectedUnit: unit);
                      Navigator.pop(ctx);
                    },
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showCartSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.65,
          maxChildSize: 0.9,
          minChildSize: 0.4,
          expand: false,
          builder: (context, scrollController) {
            return Consumer2<PosProvider, ProductProvider>(
              builder: (context, pos, productProv, _) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Keranjang Belanja (${pos.itemCount} Item)',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          TextButton.icon(
                            icon: const Icon(Icons.pause_circle_outline, size: 18),
                            label: const Text('Tahan Order'),
                            onPressed: pos.isEmpty
                                ? null
                                : () {
                                    pos.holdCurrentOrder();
                                    Navigator.pop(ctx);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Pesanan berhasil ditahan.')),
                                    );
                                  },
                          ),
                        ],
                      ),
                      const Divider(),
                      Expanded(
                        child: pos.isEmpty
                            ? const Center(child: Text('Keranjang masih kosong'))
                            : ListView.separated(
                                controller: scrollController,
                                itemCount: pos.cartItems.length,
                                separatorBuilder: (_, __) => const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final item = pos.cartItems[index];
                                  final prod = productProv.products.firstWhere(
                                    (p) => p.id == item.productId,
                                    orElse: () => ProductModel(
                                      code: item.productCode,
                                      name: item.productName,
                                      sellingPrice: item.unitPrice,
                                    ),
                                  );

                                  return Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 6),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                item.productName,
                                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                              ),
                                              Text(
                                                '${CurrencyHelper.format(item.unitPrice)} / ${item.unitName}',
                                                style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                                              ),
                                              Text(
                                                'Total: ${CurrencyHelper.format(item.subtotal)}',
                                                style: const TextStyle(
                                                    fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.primaryGreen),
                                              ),
                                            ],
                                          ),
                                        ),
                                        // Qty controls
                                        Row(
                                          children: [
                                            IconButton(
                                              icon: const Icon(Icons.remove_circle_outline, color: AppTheme.accentRed),
                                              onPressed: () => pos.updateItemQty(index, item.qty - 1, prod),
                                            ),
                                            Text(
                                              '${item.qty.toStringAsFixed(item.qty.truncateToDouble() == item.qty ? 0 : 1)} ${item.unitName}',
                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                            ),
                                            IconButton(
                                              icon: const Icon(Icons.add_circle_outline, color: AppTheme.primaryGreen),
                                              onPressed: () => pos.updateItemQty(index, item.qty + 1, prod),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                      ),
                      const Divider(),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Grand Total:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          Text(
                            CurrencyHelper.format(pos.grandTotal),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primaryGreen,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: pos.isEmpty
                              ? null
                              : () {
                                  Navigator.pop(ctx);
                                  showDialog(
                                    context: context,
                                    builder: (_) => const PaymentDialog(),
                                  );
                                },
                          child: const Text('PROSES PEMBAYARAN', style: TextStyle(fontSize: 16)),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final productProv = Provider.of<ProductProvider>(context);
    final pos = Provider.of<PosProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kasir (POS)'),
        actions: [
          // Held Orders Button
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.pause_circle_rounded),
                tooltip: 'Pesanan Ditahan',
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (_) => const HeldOrdersDialog(),
                  );
                },
              ),
              if (pos.heldOrders.isNotEmpty)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: AppTheme.accentOrange,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${pos.heldOrders.length}',
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_rounded),
            tooltip: 'Kosongkan Keranjang',
            onPressed: pos.isEmpty ? null : pos.clearCart,
          ),
        ],
      ),
      body: Column(
        children: [
          // Search & Barcode Scan Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: Colors.white,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      hintText: 'Cari nama produk / scan barcode...',
                      hintStyle: const TextStyle(fontSize: 13),
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      suffixIcon: _searchCtrl.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, size: 18),
                              onPressed: () {
                                _searchCtrl.clear();
                                productProv.loadProducts(query: '');
                              },
                            )
                          : null,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    onChanged: (val) {
                      productProv.loadProducts(query: val);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                // Barcode simulation or camera scanner trigger
                Container(
                  decoration: BoxDecoration(
                    color: AppTheme.primaryGreen.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.qr_code_scanner_rounded, color: AppTheme.primaryGreen),
                    tooltip: 'Scan Barcode Kamera',
                    onPressed: () {
                      _showManualBarcodeDialog(context);
                    },
                  ),
                ),
              ],
            ),
          ),

          // Categories Horizontal Chips
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
                  onSelected: (_) {
                    productProv.loadProducts(category: cat);
                  },
                );
              },
            ),
          ),
          const Divider(height: 1),

          // Products Grid
          Expanded(
            child: productProv.isLoading
                ? const Center(child: CircularProgressIndicator())
                : productProv.products.isEmpty
                    ? const Center(child: Text('Tidak ada produk ditemukan'))
                    : GridView.builder(
                        padding: const EdgeInsets.all(12),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                          childAspectRatio: 1.1,
                        ),
                        itemCount: productProv.products.length,
                        itemBuilder: (context, index) {
                          final prod = productProv.products[index];
                          return InkWell(
                            onTap: () => pos.addProduct(prod),
                            onLongPress: () => _showUnitSelector(prod),
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: prod.isLowStock
                                      ? AppTheme.accentOrange.withOpacity(0.5)
                                      : Colors.black.withOpacity(0.06),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: prod.isService
                                              ? Colors.purple.withOpacity(0.12)
                                              : (prod.isLowStock
                                                  ? AppTheme.accentOrange.withOpacity(0.15)
                                                  : Colors.grey.shade100),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          prod.isService
                                              ? 'JASA'
                                              : (prod.isLowStock
                                                  ? 'Sisa ${prod.stock.toInt()}'
                                                  : 'Stok: ${prod.stock.toInt()}'),
                                          style: TextStyle(
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.bold,
                                            color: prod.isService
                                                ? Colors.purple
                                                : (prod.isLowStock ? AppTheme.accentOrange : AppTheme.textMuted),
                                          ),
                                        ),
                                      ),
                                      if (prod.units.isNotEmpty)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: AppTheme.primaryGreen.withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            '+${prod.units.length} Satuan',
                                            style: const TextStyle(fontSize: 8.5, color: AppTheme.primaryGreen),
                                          ),
                                        ),
                                    ],
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        prod.name,
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${prod.code} • ${prod.baseUnit}',
                                        style: const TextStyle(fontSize: 10, color: AppTheme.textMuted),
                                      ),
                                    ],
                                  ),
                                  Text(
                                    CurrencyHelper.format(prod.sellingPrice),
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.primaryGreen,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),

          // Bottom Cart Summary Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  offset: const Offset(0, -3),
                  blurRadius: 6,
                ),
              ],
            ),
            child: Row(
              children: [
                InkWell(
                  onTap: _showCartSheet,
                  child: Row(
                    children: [
                      Stack(
                        children: [
                          const Icon(Icons.shopping_cart_rounded, size: 28, color: AppTheme.primaryGreen),
                          if (pos.itemCount > 0)
                            Positioned(
                              top: -2,
                              right: -2,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                  color: AppTheme.accentOrange,
                                  shape: BoxShape.circle,
                                ),
                                child: Text(
                                  '${pos.itemCount}',
                                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Total Belanja', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                          Text(
                            CurrencyHelper.format(pos.grandTotal),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textDark,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                ElevatedButton.icon(
                  icon: const Icon(Icons.payment_rounded, size: 20),
                  label: const Text('BAYAR', style: TextStyle(fontSize: 15)),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                  onPressed: pos.isEmpty
                      ? null
                      : () {
                          showDialog(
                            context: context,
                            builder: (_) => const PaymentDialog(),
                          );
                        },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showManualBarcodeDialog(BuildContext context) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Scan / Ketik Barcode'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Contoh: 8992345001',
              prefixIcon: Icon(Icons.qr_code_rounded),
            ),
            onSubmitted: (code) async {
              Navigator.pop(ctx);
              final productProv = Provider.of<ProductProvider>(context, listen: false);
              final pos = Provider.of<PosProvider>(context, listen: false);
              final found = productProv.products.where((p) => p.barcode == code || p.code == code);
              if (found.isNotEmpty) {
                pos.addProduct(found.first);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Berhasil menambahkan: ${found.first.name}')),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Produk barcode tidak ditemukan!')),
                );
              }
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Tutup'),
            ),
          ],
        );
      },
    );
  }
}
