import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/product.dart';
import '../models/receipt_config.dart';
import '../models/transaction.dart';
import '../utils/currency_format.dart';
import '../utils/date_format.dart';
import 'printer/esc_pos_image_helper.dart';

class EscPosLabelItemAdapter {
  final String name;
  final String sku;
  final String barcodeData;
  final double price;
  final int copyCount;

  const EscPosLabelItemAdapter({
    required this.name,
    required this.sku,
    required this.barcodeData,
    required this.price,
    this.copyCount = 1,
  });
}

class ThermalPrinterService {
  // ESC/POS Command to open cash drawer via RJ11 pulse
  static List<int> get openCashDrawerCommand => [0x1B, 0x70, 0x00, 0x19, 0xFA];

  static Future<pw.MemoryImage?> _loadLogo(String? logoPath) async {
    final normalized = EscPosImageHelper.loadNormalizedPngBytes(logoPath, maxWidth: 360);
    if (normalized != null && normalized.isNotEmpty) {
      return pw.MemoryImage(normalized);
    }
    return null;
  }

  /// Backward-compatible receipt printer entry point
  static Future<void> printReceipt({
    required TransactionModel transaction,
    required String storeName,
    required String storeAddress,
    required String storePhone,
    required String footerMessage,
    String paperSize = '58mm',
    String? logoPath,
    bool isReprint = false,
  }) {
    return printReceiptWithConfig(
      transaction: transaction,
      storeName: storeName,
      storeAddress: storeAddress,
      storePhone: storePhone,
      config: ReceiptConfigModel(
        paperSize: paperSize,
        footerText: footerMessage,
      ),
      logoPath: logoPath,
      isReprint: isReprint,
    );
  }

  static Future<void> printReceiptWithConfig({
    required TransactionModel transaction,
    required String storeName,
    required String storeAddress,
    required String storePhone,
    required ReceiptConfigModel config,
    String? logoPath,
    bool isReprint = false,
  }) async {
    final doc = pw.Document();
    final logoImg = config.showLogo ? await _loadLogo(logoPath) : null;

    final isA4 = config.paperSize == 'a4';
    final is80mm = config.paperSize == '80mm';
    final PdfPageFormat pageFormat = isA4
        ? PdfPageFormat.a4
        : PdfPageFormat(
            (is80mm ? 72 : 58) * PdfPageFormat.mm,
            double.infinity,
            marginAll: 2.5 * PdfPageFormat.mm,
          );

    final baseFont = config.basePdfFontSize + (isA4 ? 2.0 : 0.0);
    final alignLeft = config.headerAlignment == 'left';
    final dividerLine = (config.dividerStyle.isNotEmpty ? config.dividerStyle : '-') *
        (isA4 ? 72 : (is80mm ? 42 : 30));

    final copyCount = isReprint ? 1 : config.copyCount.clamp(1, 5);

    for (int c = 0; c < copyCount; c++) {
      doc.addPage(
        pw.Page(
          pageFormat: pageFormat,
          margin: isA4 ? const pw.EdgeInsets.all(28) : null,
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: alignLeft ? pw.CrossAxisAlignment.start : pw.CrossAxisAlignment.center,
              children: [
                if (logoImg != null) ...[
                  pw.Container(
                    constraints: pw.BoxConstraints(
                      maxWidth: isA4 ? 96 : (is80mm ? 84 : 68),
                      maxHeight: isA4 ? 64 : 44,
                    ),
                    child: pw.Image(logoImg, fit: pw.BoxFit.contain),
                  ),
                  pw.SizedBox(height: 3),
                ],
                if (!(config.showLogo && config.hideStoreNameWithLogo && logoImg != null))
                  pw.Text(
                    storeName,
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: baseFont + 4),
                    textAlign: alignLeft ? pw.TextAlign.left : pw.TextAlign.center,
                  ),
                if (config.showAddress && storeAddress.isNotEmpty)
                  pw.Text(
                    storeAddress,
                    style: pw.TextStyle(fontSize: baseFont - 0.5),
                    textAlign: alignLeft ? pw.TextAlign.left : pw.TextAlign.center,
                  ),
                if (config.showPhone && storePhone.isNotEmpty)
                  pw.Text(
                    'Telp: $storePhone',
                    style: pw.TextStyle(fontSize: baseFont - 0.5),
                    textAlign: alignLeft ? pw.TextAlign.left : pw.TextAlign.center,
                  ),
                if (isReprint)
                  pw.Container(
                    margin: const pw.EdgeInsets.only(top: 3),
                    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.6)),
                    child: pw.Text('SALINAN / CETAK ULANG',
                        style: pw.TextStyle(fontSize: baseFont - 1, fontWeight: pw.FontWeight.bold)),
                  ),
                pw.Text(dividerLine, style: pw.TextStyle(fontSize: baseFont - 1, color: PdfColors.grey700)),

                pw.Align(
                  alignment: pw.Alignment.centerLeft,
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('No. Nota : ${transaction.invoiceNumber}', style: pw.TextStyle(fontSize: baseFont)),
                      pw.Text('Tanggal  : ${DateHelper.formatReceipt(transaction.date)}',
                          style: pw.TextStyle(fontSize: baseFont)),
                      if (config.showCashier)
                        pw.Text('Kasir    : ${transaction.cashierName}', style: pw.TextStyle(fontSize: baseFont)),
                      if (config.showCustomer && transaction.customerName != 'Pelanggan Umum')
                        pw.Text('Pelanggan: ${transaction.customerName}',
                            style: pw.TextStyle(fontSize: baseFont)),
                    ],
                  ),
                ),
                pw.Text(dividerLine, style: pw.TextStyle(fontSize: baseFont - 1, color: PdfColors.grey700)),

