import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../models/receipt_config.dart';
import '../../models/transaction.dart';
import '../../models/transaction_item.dart';
import '../../providers/printer_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/printer/printer_manager.dart';
import '../../utils/app_theme.dart';
import '../../utils/currency_format.dart';
import '../../utils/date_format.dart';
import '../../widgets/quantity_stepper.dart';
import 'printer_management_screen.dart';

class ReceiptSettingsScreen extends StatefulWidget {
  const ReceiptSettingsScreen({super.key});

  @override
  State<ReceiptSettingsScreen> createState() => _ReceiptSettingsScreenState();
}

class _ReceiptSettingsScreenState extends State<ReceiptSettingsScreen> {
  late ReceiptConfigModel _cfg;
  late TextEditingController _warrantyCtrl;
  late TextEditingController _returnCtrl;
  late TextEditingController _footerCtrl;

  @override
  void initState() {
    super.initState();
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    _cfg = settings.receiptConfig;
    _warrantyCtrl = TextEditingController(text: _cfg.warrantyInfo);
    _returnCtrl = TextEditingController(text: _cfg.returnPolicy);
    _footerCtrl = TextEditingController(text: _cfg.footerText);
  }

  @override
  void dispose() {
    _warrantyCtrl.dispose();
    _returnCtrl.dispose();
    _footerCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final updated = _cfg.copyWith(
      warrantyInfo: _warrantyCtrl.text.trim(),
      returnPolicy: _returnCtrl.text.trim(),
      footerText: _footerCtrl.text.trim(),
    );
    await Provider.of<SettingsProvider>(context, listen: false).updateReceiptConfig(updated);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Pengaturan struk berhasil disimpan!')),
    );
  }

  TransactionModel get _sampleTransaction => TransactionModel(
        invoiceNumber: 'INV-20261125-8821',
        date: DateTime.now(),
        cashierId: 1,
        cashierName: 'Kasir Demo',
        customerName: 'Bapak Hendra',
        subtotal: 79000,
        discountTotal: 4000,
        grandTotal: 75000,
        paymentMethod: 'tunai',
        amountPaid: 100000,
        changeAmount: 25000,
        items: [
          TransactionItemModel(
            productId: 1,
            productCode: 'PRD-001',
            productName: 'Minyak Goreng Sania 2L',
            unitName: 'Pcs',
            qty: 2,
            unitPrice: 34500,
            subtotal: 69000,
          ),
          TransactionItemModel(
            productId: 4,
            productCode: 'SRV-001',
            productName: 'Jasa Antar Barang',
            unitName: 'Trip',
            qty: 1,
            unitPrice: 10000,
            subtotal: 10000,
            isService: true,
          ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context);
    final printerProv = Provider.of<PrinterProvider>(context);
    final isWide = AppBreakpoints.isTablet(context);

    final formWidget = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: AppTheme.cardDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Template & Format Kertas', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: _cfg.template,
                decoration: const InputDecoration(labelText: 'Template Struk'),
                items: ReceiptTemplateType.all
                    .map((t) => DropdownMenuItem(value: t, child: Text(ReceiptTemplateType.label(t))))
                    .toList(),
                onChanged: (v) {
                  if (v == null) return;
                  setState(() {
                    _cfg = _cfg.copyWith(template: v);
                    if (v == ReceiptTemplateType.minimalist) {
                      _cfg = _cfg.copyWith(showLogo: false, showAddress: false, showQrInvoice: false);
                    } else if (v == ReceiptTemplateType.phoneCounter || v == ReceiptTemplateType.service) {
                      _cfg = _cfg.copyWith(showLogo: true, showCustomer: true, showQrInvoice: true);
                    } else {
                      _cfg = _cfg.copyWith(showLogo: true, showAddress: true, showQrInvoice: true);
                    }
                  });
                },
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _cfg.paperSize,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Format Kertas'),
                      items: const [
                        DropdownMenuItem(value: '58mm', child: Text('Thermal 58 mm', overflow: TextOverflow.ellipsis)),
                        DropdownMenuItem(value: '80mm', child: Text('Thermal 80 mm', overflow: TextOverflow.ellipsis)),
                        DropdownMenuItem(value: 'a4', child: Text('Laser A4', overflow: TextOverflow.ellipsis)),
                        DropdownMenuItem(value: 'continuous', child: Text('Continuous Form', overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: (v) => setState(() => _cfg = _cfg.copyWith(paperSize: v ?? _cfg.paperSize)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _cfg.fontSize,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Ukuran Font'),
                      items: const [
                        DropdownMenuItem(value: 'small', child: Text('Kecil', overflow: TextOverflow.ellipsis)),
                        DropdownMenuItem(value: 'normal', child: Text('Sedang', overflow: TextOverflow.ellipsis)),
                        DropdownMenuItem(value: 'large', child: Text('Besar', overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: (v) => setState(() => _cfg = _cfg.copyWith(fontSize: v ?? _cfg.fontSize)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _cfg.headerAlignment,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Perataan Header'),
                      items: const [
                        DropdownMenuItem(value: 'center', child: Text('Tengah (Center)', overflow: TextOverflow.ellipsis)),
                        DropdownMenuItem(value: 'left', child: Text('Rata Kiri (Left)', overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: (v) => setState(() => _cfg = _cfg.copyWith(headerAlignment: v ?? _cfg.headerAlignment)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _cfg.dividerStyle,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Garis Pemisah'),
                      items: const [
                        DropdownMenuItem(value: '-', child: Text('Garis Putus (----)', overflow: TextOverflow.ellipsis)),
                        DropdownMenuItem(value: '=', child: Text('Garis Ganda (====)', overflow: TextOverflow.ellipsis)),
                        DropdownMenuItem(value: '*', child: Text('Bintang (****)', overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: (v) => setState(() => _cfg = _cfg.copyWith(dividerStyle: v ?? _cfg.dividerStyle)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Jumlah Salinan Cetak:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  QuantityStepper(
                    value: _cfg.copyCount.toDouble(),
                    minValue: 1,
                    maxValue: 5,
                    compact: true,
                    onChanged: (v) => setState(() => _cfg = _cfg.copyWith(copyCount: v.toInt())),
                  ),
                ],
              ),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('Cetak Otomatis Setelah Pembayaran Berhasil'),
                value: _cfg.autoPrint,
                onChanged: (v) => setState(() => _cfg = _cfg.copyWith(autoPrint: v)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Field visibility toggles
        Container(
          padding: const EdgeInsets.all(14),
          decoration: AppTheme.cardDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Elemen yang Ditampilkan di Struk', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              const SizedBox(height: 4),
              SwitchListTile(dense: true, contentPadding: EdgeInsets.zero, title: const Text('Logo Toko'), value: _cfg.showLogo, onChanged: (v) => setState(() => _cfg = _cfg.copyWith(showLogo: v))),
              if (_cfg.showLogo)
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Sembunyikan Nama Toko Jika Logo Ditampilkan'),
                  subtitle: const Text(
                    'Menghemat ruang kertas thermal ketika logo toko aktif & termuat',
                    style: TextStyle(fontSize: 11),
                  ),
                  value: _cfg.hideStoreNameWithLogo,
                  onChanged: (v) => setState(() => _cfg = _cfg.copyWith(hideStoreNameWithLogo: v)),
                ),
              SwitchListTile(dense: true, contentPadding: EdgeInsets.zero, title: const Text('Alamat & Telepon Toko'), value: _cfg.showAddress, onChanged: (v) => setState(() => _cfg = _cfg.copyWith(showAddress: v, showPhone: v))),
              SwitchListTile(dense: true, contentPadding: EdgeInsets.zero, title: const Text('Nama Kasir'), value: _cfg.showCashier, onChanged: (v) => setState(() => _cfg = _cfg.copyWith(showCashier: v))),
              SwitchListTile(dense: true, contentPadding: EdgeInsets.zero, title: const Text('Informasi Pelanggan'), value: _cfg.showCustomer, onChanged: (v) => setState(() => _cfg = _cfg.copyWith(showCustomer: v))),
              SwitchListTile(dense: true, contentPadding: EdgeInsets.zero, title: const Text('Harga Satuan & Quantity'), value: _cfg.showUnitPrice, onChanged: (v) => setState(() => _cfg = _cfg.copyWith(showUnitPrice: v, showQty: v))),
              SwitchListTile(dense: true, contentPadding: EdgeInsets.zero, title: const Text('Rincian Diskon'), value: _cfg.showDiscount, onChanged: (v) => setState(() => _cfg = _cfg.copyWith(showDiscount: v))),
              SwitchListTile(dense: true, contentPadding: EdgeInsets.zero, title: const Text('Metode Bayar, Tunai & Kembalian'), value: _cfg.showPaidAndChange, onChanged: (v) => setState(() => _cfg = _cfg.copyWith(showPaymentMethod: v, showPaidAndChange: v))),
              SwitchListTile(dense: true, contentPadding: EdgeInsets.zero, title: const Text('QR Code Transaksi di Footer'), value: _cfg.showQrInvoice, onChanged: (v) => setState(() => _cfg = _cfg.copyWith(showQrInvoice: v))),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Warranty & Footer text
        Container(
          padding: const EdgeInsets.all(14),
          decoration: AppTheme.cardDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Teks Informasi Garansi, Retur & Footer', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              const SizedBox(height: 10),
              TextField(
                controller: _warrantyCtrl,
                decoration: const InputDecoration(
                  labelText: 'Informasi Garansi (Opsional)',
                  hintText: 'Contoh: Garansi servis/unit 7 hari sesuai ketentuan.',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _returnCtrl,
                decoration: const InputDecoration(labelText: 'Informasi Retur / Penukaran'),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _footerCtrl,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Footer Ucapan Struk'),
                onChanged: (_) => setState(() {}),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.print_rounded),
                label: const Text('Test Print Struk'),
                onPressed: () async {
                  final liveCfg = _cfg.copyWith(
                    warrantyInfo: _warrantyCtrl.text.trim(),
                    returnPolicy: _returnCtrl.text.trim(),
                    footerText: _footerCtrl.text.trim(),
                  );
                  final res = await PrinterManager.printTransactionReceipt(
                    printer: printerProv.defaultPrinter,
                    transaction: _sampleTransaction,
                    storeName: settings.storeName,
                    storeAddress: settings.storeAddress,
                    storePhone: settings.storePhone,
                    receiptConfig: liveCfg,
                    logoPath: settings.logoPath,
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res.message)));
                  }
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton.icon(
                icon: const Icon(Icons.save_rounded),
                label: const Text('Simpan Pengaturan'),
                onPressed: _save,
              ),
            ),
          ],
        ),
      ],
    );

    final previewWidget = Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: _cfg.headerAlignment == 'left'
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Pratinjau Struk', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textMuted)),
              TextButton.icon(
                icon: const Icon(Icons.print_outlined, size: 16),
                label: Text(printerProv.defaultPrinter?.name ?? 'Pilih Printer', style: const TextStyle(fontSize: 11)),
                onPressed: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const PrinterManagementScreen()));
                },
              ),
            ],
          ),
          const Divider(),
          if (_cfg.showLogo && settings.logoPath.isNotEmpty && File(settings.logoPath).existsSync()) ...[
            SizedBox(height: 44, child: Image.file(File(settings.logoPath), fit: BoxFit.contain)),
            const SizedBox(height: 4),
          ],
          if (!(_cfg.showLogo &&
              _cfg.hideStoreNameWithLogo &&
              settings.logoPath.isNotEmpty &&
              File(settings.logoPath).existsSync()))
            Text(
              settings.storeName,
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: _cfg.basePdfFontSize + 5),
              textAlign: _cfg.headerAlignment == 'left' ? TextAlign.left : TextAlign.center,
            ),
          if (_cfg.showAddress)
            Text(settings.storeAddress, style: TextStyle(fontSize: _cfg.basePdfFontSize + 1, color: AppTheme.textMuted)),
          if (_cfg.showPhone)
            Text('Telp: ${settings.storePhone}', style: TextStyle(fontSize: _cfg.basePdfFontSize + 1, color: AppTheme.textMuted)),
          Text(_cfg.dividerStyle * 28, style: const TextStyle(color: AppTheme.textMuted)),
          Align(
            alignment: Alignment.centerLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('No. Nota: ${_sampleTransaction.invoiceNumber}', style: TextStyle(fontSize: _cfg.basePdfFontSize + 1)),
                Text('Tanggal : ${DateHelper.formatReceipt(_sampleTransaction.date)}', style: TextStyle(fontSize: _cfg.basePdfFontSize + 1)),
                if (_cfg.showCashier)
                  Text('Kasir   : ${_sampleTransaction.cashierName}', style: TextStyle(fontSize: _cfg.basePdfFontSize + 1)),
                if (_cfg.showCustomer)
                  Text('Pelanggan: ${_sampleTransaction.customerName}', style: TextStyle(fontSize: _cfg.basePdfFontSize + 1)),
              ],
            ),
          ),
          Text(_cfg.dividerStyle * 28, style: const TextStyle(color: AppTheme.textMuted)),
          for (final item in _sampleTransaction.items)
            Padding(
              padding: EdgeInsets.symmetric(vertical: _cfg.lineSpacing),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      _cfg.showUnitPrice
                          ? '${item.productName}\n  ${item.qty.toInt()} ${item.unitName} x ${CurrencyHelper.format(item.unitPrice)}'
                          : item.productName,
                      style: TextStyle(fontSize: _cfg.basePdfFontSize + 1),
                    ),
                  ),
                  Text(CurrencyHelper.format(item.subtotal),
                      style: TextStyle(fontSize: _cfg.basePdfFontSize + 1, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          Text(_cfg.dividerStyle * 28, style: const TextStyle(color: AppTheme.textMuted)),
          if (_cfg.showTotal) ...[
            if (_cfg.showDiscount)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Diskon', style: TextStyle(fontSize: _cfg.basePdfFontSize + 1)),
                  Text('-${CurrencyHelper.format(_sampleTransaction.discountTotal)}',
                      style: TextStyle(fontSize: _cfg.basePdfFontSize + 1)),
                ],
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('TOTAL', style: TextStyle(fontWeight: FontWeight.bold, fontSize: _cfg.basePdfFontSize + 3)),
                Text(CurrencyHelper.format(_sampleTransaction.grandTotal),
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: _cfg.basePdfFontSize + 3, color: AppTheme.primaryGreen)),
              ],
            ),
          ],
          if (_cfg.showPaidAndChange) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Bayar (TUNAI)', style: TextStyle(fontSize: _cfg.basePdfFontSize + 1)),
                Text(CurrencyHelper.format(_sampleTransaction.amountPaid), style: TextStyle(fontSize: _cfg.basePdfFontSize + 1)),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Kembali', style: TextStyle(fontSize: _cfg.basePdfFontSize + 1)),
                Text(CurrencyHelper.format(_sampleTransaction.changeAmount), style: TextStyle(fontSize: _cfg.basePdfFontSize + 1)),
              ],
            ),
          ],
          if (_cfg.showQrInvoice) ...[
            const SizedBox(height: 8),
            QrImageView(data: _sampleTransaction.qrCodePayload, size: 68),
          ],
          if (_warrantyCtrl.text.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(_warrantyCtrl.text.trim(),
                style: TextStyle(fontSize: _cfg.basePdfFontSize, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
          ],
          if (_returnCtrl.text.trim().isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(_returnCtrl.text.trim(),
                style: TextStyle(fontSize: _cfg.basePdfFontSize, color: AppTheme.textMuted), textAlign: TextAlign.center),
          ],
          if (_footerCtrl.text.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(_footerCtrl.text.trim(),
                style: TextStyle(fontSize: _cfg.basePdfFontSize, color: AppTheme.textMuted), textAlign: TextAlign.center),
          ],
        ],
      ),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Pengaturan Template & Struk')),
      body: isWide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: SingleChildScrollView(padding: const EdgeInsets.all(16), child: formWidget),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  flex: 2,
                  child: SingleChildScrollView(padding: const EdgeInsets.all(16), child: previewWidget),
                ),
              ],
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  previewWidget,
                  const SizedBox(height: 16),
                  formWidget,
                ],
              ),
            ),
    );
  }
}
