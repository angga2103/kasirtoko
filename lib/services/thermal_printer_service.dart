import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/transaction.dart';
import '../models/product.dart';
import '../utils/currency_format.dart';
import '../utils/date_format.dart';

class ThermalPrinterService {
  // ESC/POS Command to open cash drawer via RJ11 pulse
  static List<int> get openCashDrawerCommand => [0x1B, 0x70, 0x00, 0x19, 0xFA];

  // Print Thermal Struk using PDF & Printing package (Compatible with all 58mm & 80mm Bluetooth/USB printers)
  static Future<void> printReceipt({
    required TransactionModel transaction,
    required String storeName,
    required String storeAddress,
    required String storePhone,
    required String footerMessage,
    String paperSize = '58mm',
  }) async {
    final doc = pw.Document();

    final is80mm = paperSize == '80mm';
    final double pageWidth = is80mm ? 72 * PdfPageFormat.mm : 58 * PdfPageFormat.mm;
    final pageFormat = PdfPageFormat(pageWidth, double.infinity, marginAll: 2 * PdfPageFormat.mm);

    doc.addPage(
      pw.Page(
        pageFormat: pageFormat,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              // Store Header
              pw.Text(
                storeName,
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13),
                textAlign: pw.TextAlign.center,
              ),
              if (storeAddress.isNotEmpty)
                pw.Text(
                  storeAddress,
                  style: const pw.TextStyle(fontSize: 8),
                  textAlign: pw.TextAlign.center,
                ),
              if (storePhone.isNotEmpty)
                pw.Text(
                  'Telp: $storePhone',
                  style: const pw.TextStyle(fontSize: 8),
                  textAlign: pw.TextAlign.center,
                ),
              pw.Divider(thickness: 0.5),

              // Transaction Info
              pw.Align(
                alignment: pw.Alignment.centerLeft,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('No. Nota : ${transaction.invoiceNumber}',
                        style: const pw.TextStyle(fontSize: 8)),
                    pw.Text('Tanggal  : ${DateHelper.formatReceipt(transaction.date)}',
                        style: const pw.TextStyle(fontSize: 8)),
                    pw.Text('Kasir    : ${transaction.cashierName}',
                        style: const pw.TextStyle(fontSize: 8)),
                    if (transaction.customerName != 'Pelanggan Umum')
                      pw.Text('Pelanggan: ${transaction.customerName}',
                          style: const pw.TextStyle(fontSize: 8)),
                  ],
                ),
              ),
              pw.Divider(thickness: 0.5),