                // Items
                pw.Column(
                  children: transaction.items.map((item) {
                    final qtyStr = item.qty.toStringAsFixed(item.qty.truncateToDouble() == item.qty ? 0 : 1);
                    return pw.Padding(
                      padding: pw.EdgeInsets.symmetric(vertical: config.lineSpacing),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            item.productName,
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: baseFont),
                          ),
                          pw.Row(
                            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                            children: [
                              pw.Text(
                                config.showQty
                                    ? (config.showUnitPrice
                                        ? '$qtyStr ${item.unitName} x ${CurrencyHelper.format(item.unitPrice)}'
                                        : '$qtyStr ${item.unitName}')
                                    : '',
                                style: pw.TextStyle(fontSize: baseFont - 0.5),
                              ),
                              pw.Text(
                                CurrencyHelper.format(item.subtotal),
                                style: pw.TextStyle(fontSize: baseFont - 0.5, fontWeight: pw.FontWeight.bold),
                              ),
                            ],
                          ),
                          if (config.showDiscount && item.discount > 0)
                            pw.Text(
                              '  Diskon item: -${CurrencyHelper.format(item.discount)}',
                              style: pw.TextStyle(fontSize: baseFont - 1.2, color: PdfColors.grey700),
                            ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
                pw.Text(dividerLine, style: pw.TextStyle(fontSize: baseFont - 1, color: PdfColors.grey700)),

                if (config.showTotal) ...[
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('Subtotal', style: pw.TextStyle(fontSize: baseFont)),
                      pw.Text(CurrencyHelper.format(transaction.subtotal), style: pw.TextStyle(fontSize: baseFont)),
                    ],
                  ),
                  if (config.showDiscount && transaction.discountTotal > 0)
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(
                          transaction.promoName.isNotEmpty
                              ? 'Diskon (${transaction.promoName})'
                              : 'Total Diskon',
                          style: pw.TextStyle(fontSize: baseFont),
                        ),
                        pw.Text('-${CurrencyHelper.format(transaction.discountTotal)}',
                            style: pw.TextStyle(fontSize: baseFont)),
                      ],
                    ),
                  if (transaction.taxAmount > 0)
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('Pajak', style: pw.TextStyle(fontSize: baseFont)),
                        pw.Text(CurrencyHelper.format(transaction.taxAmount),
                            style: pw.TextStyle(fontSize: baseFont)),
                      ],
                    ),
                  pw.SizedBox(height: 2),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('TOTAL', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: baseFont + 2)),
                      pw.Text(CurrencyHelper.format(transaction.grandTotal),
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: baseFont + 2)),
                    ],
                  ),
                ],
                pw.Text(dividerLine, style: pw.TextStyle(fontSize: baseFont - 1, color: PdfColors.grey700)),

                if (config.showPaymentMethod)
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('Metode Bayar', style: pw.TextStyle(fontSize: baseFont - 0.5)),
                      pw.Text(transaction.paymentMethod.toUpperCase(), style: pw.TextStyle(fontSize: baseFont - 0.5)),
                    ],
                  ),
                if (config.showPaidAndChange) ...[
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('Bayar', style: pw.TextStyle(fontSize: baseFont - 0.5)),
                      pw.Text(CurrencyHelper.format(transaction.amountPaid),
                          style: pw.TextStyle(fontSize: baseFont - 0.5)),
                    ],
                  ),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('Kembali', style: pw.TextStyle(fontSize: baseFont - 0.5)),
                      pw.Text(CurrencyHelper.format(transaction.changeAmount),
                          style: pw.TextStyle(fontSize: baseFont - 0.5)),
                    ],
                  ),
                ],

                if (config.showQrInvoice && transaction.qrCodePayload.isNotEmpty) ...[
                  pw.SizedBox(height: 6),
                  pw.Center(
                    child: pw.BarcodeWidget(
                      barcode: pw.Barcode.qrCode(),
                      data: transaction.qrCodePayload,
                      width: isA4 ? 64 : 44,
                      height: isA4 ? 64 : 44,
                    ),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    'Scan QR untuk Retur / Cek Nota',
                    style: pw.TextStyle(fontSize: baseFont - 1.5),
                    textAlign: pw.TextAlign.center,
                  ),
                ],

                if (config.warrantyInfo.isNotEmpty) ...[
                  pw.SizedBox(height: 4),
                  pw.Text(
                    config.warrantyInfo,
                    style: pw.TextStyle(fontSize: baseFont - 1.2, fontWeight: pw.FontWeight.bold),
                    textAlign: pw.TextAlign.center,
                  ),
                ],
                if (config.returnPolicy.isNotEmpty) ...[
                  pw.SizedBox(height: 2),
                  pw.Text(
                    config.returnPolicy,
                    style: pw.TextStyle(fontSize: baseFont - 1.5),
                    textAlign: pw.TextAlign.center,
                  ),
                ],
                if (config.footerText.isNotEmpty) ...[
                  pw.SizedBox(height: 4),
                  pw.Text(
                    config.footerText,
                    style: pw.TextStyle(fontSize: baseFont - 1),
                    textAlign: pw.TextAlign.center,
                  ),
                ],
                pw.SizedBox(height: 8),
              ],
            );
          },
        ),
      );
    }

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => doc.save(),
      name: 'Struk_${transaction.invoiceNumber}',
    );
  }

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
    return printProductLabelsBatch(
      items: [
        EscPosLabelItemAdapter(
          name: product.name,
          sku: product.code,
          barcodeData: product.barcode.isNotEmpty ? product.barcode : product.code,
          price: product.sellingPrice,
          copyCount: copyCount,
        ),
      ],
      storeName: storeName,
      isQrCode: isQrCode,
      showPrice: showPrice,
      showStoreName: showStoreName,
      labelWidthMm: labelWidthMm,
      labelHeightMm: labelHeightMm,
    );
  }

  static Future<void> printProductLabelsBatch({
    required List<EscPosLabelItemAdapter> items,
    required String storeName,
    bool isQrCode = false,
    bool showPrice = true,
    bool showStoreName = true,
    bool showSku = true,
    double labelWidthMm = 40,
    double labelHeightMm = 30,
    bool isA4StickerGrid = false,
  }) async {
    final doc = pw.Document();
    final expanded = <EscPosLabelItemAdapter>[];
    for (final it in items) {
      final cnt = it.copyCount.clamp(1, 200);
      for (int c = 0; c < cnt; c++) {
        expanded.add(it);
      }
    }

    pw.Widget buildLabelTile(EscPosLabelItemAdapter item, {required double tileWmm, required double tileHmm}) {
      final barcodeData = item.barcodeData.isNotEmpty ? item.barcodeData : item.sku;
      final contentW = (tileWmm - 4) * PdfPageFormat.mm;
      final qrSize = ((tileHmm - 14) * PdfPageFormat.mm).clamp(22.0, 44.0);
      final barH = ((tileHmm - 15) * PdfPageFormat.mm).clamp(14.0, 24.0);

      return pw.Container(
        padding: const pw.EdgeInsets.all(2),
        alignment: pw.Alignment.center,
        child: pw.Column(
          mainAxisAlignment: pw.MainAxisAlignment.center,
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          mainAxisSize: pw.MainAxisSize.min,
          children: [
            if (showStoreName && storeName.isNotEmpty)
              pw.Text(
                storeName,
                style: pw.TextStyle(fontSize: 6.5, fontWeight: pw.FontWeight.bold),
                maxLines: 1,
              ),
            pw.Text(
              item.name,
              style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold),
              maxLines: 1,
              overflow: pw.TextOverflow.clip,
              textAlign: pw.TextAlign.center,
            ),
            if (showSku && item.sku.isNotEmpty)
              pw.Text(
                'SKU: ${item.sku}',
                style: const pw.TextStyle(fontSize: 6),
                maxLines: 1,
              ),
            pw.SizedBox(height: 1.5),
            if (isQrCode)
              pw.BarcodeWidget(
                barcode: pw.Barcode.qrCode(),
                data: barcodeData,
                width: qrSize,
                height: qrSize,
              )
            else
              pw.BarcodeWidget(
                barcode: pw.Barcode.code128(),
                data: barcodeData,
                width: contentW,
                height: barH,
                drawText: true,
                textStyle: const pw.TextStyle(fontSize: 6),
              ),
            if (showPrice) ...[
              pw.SizedBox(height: 1.5),
              pw.Text(
                CurrencyHelper.format(item.price),
                style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold),
              ),
            ],
          ],
        ),
      );
    }

    if (isA4StickerGrid) {
      const cols = 3;
      const rowsPerPage = 7;
      const perPage = cols * rowsPerPage;
      for (int start = 0; start < expanded.length; start += perPage) {
        final chunk = expanded.sublist(
          start,
          (start + perPage) > expanded.length ? expanded.length : (start + perPage),
        );
        doc.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.all(14),
            build: (_) {
              final tableRows = <pw.TableRow>[];
              for (int r = 0; r < chunk.length; r += cols) {
                final cells = <pw.Widget>[];
                for (int c = 0; c < cols; c++) {
                  final idx = r + c;
                  if (idx < chunk.length) {
                    cells.add(
                      pw.Container(
                        height: 36 * PdfPageFormat.mm,
                        decoration: pw.BoxDecoration(
                          border: pw.Border.all(color: PdfColors.grey300, width: 0.4),
                        ),
                        child: buildLabelTile(chunk[idx], tileWmm: 60, tileHmm: 35),
                      ),
                    );
                  } else {
                    cells.add(pw.SizedBox(height: 36 * PdfPageFormat.mm));
                  }
                }
                tableRows.add(pw.TableRow(children: cells));
              }
              return pw.Table(children: tableRows);
            },
          ),
        );
      }
    } else {
      final pageFormat = PdfPageFormat(
        labelWidthMm * PdfPageFormat.mm,
        labelHeightMm * PdfPageFormat.mm,
        marginAll: 1.5 * PdfPageFormat.mm,
      );
      for (final item in expanded) {
        doc.addPage(
          pw.Page(
            pageFormat: pageFormat,
            build: (_) => buildLabelTile(item, tileWmm: labelWidthMm, tileHmm: labelHeightMm),
          ),
        );
      }
    }

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => doc.save(),
      name: items.length == 1 ? 'Label_${items.first.sku}' : 'Batch_Labels_${expanded.length}',
    );
  }
}
