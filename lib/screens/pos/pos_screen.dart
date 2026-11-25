import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../models/customer.dart';
import '../../models/product.dart';
import '../../models/promo.dart';
import '../../models/user.dart';
import '../../providers/auth_provider.dart';
import '../../providers/cash_flow_provider.dart';
import '../../providers/customer_provider.dart';
import '../../providers/pos_provider.dart';
import '../../providers/product_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/hardware_bridge.dart';
import '../../utils/app_theme.dart';
import '../../utils/currency_format.dart';
import '../../widgets/quantity_stepper.dart';
import '../cash_flow/shift_screen.dart';
import '../scanner/barcode_scanner_screen.dart';
import 'held_orders_dialog.dart';
import 'payment_dialog.dart';

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
      final prodProv = Provider.of<ProductProvider>(context, listen: false);
      final pos = Provider.of<PosProvider>(context, listen: false);
      final settings = Provider.of<SettingsProvider>(context, listen: false);
      final cashFlow = Provider.of<CashFlowProvider>(context, listen: false);
      final custProv = Provider.of<CustomerProvider>(context, listen: false);
      prodProv.loadProducts();
      pos.loadPromos();
      cashFlow.checkOpenShift();
      custProv.loadCustomers();
      pos.configureTax(enabled: settings.taxEnabled, rate: settings.taxRate);
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _showCartError(String? msg) {
    if (msg == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppTheme.accentRed),
    );
  }

  Future<void> _handleBarcodeInput(String rawCode) async {
    final code = rawCode.trim();
    if (code.isEmpty) return;

    final productProv = Provider.of<ProductProvider>(context, listen: false);
    final pos = Provider.of<PosProvider>(context, listen: false);

    final match = await productProv.findProductByBarcode(code);
    if (match != null) {
      final res = pos.addProduct(match.product, selectedUnit: match.matchedUnit);
      await HardwareBridge.playBeep();
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      if (res.success) {
        final unitLabel = match.matchedUnit?.unitName ?? match.product.baseUnit;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ditambahkan: ${match.product.name} ($unitLabel)'),
            duration: const Duration(milliseconds: 1300),
            backgroundColor: AppTheme.success,
          ),
        );
      } else {
        _showCartError(res.message);
      }
      _searchCtrl.clear();
      productProv.loadProducts(query: '');
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Barcode "$code" tidak ditemukan dalam master produk.'),
            backgroundColor: AppTheme.accentOrange,
          ),
        );
      }
    }
  }

  Future<void> _openContinuousScanner() async {
    final productProv = Provider.of<ProductProvider>(context, listen: false);
    final pos = Provider.of<PosProvider>(context, listen: false);

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BarcodeScannerScreen(
          title: 'Scan Barcode Kasir',
          helperText: 'Scan beruntun • Anti-double-scan aktif',
          continuousMode: true,
          onBarcodeScanned: (barcode) async {
            final match = await productProv.findProductByBarcode(barcode);
            if (match == null) {
              return ContinuousScanEventResult(
                found: false,
                title: 'Tidak ditemukan',
              );
            }
            final res = pos.addProduct(match.product, selectedUnit: match.matchedUnit);
            final unitLabel = match.matchedUnit?.unitName ?? match.product.baseUnit;
            if (!res.success) {
              return ContinuousScanEventResult(
                found: false,
                title: match.product.name,
                subtitle: res.message ?? 'Stok habis',
              );
            }
            return ContinuousScanEventResult(
              found: true,
              title: match.product.name,
              subtitle: '($unitLabel • ${CurrencyHelper.format(match.matchedUnit?.sellingPrice ?? match.product.sellingPrice)})',
            );
          },
        ),
      ),
    );
  }

  void _showUnitSelector(ProductModel product) {
    final pos = Provider.of<PosProvider>(context, listen: false);
    if (product.units.isEmpty) {
      final res = pos.addProduct(product);
      if (!res.success) _showCartError(res.message);
      return;
    }

    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Pilih Satuan: ${product.name}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              ListTile(
                leading: const Icon(Icons.check_circle_outline, color: AppTheme.primaryGreen),
                title: Text('Satuan Dasar (${product.baseUnit})'),
                subtitle: Text(CurrencyHelper.format(product.sellingPrice)),
                onTap: () {
                  final res = pos.addProduct(product);
                  Navigator.pop(ctx);
                  if (!res.success) _showCartError(res.message);
                },
              ),
              ...product.units.map((unit) {
                return ListTile(
                  leading: const Icon(Icons.inventory_2_outlined, color: AppTheme.accentOrange),
                  title: Text('${unit.unitName} (Isi ${unit.conversionFactor.toInt()} ${product.baseUnit})'),
                  subtitle: Text(CurrencyHelper.format(unit.sellingPrice)),
                  onTap: () {
                    final res = pos.addProduct(product, selectedUnit: unit);
                    Navigator.pop(ctx);
                    if (!res.success) _showCartError(res.message);
                  },
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  void _showCustomerPickerDialog() {
    final custProv = Provider.of<CustomerProvider>(context, listen: false);
    final pos = Provider.of<PosProvider>(context, listen: false);
    final nameCtrl = TextEditingController(text: pos.customerName);
    final phoneCtrl = TextEditingController(text: pos.customerPhone);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pilih / Isi Pelanggan'),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Nama Pelanggan'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'No. HP / WA'),
                ),
                const Divider(height: 20),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Atau Pilih dari Daftar Pelanggan:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  height: 180,
                  child: ListView.builder(
                    itemCount: custProv.customers.length,
                    itemBuilder: (_, i) {
                      final CustomerModel c = custProv.customers[i];
                      return ListTile(
                        dense: true,
                        title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(c.phone),
                        onTap: () {
                          pos.setCustomerInfo(c.name, c.phone, customerId: c.id);
                          Navigator.pop(ctx);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          ElevatedButton(
            onPressed: () {
              final enteredName = nameCtrl.text.trim();
              final match = custProv.customers.cast<CustomerModel?>().firstWhere(
                (c) => c != null && c.name.trim().toLowerCase() == enteredName.toLowerCase(),
                orElse: () => null,
              );
              pos.setCustomerInfo(nameCtrl.text, phoneCtrl.text, customerId: match?.id);
              Navigator.pop(ctx);
            },
            child: const Text('Terapkan'),
          ),
        ],
      ),
    ).then((_) {
      nameCtrl.dispose();
      phoneCtrl.dispose();
    });
  }

  void _showDiscountAndPromoDialog() {
    final pos = Provider.of<PosProvider>(context, listen: false);
    final auth = Provider.of<AuthProvider>(context, listen: false);
    if (!auth.hasPermission(AppPermissions.applyDiscount)) {
      _showCartError('Akun Anda tidak memiliki izin memberi diskon manual / promo.');
      return;
    }

    final discountCtrl = TextEditingController(text: pos.manualCartDiscount.toInt().toString());
    PromoModel? pickedPromo = pos.selectedPromo;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDState) => AlertDialog(
          title: const Text('Diskon & Promo Transaksi'),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: discountCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Potongan / Diskon Manual (Rp)',
                      prefixText: 'Rp ',
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text('Pilih Promo Aktif Toko:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 6),
                  if (pos.activePromos.isEmpty)
                    const Text('Tidak ada promo aktif saat ini.', style: TextStyle(fontSize: 12, color: AppTheme.textMuted))
                  else ...[
                    RadioListTile<PromoModel?>(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Tanpa Promo'),
                      value: null,
                      groupValue: pickedPromo,
                      onChanged: (v) => setDState(() => pickedPromo = v),
                    ),
                    ...pos.activePromos.map((promo) => RadioListTile<PromoModel?>(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(promo.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(
                            promo.promoType == 'diskon_persen'
                                ? 'Diskon ${promo.discountValue.toInt()}% (Min. ${CurrencyHelper.format(promo.minPurchase)})'
                                : (promo.promoType == 'potongan_nominal'
                                    ? 'Potongan ${CurrencyHelper.format(promo.discountValue)} (Min. ${CurrencyHelper.format(promo.minPurchase)})'
                                    : 'Beli ${promo.buyQty} Gratis ${promo.getQty}'),
                            style: const TextStyle(fontSize: 11),
                          ),
                          value: promo,
                          groupValue: pickedPromo,
                          onChanged: (v) => setDState(() => pickedPromo = v),
                        )),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
            ElevatedButton(
              onPressed: () {
                final disc = double.tryParse(discountCtrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0.0;
                pos.setCartDiscount(disc);
                pos.setSelectedPromo(pickedPromo);
                Navigator.pop(ctx);
              },
              child: const Text('Terapkan'),
            ),
          ],
        ),
      ),
    ).then((_) => discountCtrl.dispose());
  }

  void _openPaymentFlow() {
    final cashFlow = Provider.of<CashFlowProvider>(context, listen: false);
    if (!cashFlow.isShiftOpen) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.lock_clock_rounded, color: AppTheme.accentOrange),
              SizedBox(width: 8),
              Expanded(child: Text('Shift Kasir Belum Dibuka')),
            ],
          ),
          content: const Text(
            'Transaksi penjualan hanya diperbolehkan saat shift kasir aktif agar kas laci dan laporan akurat. Silakan buka shift terlebih dahulu.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Tutup')),
            ElevatedButton.icon(
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Buka Shift Sekarang'),
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const ShiftScreen())).then((_) {
                  if (mounted) cashFlow.checkOpenShift();
                });
              },
            ),
          ],
        ),
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PaymentDialog(),
    );
  }

  void _showMobileCartSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final viewInsets = MediaQuery.viewInsetsOf(ctx).bottom;
        return Padding(
          padding: EdgeInsets.only(bottom: viewInsets),
          child: DraggableScrollableSheet(
            initialChildSize: 0.78,
            maxChildSize: 0.94,
            minChildSize: 0.45,
            expand: false,
            builder: (context, scrollController) {
              return _CartPanelWidget(
                scrollController: scrollController,
                isModalSheet: true,
                onCloseModal: () => Navigator.pop(ctx),
                onCheckoutPressed: () {
                  Navigator.pop(ctx);
                  _openPaymentFlow();
                },
                onPickCustomer: _showCustomerPickerDialog,
                onPickDiscount: _showDiscountAndPromoDialog,
                onCartError: _showCartError,
              );
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final productProv = Provider.of<ProductProvider>(context);
    final pos = Provider.of<PosProvider>(context);
    final settings = Provider.of<SettingsProvider>(context);
    final cashFlow = Provider.of<CashFlowProvider>(context);

    final isTablet = AppBreakpoints.isTablet(context);
    final categories = productProv.categoriesForBusiness(settings.businessType);
    final gridCols = AppBreakpoints.productGridCount(context, twoPane: isTablet);

    final catalogSection = Column(
      children: [
        // Search + Camera Scan Bar (Supports USB/BT HID Enter & Realtime Camera)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: Colors.white,
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Cari produk / scan USB HID barcode...',
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
                  onChanged: (val) => productProv.loadProducts(query: val),
                  onSubmitted: _handleBarcodeInput,
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _openContinuousScanner,
                icon: const Icon(Icons.qr_code_scanner_rounded, size: 20),
                label: Text(isTablet ? 'Scan Kamera' : 'Scan'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                ),
              ),
            ],
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

        // Product Grid
        Expanded(
          child: productProv.isLoading
              ? const Center(child: CircularProgressIndicator())
              : productProv.products.isEmpty
                  ? const Center(child: Text('Tidak ada produk ditemukan'))
                  : GridView.builder(
                      padding: const EdgeInsets.all(12),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: gridCols,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        childAspectRatio: isTablet ? 0.78 : 0.68,
                      ),
                      itemCount: productProv.products.length,
                      itemBuilder: (context, index) {
                        final prod = productProv.products[index];
                        final cartQty = pos.getCartQtyForProduct(prod.id ?? -1);
                        final baseCartQty = pos.getBaseCartQtyForProduct(prod.id ?? -1, prod.baseUnit);
                        final hasImage = prod.imagePath != null &&
                            prod.imagePath!.isNotEmpty &&
                            File(prod.imagePath!).existsSync();

                        return Material(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            onTap: () {
                              final res = pos.addProduct(prod);
                              if (!res.success) _showCartError(res.message);
                            },
                            onLongPress: () => _showUnitSelector(prod),
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.all(9),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: cartQty > 0
                                      ? AppTheme.primaryGreen
                                      : (prod.isLowStock
                                          ? AppTheme.accentOrange.withValues(alpha: 0.6)
                                          : AppTheme.borderLight),
                                  width: cartQty > 0 ? 1.8 : 1,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Photo + Stock + In-Cart Qty Badge
                                  Expanded(
                                    child: Stack(
                                      children: [
                                        Container(
                                          width: double.infinity,
                                          decoration: BoxDecoration(
                                            color: prod.isService
                                                ? Colors.purple.withValues(alpha: 0.08)
                                                : AppTheme.lightGreyBg,
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          clipBehavior: Clip.antiAlias,
                                          child: hasImage
                                              ? Image.file(File(prod.imagePath!), fit: BoxFit.cover)
                                              : Center(
                                                  child: Icon(
                                                    prod.isService ? Icons.build_circle_rounded : Icons.inventory_2_rounded,
                                                    color: prod.isService ? Colors.purple : AppTheme.primaryGreenLight,
                                                    size: 30,
                                                  ),
                                                ),
                                        ),
                                        Positioned(
                                          top: 4,
                                          left: 4,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: prod.isService
                                                  ? Colors.purple.shade700
                                                  : (!prod.trackStock
                                                      ? Colors.blueGrey
                                                      : (prod.isLowStock ? AppTheme.accentOrange : Colors.black87)),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              prod.isService
                                                  ? 'JASA'
                                                  : (!prod.trackStock
                                                      ? 'NON-STOK'
                                                      : 'Stok: ${prod.stock == prod.stock.truncateToDouble() ? prod.stock.toInt() : prod.stock.toStringAsFixed(1)}'),
                                              style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                        ),
                                        if (cartQty > 0)
                                          Positioned(
                                            top: 4,
                                            right: 4,
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                              decoration: BoxDecoration(
                                                color: AppTheme.primaryGreen,
                                                borderRadius: BorderRadius.circular(10),
                                              ),
                                              child: Text(
                                                'x${cartQty == cartQty.truncateToDouble() ? cartQty.toInt() : cartQty.toStringAsFixed(1)}',
                                                style: const TextStyle(
                                                    color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    prod.name,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          CurrencyHelper.format(prod.sellingPrice),
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                            color: AppTheme.primaryGreen,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (prod.units.isNotEmpty)
                                        GestureDetector(
                                          onTap: () => _showUnitSelector(prod),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: AppTheme.primaryGreenSoft,
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              '+${prod.units.length} Satuan',
                                              style: const TextStyle(
                                                  fontSize: 9, fontWeight: FontWeight.bold, color: AppTheme.primaryGreen),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  _ProductGridQtyControl(
                                    qty: baseCartQty,
                                    unitLabel: prod.baseUnit,
                                    onDecrement: () {
                                      final res = pos.setExactBaseQtyForProduct(prod, baseCartQty - 1);
                                      if (!res.success) _showCartError(res.message);
                                    },
                                    onIncrement: () {
                                      final res = pos.addProduct(prod);
                                      if (!res.success) _showCartError(res.message);
                                    },
                                    onSetQty: (val) {
                                      final res = pos.setExactBaseQtyForProduct(prod, val);
                                      if (!res.success) _showCartError(res.message);
                                      return res.success;
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: Row(
          children: [
            const Flexible(
              child: Text(
                'Kasir (POS)',
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            const SizedBox(width: 6),
            InkWell(
              onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const ShiftScreen())).then((_) {
                  if (mounted) cashFlow.checkOpenShift();
                });
              },
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: cashFlow.isShiftOpen ? AppTheme.success : AppTheme.accentOrange,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  cashFlow.isShiftOpen ? 'Shift Aktif' : 'Buka Shift',
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                  maxLines: 1,
                ),
              ),
            ),
          ],
        ),
        actions: [
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.pause_circle_rounded),
                tooltip: 'Pesanan Ditahan',
                onPressed: () {
                  showDialog(context: context, builder: (_) => const HeldOrdersDialog());
                },
              ),
              if (pos.heldOrders.isNotEmpty)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(color: AppTheme.accentOrange, shape: BoxShape.circle),
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
      body: isTablet
          ? Row(
              children: [
                Expanded(child: catalogSection),
                const VerticalDivider(width: 1),
                SizedBox(
                  width: MediaQuery.sizeOf(context).width >= AppBreakpoints.largeTablet ? 410 : 350,
                  child: _CartPanelWidget(
                    isModalSheet: false,
                    onCheckoutPressed: _openPaymentFlow,
                    onPickCustomer: _showCustomerPickerDialog,
                    onPickDiscount: _showDiscountAndPromoDialog,
                    onCartError: _showCartError,
                  ),
                ),
              ],
            )
          : Column(
              children: [
                Expanded(child: catalogSection),
                // Mobile Bottom Cart Bar
                SafeArea(
                  top: false,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: const Border(top: BorderSide(color: AppTheme.borderLight)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          offset: const Offset(0, -3),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: _showMobileCartSheet,
                            child: Row(
                              children: [
                                Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: AppTheme.primaryGreenSoft,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: const Icon(Icons.shopping_cart_rounded, color: AppTheme.primaryGreen, size: 22),
                                    ),
                                    if (pos.itemCount > 0)
                                      Positioned(
                                        top: -4,
                                        right: -4,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                          decoration: const BoxDecoration(color: AppTheme.accentOrange, shape: BoxShape.circle),
                                          child: Text(
                                            '${pos.itemCount}',
                                            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Flexible(
                                            child: Text(
                                              'Keranjang (${pos.totalUnitsCount.toInt()} item)',
                                              style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                                              overflow: TextOverflow.ellipsis,
                                              maxLines: 1,
                                            ),
                                          ),
                                          const Icon(Icons.keyboard_arrow_up_rounded, size: 15, color: AppTheme.textMuted),
                                        ],
                                      ),
                                      Text(
                                        CurrencyHelper.format(pos.grandTotal),
                                        style: const TextStyle(
                                            fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.payment_rounded, size: 18),
                          label: const Text('BAYAR'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          ),
                          onPressed: pos.isEmpty ? null : _openPaymentFlow,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _CartPanelWidget extends StatelessWidget {
  final ScrollController? scrollController;
  final bool isModalSheet;
  final VoidCallback? onCloseModal;
  final VoidCallback onCheckoutPressed;
  final VoidCallback onPickCustomer;
  final VoidCallback onPickDiscount;
  final ValueChanged<String?> onCartError;

  const _CartPanelWidget({
    this.scrollController,
    required this.isModalSheet,
    this.onCloseModal,
    required this.onCheckoutPressed,
    required this.onPickCustomer,
    required this.onPickDiscount,
    required this.onCartError,
  });

  @override
  Widget build(BuildContext context) {
    final pos = Provider.of<PosProvider>(context);
    final productProv = Provider.of<ProductProvider>(context);

    return Container(
      color: Colors.white,
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 6),
            child: Row(
              children: [
                const Icon(Icons.shopping_bag_rounded, color: AppTheme.primaryGreen, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Keranjang (${pos.itemCount} Jenis)',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.pause_circle_outline, size: 16),
                  label: const Text('Tahan', style: TextStyle(fontSize: 12)),
                  onPressed: pos.isEmpty
                      ? null
                      : () {
                          pos.holdCurrentOrder();
                          if (isModalSheet && onCloseModal != null) onCloseModal!();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Pesanan berhasil ditahan sementara.')),
                          );
                        },
                ),
                if (isModalSheet && onCloseModal != null)
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: onCloseModal,
                  ),
              ],
            ),
          ),

          // Customer & Promo Shortcut Row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: onPickCustomer,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                      decoration: BoxDecoration(
                        color: AppTheme.lightGreyBg,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.borderLight),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.person_outline_rounded, size: 16, color: AppTheme.primaryGreen),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              pos.customerName,
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: onPickDiscount,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: pos.cartDiscount > 0 ? Colors.pink.shade50 : AppTheme.lightGreyBg,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: pos.cartDiscount > 0 ? Colors.pink.shade200 : AppTheme.borderLight),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.discount_outlined,
                            size: 15, color: pos.cartDiscount > 0 ? Colors.pink : AppTheme.textMuted),
                        const SizedBox(width: 4),
                        Text(
                          pos.cartDiscount > 0 ? 'Diskon Aktif' : 'Diskon/Promo',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: pos.cartDiscount > 0 ? Colors.pink : AppTheme.textDark,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 8),

          // Cart Item List (Visible [-] qty [+] manual input + delete + subtotal)
          Expanded(
            child: pos.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.shopping_cart_outlined, size: 46, color: AppTheme.textMuted),
                          SizedBox(height: 8),
                          Text('Keranjang belanja masih kosong',
                              style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
                        ],
                      ),
                    ),
                  )
                : ListView.separated(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    itemCount: pos.cartItems.length,
                    separatorBuilder: (_, __) => const Divider(height: 12),
                    itemBuilder: (context, index) {
                      final item = pos.cartItems[index];
                      final prod = productProv.findById(item.productId) ??
                          ProductModel(
                            id: item.productId,
                            code: item.productCode,
                            name: item.productName,
                            sellingPrice: item.unitPrice,
                            isService: item.isService,
                            stock: 999999,
                          );

                      return Column(
                        key: ValueKey('cart_${item.productId}_${item.unitName}'),
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  '${item.productName} — ${CurrencyHelper.format(item.unitPrice)}',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                              ),
                              IconButton(
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                icon: const Icon(Icons.delete_outline_rounded, size: 19, color: AppTheme.accentRed),
                                tooltip: 'Hapus Item',
                                onPressed: () => pos.removeItem(index),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              QuantityStepper(
                                value: item.qty,
                                minValue: 1,
                                compact: true,
                                allowDecimal: true,
                                unitLabel: item.unitName,
                                onChanged: (newQty) {
                                  final res = pos.updateItemQty(index, newQty, prod);
                                  if (!res.success) onCartError(res.message);
                                },
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  const Text('Subtotal', style: TextStyle(fontSize: 10, color: AppTheme.textMuted)),
                                  Text(
                                    CurrencyHelper.format(item.subtotal),
                                    style: const TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.primaryGreen,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
          ),

          // Totals Footer
          Container(
            padding: const EdgeInsets.all(14),
            decoration: const BoxDecoration(
              color: AppTheme.lightGreyBg,
              border: Border(top: BorderSide(color: AppTheme.borderLight)),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _totalRow('Subtotal', CurrencyHelper.format(pos.subtotal)),
                  if (pos.cartDiscount > 0)
                    _totalRow(
                      pos.selectedPromo != null ? 'Diskon (${pos.selectedPromo!.name})' : 'Diskon',
                      '-${CurrencyHelper.format(pos.cartDiscount)}',
                      color: Colors.pink,
                    ),
                  if (pos.taxAmount > 0)
                    _totalRow('Pajak (${pos.taxRate.toStringAsFixed(0)}%)', CurrencyHelper.format(pos.taxAmount)),
                  const Divider(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('TOTAL', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                      Text(
                        CurrencyHelper.format(pos.grandTotal),
                        style: const TextStyle(
                            fontSize: 19, fontWeight: FontWeight.bold, color: AppTheme.primaryGreen),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.payment_rounded),
                      label: const Text('PROSES PEMBAYARAN', style: TextStyle(fontSize: 15)),
                      onPressed: pos.isEmpty ? null : onCheckoutPressed,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _totalRow(String l, String r, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(l, style: TextStyle(fontSize: 12, color: color ?? AppTheme.textMuted)),
          Text(r, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color ?? AppTheme.textDark)),
        ],
      ),
    );
  }
}

class _ProductGridQtyControl extends StatefulWidget {
  final double qty;
  final String unitLabel;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;
  final bool Function(double newQty) onSetQty;

  const _ProductGridQtyControl({
    required this.qty,
    required this.unitLabel,
    required this.onDecrement,
    required this.onIncrement,
    required this.onSetQty,
  });

  @override
  State<_ProductGridQtyControl> createState() => _ProductGridQtyControlState();
}

class _ProductGridQtyControlState extends State<_ProductGridQtyControl> {
  late TextEditingController _ctrl;
  final FocusNode _focusNode = FocusNode();

  String _formatQty(double q) {
    if (q <= 0) return '0';
    return q == q.truncateToDouble() ? q.toInt().toString() : q.toStringAsFixed(1);
  }

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: _formatQty(widget.qty));
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus) {
        _commitTypedQty();
      } else {
        _ctrl.selection = TextSelection(baseOffset: 0, extentOffset: _ctrl.text.length);
      }
    });
  }

  @override
  void didUpdateWidget(covariant _ProductGridQtyControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focusNode.hasFocus && (oldWidget.qty != widget.qty || _ctrl.text != _formatQty(widget.qty))) {
      _ctrl.text = _formatQty(widget.qty);
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  void _commitTypedQty() {
    final normalized = _ctrl.text.trim().replaceAll(',', '.');
    final parsed = double.tryParse(normalized);
    if (parsed == null || parsed < 0) {
      _ctrl.text = _formatQty(widget.qty);
      return;
    }
    final ok = widget.onSetQty(parsed);
    if (!ok) {
      _ctrl.text = _formatQty(widget.qty);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasQty = widget.qty > 0;
    return Container(
      height: 30,
      decoration: BoxDecoration(
        color: hasQty ? AppTheme.primaryGreenSoft : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: hasQty ? AppTheme.primaryGreen.withValues(alpha: 0.45) : Colors.grey.shade300,
        ),
      ),
      child: Row(
        children: [
          InkWell(
            onTap: hasQty ? widget.onDecrement : null,
            borderRadius: const BorderRadius.horizontal(left: Radius.circular(7)),
            child: SizedBox(
              width: 28,
              height: 30,
              child: Icon(
                Icons.remove_rounded,
                size: 16,
                color: hasQty ? AppTheme.primaryGreen : Colors.grey.shade400,
              ),
            ),
          ),
          Expanded(
            child: TextField(
              controller: _ctrl,
              focusNode: _focusNode,
              textAlign: TextAlign.center,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: hasQty ? AppTheme.primaryGreen : AppTheme.textMuted,
              ),
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                filled: false,
              ),
              onSubmitted: (_) {
                _commitTypedQty();
                _focusNode.unfocus();
              },
            ),
          ),
          InkWell(
            onTap: widget.onIncrement,
            borderRadius: const BorderRadius.horizontal(right: Radius.circular(7)),
            child: Container(
              width: 28,
              height: 30,
              decoration: BoxDecoration(
                color: AppTheme.primaryGreen,
                borderRadius: const BorderRadius.horizontal(right: Radius.circular(7)),
              ),
              child: const Icon(Icons.add_rounded, size: 16, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