              // Item List
              pw.Column(
                children: transaction.items.map((item) {
                  return pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          item.productName,
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8.5),
                        ),
                        pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                          children: [
                            pw.Text(
                              '${item.qty.toStringAsFixed(item.qty.truncateToDouble() == item.qty ? 0 : 1)} ${item.unitName} x ${CurrencyHelper.format(item.unitPrice)}',
                              style: const pw.TextStyle(fontSize: 8),
                            ),
                            pw.Text(
                              CurrencyHelper.format(item.subtotal),
                              style: const pw.TextStyle(fontSize: 8),
                            ),
                          ],
                        ),
                        if (item.discount > 0)
                          pw.Text(
                            '  Diskon: -${CurrencyHelper.format(item.discount)}',
                            style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700),
                          ),
                      ],
                    ),
                  );
                }).toList(),
              ),
              pw.Divider(thickness: 0.5),

              // Totals
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Subtotal', style: const pw.TextStyle(fontSize: 8.5)),
                  pw.Text(CurrencyHelper.format(transaction.subtotal),
                      style: const pw.TextStyle(fontSize: 8.5)),
                ],
              ),
              if (transaction.discountTotal > 0)
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Total Diskon', style: const pw.TextStyle(fontSize: 8.5)),
                    pw.Text('-${CurrencyHelper.format(transaction.discountTotal)}',
                        style: const pw.TextStyle(fontSize: 8.5)),
                  ],
                ),
              pw.SizedBox(height: 2),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('TOTAL',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                  pw.Text(CurrencyHelper.format(transaction.grandTotal),
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                ],
              ),
              pw.Divider(thickness: 0.5),

              // Payment Details
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Metode Bayar', style: const pw.TextStyle(fontSize: 8)),
                  pw.Text(transaction.paymentMethod.toUpperCase(),
                      style: const pw.TextStyle(fontSize: 8)),
                ],
              ),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Bayar', style: const pw.TextStyle(fontSize: 8)),
                  pw.Text(CurrencyHelper.format(transaction.amountPaid),
                      style: const pw.TextStyle(fontSize: 8)),
                ],
              ),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Kembali', style: const pw.TextStyle(fontSize: 8)),
                  pw.Text(CurrencyHelper.format(transaction.changeAmount),
                      style: const pw.TextStyle(fontSize: 8)),
                ],
              ),
              pw.SizedBox(height: 6),

              // QR Code in Footer for instant transaction lookup / return
              pw.BarcodeWidget(
                barcode: pw.Barcode.qrCode(),
                data: transaction.qrCodePayload,
                width: 45,
                height: 45,
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                'Scan QR untuk Retur / Cek Nota',
                style: const pw.TextStyle(fontSize: 7),
                textAlign: pw.TextAlign.center,
              ),
              pw.SizedBox(height: 6),

              // Footer Message
              if (footerMessage.isNotEmpty)
                pw.Text(
                  footerMessage,
                  style: const pw.TextStyle(fontSize: 7.5),
                  textAlign: pw.TextAlign.center,
                ),
              pw.SizedBox(height: 10),
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => doc.save(),
      name: 'Struk_${transaction.invoiceNumber}',
    );
  }

  // Print Barcode & QR Label for thermal sticker printer
  static Future<void> printProductLabel({
    required ProductModel product,
    required String storeName,
    required int copyCount,
    bool isQrCode = false,
    bool showPrice = true,
    bool showStoreName = true,
    double labelWidthMm = 40,
    double labelHeightMm = 30,
  }) async {
    final doc = pw.Document();

    final pageFormat = PdfPageFormat(
      labelWidthMm * PdfPageFormat.mm,
      labelHeightMm * PdfPageFormat.mm,
      marginAll: 1.5 * PdfPageFormat.mm,
    );

    for (int i = 0; i < copyCount; i++) {
      doc.addPage(
        pw.Page(
          pageFormat: pageFormat,
          build: (pw.Context context) {
            final barcodeData = product.barcode.isNotEmpty ? product.barcode : product.code;

            return pw.Center(
              child: pw.Column(
                mainAxisAlignment: pw.MainAxisAlignment.center,
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  if (showStoreName && storeName.isNotEmpty)
                    pw.Text(
                      storeName,
                      style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold),
                      maxLines: 1,
                    ),
                  pw.Text(
                    product.name,
                    style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
                    maxLines: 1,
                    overflow: pw.TextOverflow.clip,
                    textAlign: pw.TextAlign.center,
                  ),
                  pw.SizedBox(height: 2),
                  if (isQrCode)
                    pw.BarcodeWidget(
                      barcode: pw.Barcode.qrCode(),
                      data: barcodeData,
                      width: 32,
                      height: 32,
                    )
                  else
                    pw.BarcodeWidget(
                      barcode: pw.Barcode.code128(),
                      data: barcodeData,
                      width: labelWidthMm * 2,
                      height: 18,
                      drawText: true,
                      textStyle: const pw.TextStyle(fontSize: 6.5),
                    ),
                  if (showPrice) ...[
                    pw.SizedBox(height: 2),
                    pw.Text(
                      CurrencyHelper.format(product.sellingPrice),
                      style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      );
    }

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => doc.save(),
      name: 'Label_${product.code}',
    );
  }
}
