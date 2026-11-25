import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/receipt_config.dart';
import '../../models/transaction.dart';
import '../../providers/auth_provider.dart';
import '../../providers/printer_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/printer/printer_manager.dart';
import '../../services/whatsapp_service.dart';
import '../../utils/app_theme.dart';
import '../../utils/currency_format.dart';
import '../../utils/date_format.dart';

class ReceiptDialog extends StatelessWidget {
  final TransactionModel transaction;
  final bool isReprint;

  const ReceiptDialog({
    super.key,
    required this.transaction,
    this.isReprint = false,
  });

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final printerProv = Provider.of<PrinterProvider>(context, listen: false);

    // Use historical snapshot when reprinting if available!
    final snap = transaction.snapshotMap;
    final storeName = (snap?['store_name'] as String?)?.isNotEmpty == true
        ? snap!['store_name'] as String
        : settings.storeName;
    final storeAddress = (snap?['store_address'] as String?)?.isNotEmpty == true
        ? snap!['store_address'] as String
        : settings.storeAddress;
    final storePhone = (snap?['store_phone'] as String?)?.isNotEmpty == true
        ? snap!['store_phone'] as String
        : settings.storePhone;
    final ReceiptConfigModel config = snap?['receipt_config'] is Map
        ? ReceiptConfigModel.fromMap(Map<String, dynamic>.from(snap!['receipt_config'] as Map))
        : settings.receiptConfig;

