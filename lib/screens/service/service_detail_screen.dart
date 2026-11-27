import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/product.dart';
import '../../models/service_order.dart';
import '../../providers/auth_provider.dart';
import '../../providers/cash_flow_provider.dart';
import '../../providers/printer_provider.dart';
import '../../providers/product_provider.dart';
import '../../providers/service_order_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/printer/printer_manager.dart';
import '../../services/whatsapp_service.dart';
import '../../utils/app_theme.dart';
import '../../utils/currency_format.dart';
import '../../utils/date_format.dart';
import 'service_form_screen.dart';

class ServiceDetailScreen extends StatefulWidget {
  final int orderId;

  const ServiceDetailScreen({super.key, required this.orderId});

  @override
  State<ServiceDetailScreen> createState() => _ServiceDetailScreenState();
}

class _ServiceDetailScreenState extends State<ServiceDetailScreen> {
  ServiceOrderModel? _order;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final ord = await Provider.of<ServiceOrderProvider>(context, listen: false)
        .getOrderDetail(widget.orderId);
    if (mounted) {
      setState(() {
        _order = ord;
        _loading = false;
      });
    }
  }

  void _addSparepartDialog() {
    final productProv = Provider.of<ProductProvider>(context, listen: false);
    final srvProv = Provider.of<ServiceOrderProvider>(context, listen: false);
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final physicalProducts = productProv.allProducts.where((p) => !p.isService && p.stock > 0).toList();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        title: const Text('Tambah Sparepart dari Stok'),
        content: SizedBox(
          width: AppBreakpoints.boundedDialogWidth(ctx, maxWidth: 420),
          height: (MediaQuery.sizeOf(ctx).height * 0.55).clamp(180.0, 360.0),
          child: physicalProducts.isEmpty
              ? const Center(child: Text('Tidak ada stok sparepart/produk tersedia.'))
              : ListView.builder(
                  itemCount: physicalProducts.length,
                  itemBuilder: (_, i) {
                    final ProductModel p = physicalProducts[i];
                    return ListTile(
                      title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      subtitle: Text('Stok: ${p.stock.toInt()} ${p.baseUnit} • ${CurrencyHelper.format(p.sellingPrice)}'),
                      onTap: () async {
                        Navigator.pop(ctx);
                        await srvProv.addPart(
                          widget.orderId,
                          ServicePartModel(
                            productId: p.id,
                            productName: p.name,
                            qty: 1,
                            unitName: p.baseUnit,
                            conversionFactor: 1.0,
                            unitPrice: p.sellingPrice,
                            costPrice: p.costPrice,
                            subtotal: p.sellingPrice,
                          ),
                        );
                        await productProv.loadProducts();
                        await auth.logAction('servis_part', 'Tambah sparepart ${p.name} ke ${_order?.ticketNumber}');
                        await _load();
                      },
                    );
                  },
                ),
        ),
      ),
    );
  }

  void _showPaymentDialog() {
    if (_order == null) return;
    final rem = _order!.remainingPayment;
    final amountCtrl = TextEditingController(text: rem > 0 ? rem.toInt().toString() : '0');
    String method = 'tunai';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDState) => AlertDialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          title: const Text('Pembayaran / Pelunasan Servis'),
          content: AppBreakpoints.scrollableDialogContent(
            context,
            maxWidth: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Total Tagihan: ${CurrencyHelper.format(_order!.totalCost)}'),
                Text('Sudah Dibayar: ${CurrencyHelper.format(_order!.paidAmount)}'),
                Text('Sisa Pembayaran: ${CurrencyHelper.format(rem)}',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.accentRed)),
                const SizedBox(height: 12),
                TextField(
                  controller: amountCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Nominal Bayar', prefixText: 'Rp '),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: method,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Metode Pembayaran'),
                  items: const [
                    DropdownMenuItem(value: 'tunai', child: Text('Tunai (Masuk Laci Kasir)', maxLines: 1, overflow: TextOverflow.ellipsis)),
                    DropdownMenuItem(value: 'qris', child: Text('QRIS', maxLines: 1, overflow: TextOverflow.ellipsis)),
                    DropdownMenuItem(value: 'transfer', child: Text('Transfer Bank', maxLines: 1, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) => setDState(() => method = v ?? 'tunai'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
            ElevatedButton(
              onPressed: () async {
                final val = double.tryParse(amountCtrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0.0;
                if (val <= 0) return;
                final cashFlow = Provider.of<CashFlowProvider>(context, listen: false);
                final auth = Provider.of<AuthProvider>(context, listen: false);
                await Provider.of<ServiceOrderProvider>(context, listen: false).payOrder(
                  orderId: widget.orderId,
                  amount: val,
                  paymentMethod: method,
                  shiftId: cashFlow.currentShift?.id,
                  cashierName: auth.currentUser?.name ?? 'Kasir',
                );
                await cashFlow.checkOpenShift();
                await auth.logAction('servis_bayar', 'Pembayaran servis ${_order!.ticketNumber}: ${CurrencyHelper.format(val)} ($method)');
                if (ctx.mounted) Navigator.pop(ctx);
                await _load();
              },
              child: const Text('Catat Pembayaran'),
            ),
          ],
        ),
      ),
    ).then((_) => amountCtrl.dispose());
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_order == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Detail Servis')),
        body: const Center(child: Text('Tiket servis tidak ditemukan.')),
      );
    }

    final o = _order!;
    final settings = Provider.of<SettingsProvider>(context);
    final printerProv = Provider.of<PrinterProvider>(context);
    final srvProv = Provider.of<ServiceOrderProvider>(context, listen: false);
    final productProv = Provider.of<ProductProvider>(context, listen: false);
    final auth = Provider.of<AuthProvider>(context, listen: false);

    return Scaffold(
      appBar: AppBar(
        title: Text(o.ticketNumber),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_rounded),
            tooltip: 'Edit Data & Biaya Jasa',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => ServiceFormScreen(existingOrder: o)),
              ).then((_) => _load());
            },
          ),
          IconButton(
            icon: const Icon(Icons.print_rounded),
            tooltip: 'Cetak Nota Servis',
            onPressed: () async {
              final res = await PrinterManager.printServiceNote(
                printer: printerProv.defaultPrinter,
                order: o,
                storeName: settings.storeName,
                storeAddress: settings.storeAddress,
                storePhone: settings.storePhone,
                receiptConfig: settings.receiptConfig,
                logoPath: settings.logoPath,
              );
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res.message)));
              }
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 740),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Status Card
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: AppTheme.cardDecoration(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Update Status Pengerjaan:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: o.status,
                        isExpanded: true,
                        decoration: const InputDecoration(isDense: true),
                        items: ServiceStatus.all
                            .map((s) => DropdownMenuItem(
                                  value: s,
                                  child: Text(ServiceStatus.label(s), maxLines: 1, overflow: TextOverflow.ellipsis),
                                ))
                            .toList(),
                        onChanged: (newSt) async {
                          if (newSt == null || newSt == o.status) return;
                          await srvProv.changeStatus(o.id!, newSt);
                          if (newSt == ServiceStatus.dibatalkan) {
                            await productProv.loadProducts();
                          }
                          await auth.logAction('servis_status', 'Ubah status ${o.ticketNumber} -> ${ServiceStatus.label(newSt)}');
                          await _load();
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Customer & Device Card
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: AppTheme.cardDecoration(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text('${o.deviceType} ${o.brand} ${o.model}',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          ),
                          const SizedBox(width: 8),
                          if (o.customerPhone.isNotEmpty)
                            OutlinedButton.icon(
                              icon: const Icon(Icons.share_rounded, size: 16, color: Colors.green),
                              label: const Text('Kabar WA', style: TextStyle(fontSize: 12)),
                              onPressed: () {
                                WhatsAppService.sendServiceUpdateToCustomer(
                                  order: o,
                                  storeName: settings.storeName,
                                  storePhone: settings.storePhone,
                                );
                              },
                            ),
                        ],
                      ),
                      const Divider(),
                      Text('Pelanggan : ${o.customerName} (${o.customerPhone})'),
                      Text('IMEI / SN : ${o.imeiSn.isEmpty ? "-" : o.imeiSn}'),
                      Text('Kelengkapan: ${o.accessories.isEmpty ? "-" : o.accessories}'),
                      Text('Kondisi   : ${o.physicalCondition.isEmpty ? "-" : o.physicalCondition}'),
                      Text('Keluhan   : ${o.complaint}', style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text('Teknisi   : ${o.technicianName}'),
                      Text('Masuk     : ${DateHelper.formatFull(o.createdAt)}',
                          style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                      if (o.photoPaths.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 80,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: o.photoPaths.length,
                            separatorBuilder: (_, __) => const SizedBox(width: 8),
                            itemBuilder: (_, i) {
                              final f = File(o.photoPaths[i]);
                              return ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: SizedBox(
                                  width: 80,
                                  height: 80,
                                  child: f.existsSync() ? Image.file(f, fit: BoxFit.cover) : const Icon(Icons.image),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Spareparts Used
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: AppTheme.cardDecoration(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Sparepart Digunakan (Otomatis Potong Stok):',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                          TextButton.icon(
                            onPressed: _addSparepartDialog,
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Tambah Part'),
                          ),
                        ],
                      ),
                      if (o.parts.isEmpty)
                        const Text('Belum ada sparepart dipakai.', style: TextStyle(fontSize: 12, color: AppTheme.textMuted))
                      else
                        ...o.parts.map((p) => ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: Text(p.productName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                              subtitle: Text('${p.qty.toInt()} ${p.unitName} x ${CurrencyHelper.format(p.unitPrice)}'),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(CurrencyHelper.format(p.subtotal),
                                      style: const TextStyle(fontWeight: FontWeight.bold)),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, color: AppTheme.accentRed, size: 18),
                                    onPressed: () async {
                                      await srvProv.removePart(p.id!, o.id!);
                                      await productProv.loadProducts();
                                      await _load();
                                    },
                                  ),
                                ],
                              ),
                            )),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Financial Summary
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: AppTheme.cardDecoration(),
                  child: Column(
                    children: [
                      _row('Estimasi Awal', CurrencyHelper.format(o.estimatedCost)),
                      _row('Biaya Jasa Teknisi', CurrencyHelper.format(o.serviceFee)),
                      _row('Total Sparepart', CurrencyHelper.format(o.computedPartsTotal)),
                      const Divider(),
                      _row('TOTAL BIAYA SERVIS', CurrencyHelper.format(o.totalCost), bold: true),
                      _row('DP / Sudah Dibayar', CurrencyHelper.format(o.paidAmount)),
                      _row(
                        'SISA PEMBAYARAN',
                        CurrencyHelper.format(o.remainingPayment),
                        bold: true,
                        color: o.remainingPayment > 0 ? AppTheme.accentRed : AppTheme.success,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                await PrinterManager.printServiceNote(
                                  printer: printerProv.defaultPrinter,
                                  order: o,
                                  storeName: settings.storeName,
                                  storeAddress: settings.storeAddress,
                                  storePhone: settings.storePhone,
                                  receiptConfig: settings.receiptConfig,
                                  logoPath: settings.logoPath,
                                );
                              },
                              icon: const Icon(Icons.print_rounded),
                              label: const Text('Cetak Nota Servis'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _showPaymentDialog,
                              icon: const Icon(Icons.payments_rounded),
                              label: const Text('Bayar / Pelunasan'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(String l, String r, {bool bold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(l, style: TextStyle(fontSize: bold ? 13.5 : 12.5, fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
          Text(r, style: TextStyle(fontSize: bold ? 14.5 : 12.5, fontWeight: bold ? FontWeight.bold : FontWeight.w600, color: color)),
        ],
      ),
    );
  }
}
