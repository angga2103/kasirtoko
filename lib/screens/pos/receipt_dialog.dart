import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/transaction.dart';
import '../../providers/settings_provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/thermal_printer_service.dart';
import '../../services/whatsapp_service.dart';
import '../../utils/app_theme.dart';
import '../../utils/currency_format.dart';
import '../../utils/date_format.dart';

class ReceiptDialog extends StatelessWidget {
  final TransactionModel transaction;

  const ReceiptDialog({super.key, required this.transaction});

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final auth = Provider.of<AuthProvider>(context, listen: false);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              // Success Badge
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle_rounded, color: AppTheme.primaryGreen, size: 28),
                  SizedBox(width: 8),
                  Text(
                    'Transaksi Berhasil!',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primaryGreen),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Receipt Scrollable Preview
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey.shade300),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 4),
                    ],
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          settings.storeName,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        Text(
                          settings.storeAddress,
                          style: const TextStyle(fontSize: 10, color: AppTheme.textMuted),
                        ),
                        Text(
                          'Telp: ${settings.storePhone}',
                          style: const TextStyle(fontSize: 10, color: AppTheme.textMuted),
                        ),
                        const Divider(thickness: 0.8),

                        Align(
                          alignment: Alignment.centerLeft,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('No. Nota : ${transaction.invoiceNumber}',
                                  style: const TextStyle(fontSize: 10)),
                              Text('Tanggal  : ${DateHelper.formatFull(transaction.date)}',
                                  style: const TextStyle(fontSize: 10)),
                              Text('Kasir    : ${transaction.cashierName}',
                                  style: const TextStyle(fontSize: 10)),
                              if (transaction.customerName != 'Pelanggan Umum')
                                Text('Pelanggan: ${transaction.customerName}',
                                    style: const TextStyle(fontSize: 10)),
                            ],
                          ),
                        ),
                        const Divider(thickness: 0.8),

                        // Item List
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
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        Text(
                                          '${item.qty.toStringAsFixed(item.qty.truncateToDouble() == item.qty ? 0 : 1)} ${item.unitName} x ${CurrencyHelper.format(item.unitPrice)}',
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

                        // Totals
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
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Bayar (${transaction.paymentMethod.toUpperCase()})',
                                style: const TextStyle(fontSize: 10)),
                            Text(CurrencyHelper.format(transaction.amountPaid),
                                style: const TextStyle(fontSize: 10)),
                          ],
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Kembali', style: TextStyle(fontSize: 10)),
                            Text(CurrencyHelper.format(transaction.changeAmount),
                                style: const TextStyle(fontSize: 10)),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // QR Code in Footer
                        QrImageView(
                          data: transaction.qrCodePayload,
                          version: QrVersions.auto,
                          size: 72.0,
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Scan QR untuk Retur / Cek Nota',
                          style: TextStyle(fontSize: 9, color: AppTheme.textMuted),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          settings.receiptFooter,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 9, color: AppTheme.textMuted),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Action Buttons Row
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.print_rounded, size: 18),
                      label: const Text('Cetak Struk'),
                      onPressed: () async {
                        await ThermalPrinterService.printReceipt(
                          transaction: transaction,
                          storeName: settings.storeName,
                          storeAddress: settings.storeAddress,
                          storePhone: settings.storePhone,
                          footerMessage: settings.receiptFooter,
                          paperSize: settings.printerPaperSize,
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.share_rounded, size: 18),
                      label: const Text('Struk WA'),
                      onPressed: () {
                        _shareReceiptWhatsApp(context, settings);
                      },
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
                      onPressed: () {
                        auth.logAction('buka_laci', 'Buka laci kasir manual nota #${transaction.invoiceNumber}');
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Sinyal pulse RJ11 buka laci kasir terkirim.')),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryGreen),
                      onPressed: () => Navigator.pop(context),
                      child: const Text('TRANSAKSI BARU'),
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

  void _shareReceiptWhatsApp(BuildContext context, SettingsProvider settings) async {
    final phone = WhatsAppService.normalizePhone(transaction.customerPhone);
    final itemsText = transaction.items
        .map((i) =>
            '- ${i.productName} (${i.qty.toInt()} ${i.unitName}) : ${CurrencyHelper.format(i.subtotal)}')
        .join('\n');

    final message = '''
*STRUK BELANJA - ${settings.storeName}*
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
Terima kasih telah berbelanja di *${settings.storeName}*!
Simpan struk digital ini untuk bukti pembayaran.
''';

    if (phone.isNotEmpty) {
      final uri = Uri.parse('https://wa.me/$phone?text=${Uri.encodeComponent(message)}');
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nomor WA pelanggan tidak diisi saat pembayaran.')),
      );
    }
  }
}