    final hasLogo = config.showLogo &&
        settings.logoPath.isNotEmpty &&
        File(settings.logoPath).existsSync();

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440, maxHeight: 700),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    isReprint ? Icons.receipt_long_rounded : Icons.check_circle_rounded,
                    color: AppTheme.primaryGreen,
                    size: 28,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isReprint ? 'Cetak Ulang Struk' : 'Transaksi Berhasil!',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primaryGreen),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: AppTheme.cardDecoration(),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: config.headerAlignment == 'left'
                          ? CrossAxisAlignment.start
                          : CrossAxisAlignment.center,
                      children: [
                        if (hasLogo) ...[
                          SizedBox(
                            height: 44,
                            child: Image.file(File(settings.logoPath), fit: BoxFit.contain),
                          ),
                          const SizedBox(height: 4),
                        ],
                        if (!(config.showLogo && config.hideStoreNameWithLogo && hasLogo))
                          Text(storeName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        if (config.showAddress && storeAddress.isNotEmpty)
                          Text(storeAddress, style: const TextStyle(fontSize: 10, color: AppTheme.textMuted)),
                        if (config.showPhone && storePhone.isNotEmpty)
                          Text('Telp: $storePhone', style: const TextStyle(fontSize: 10, color: AppTheme.textMuted)),
                        if (isReprint)
                          Container(
                            margin: const EdgeInsets.only(top: 4),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.amber.shade100,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text('SALINAN HISTORIS (CETAK ULANG)',
                                style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold)),
                          ),
                        const Divider(thickness: 0.8),

                        Align(
                          alignment: Alignment.centerLeft,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('No. Nota : ${transaction.invoiceNumber}', style: const TextStyle(fontSize: 10)),
                              Text('Tanggal  : ${DateHelper.formatFull(transaction.date)}',
                                  style: const TextStyle(fontSize: 10)),
                              if (config.showCashier)
                                Text('Kasir    : ${transaction.cashierName}', style: const TextStyle(fontSize: 10)),
                              if (config.showCustomer && transaction.customerName != 'Pelanggan Umum')
                                Text('Pelanggan: ${transaction.customerName}', style: const TextStyle(fontSize: 10)),
                            ],
                          ),
                        ),
                        const Divider(thickness: 0.8),

                        Column(
                          children: transaction.items.map((item) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item.productName,
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        if (config.showQty)
                                          Text(
                                            '${item.qty.toStringAsFixed(item.qty.truncateToDouble() == item.qty ? 0 : 1)} ${item.unitName}${config.showUnitPrice ? " x ${CurrencyHelper.format(item.unitPrice)}" : ""}',
                                            style: const TextStyle(fontSize: 10, color: AppTheme.textMuted),
                                          ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    CurrencyHelper.format(item.subtotal),
                                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                        const Divider(thickness: 0.8),

                        if (config.showTotal) ...[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Subtotal', style: TextStyle(fontSize: 10)),
                              Text(CurrencyHelper.format(transaction.subtotal), style: const TextStyle(fontSize: 10)),
                            ],
                          ),
                          if (config.showDiscount && transaction.discountTotal > 0)
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  transaction.promoName.isNotEmpty ? 'Diskon (${transaction.promoName})' : 'Diskon',
                                  style: const TextStyle(fontSize: 10, color: Colors.pink),
                                ),
                                Text('-${CurrencyHelper.format(transaction.discountTotal)}',
                                    style: const TextStyle(fontSize: 10, color: Colors.pink)),
                              ],
                            ),
                          if (transaction.taxAmount > 0)
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Pajak', style: TextStyle(fontSize: 10)),
                                Text(CurrencyHelper.format(transaction.taxAmount), style: const TextStyle(fontSize: 10)),
                              ],
                            ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('TOTAL', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                              Text(
                                CurrencyHelper.format(transaction.grandTotal),
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.primaryGreen),
                              ),
                            ],
                          ),
                        ],
                        if (config.showPaidAndChange) ...[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Bayar (${transaction.paymentMethod.toUpperCase()})',
                                  style: const TextStyle(fontSize: 10)),
                              Text(CurrencyHelper.format(transaction.amountPaid), style: const TextStyle(fontSize: 10)),
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Kembali', style: TextStyle(fontSize: 10)),
                              Text(CurrencyHelper.format(transaction.changeAmount), style: const TextStyle(fontSize: 10)),
                            ],
                          ),
                        ],

                        if (config.showQrInvoice) ...[
                          const SizedBox(height: 10),
                          QrImageView(data: transaction.qrCodePayload, version: QrVersions.auto, size: 70.0),
                          const SizedBox(height: 3),
                          const Text('Scan QR untuk Retur / Cek Nota',
                              style: TextStyle(fontSize: 9, color: AppTheme.textMuted)),
                        ],
                        if (config.warrantyInfo.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(config.warrantyInfo,
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold)),
                        ],
                        if (config.footerText.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(config.footerText,
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 9, color: AppTheme.textMuted)),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.print_rounded, size: 18),
                      label: Text(isReprint ? 'Cetak Ulang' : 'Cetak Struk'),
                      onPressed: () async {
                        final res = await PrinterManager.printTransactionReceipt(
                          printer: printerProv.defaultPrinter,
                          transaction: transaction,
                          storeName: storeName,
                          storeAddress: storeAddress,
                          storePhone: storePhone,
                          receiptConfig: config,
                          logoPath: settings.logoPath,
                          isReprint: isReprint,
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(res.message),
                              backgroundColor: res.success ? AppTheme.success : AppTheme.accentRed,
                            ),
                          );
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.share_rounded, size: 18),
                      label: const Text('Kirim WA'),
                      onPressed: () => _shareReceiptWhatsApp(context, storeName),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.point_of_sale_rounded, size: 18, color: AppTheme.accentOrange),
                      label: const Text('Buka Laci', style: TextStyle(color: AppTheme.accentOrange)),
                      onPressed: () async {
                        final thermal = printerProv.getPreferredPrinterFor('thermal');
                        final res = await PrinterManager.openCashDrawer(thermal);
                        await auth.logAction('buka_laci', 'Buka laci manual nota #${transaction.invoiceNumber} (${res.message})');
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(res.message),
                              backgroundColor: res.success ? AppTheme.success : AppTheme.accentOrange,
                            ),
                          );
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(isReprint ? 'TUTUP' : 'TRANSAKSI BARU'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _shareReceiptWhatsApp(BuildContext context, String storeName) async {
    final phone = WhatsAppService.normalizePhone(transaction.customerPhone);
    final itemsText = transaction.items
        .map((i) => '- ${i.productName} (${i.qty.toInt()} ${i.unitName}) : ${CurrencyHelper.format(i.subtotal)}')
        .join('\n');

    final message = '''
*STRUK BELANJA - $storeName*
No. Nota: *${transaction.invoiceNumber}*
Tanggal : ${DateHelper.formatReceipt(transaction.date)}
Kasir   : ${transaction.cashierName}
----------------------------------
$itemsText
----------------------------------
*TOTAL BELANJA : ${CurrencyHelper.format(transaction.grandTotal)}*
Bayar (${transaction.paymentMethod.toUpperCase()}) : ${CurrencyHelper.format(transaction.amountPaid)}
Kembali : ${CurrencyHelper.format(transaction.changeAmount)}
----------------------------------
Terima kasih telah berbelanja di *$storeName*!
''';

    if (phone.isNotEmpty) {
      final uri = Uri.parse('https://wa.me/$phone?text=${Uri.encodeComponent(message)}');
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nomor WA pelanggan belum diisi.')),
      );
    }
  }
}
