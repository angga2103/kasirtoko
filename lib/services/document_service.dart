import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/customer_debt.dart';
import '../models/service_order.dart';
import '../models/warehouse_doc.dart';
import '../utils/currency_format.dart';
import '../utils/date_format.dart';

class DocumentService {
  static Future<pw.MemoryImage?> _loadLogo(String? logoPath) async {
    if (logoPath == null || logoPath.isEmpty) return null;
    try {
      final f = File(logoPath);
      if (await f.exists()) {
        return pw.MemoryImage(await f.readAsBytes());
      }
    } catch (_) {}
    return null;
  }

  // Generate and Print / Preview Surat Jalan or Surat Ambil Barang
  static Future<void> printWarehouseDoc({
    required WarehouseDocModel docModel,
    required String storeName,
    required String storeAddress,
    required String storePhone,
    String? logoPath,
  }) async {
    final doc = pw.Document();
    final logoImg = await _loadLogo(logoPath);
    final items = docModel.parsedItems;

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      if (logoImg != null) ...[
                        pw.Container(
                          width: 44,
                          height: 44,
                          margin: const pw.EdgeInsets.only(right: 10),
                          child: pw.Image(logoImg, fit: pw.BoxFit.contain),
                        ),
                      ],
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            storeName,
                            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
                          ),
                          pw.Text(storeAddress, style: const pw.TextStyle(fontSize: 9)),
                          pw.Text('Telp: $storePhone', style: const pw.TextStyle(fontSize: 9)),
                        ],
                      ),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        docModel.docTitle,
                        style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
                      ),
                      pw.Text('No: ${docModel.docNumber}',
                          style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                      pw.Text('Tanggal: ${DateHelper.formatShort(docModel.date)}',
                          style: const pw.TextStyle(fontSize: 9)),
                      if (docModel.deliveryDate != null)
                        pw.Text('Tgl Kirim: ${DateHelper.formatShort(docModel.deliveryDate!)}',
                            style: const pw.TextStyle(fontSize: 9)),
                      pw.Text('Status: ${docModel.status.toUpperCase()}',
                          style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold)),
                    ],
                  ),
                ],
              ),
              pw.Divider(thickness: 1.5, height: 20),

              // Recipient / Vehicle Info
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('Tujuan / Penerima:',
                            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                        pw.Text(docModel.recipientName,
                            style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                        if (docModel.recipientAddress.isNotEmpty)
                          pw.Text(docModel.recipientAddress, style: const pw.TextStyle(fontSize: 9)),
                        if (docModel.recipientPhone.isNotEmpty)
                          pw.Text('Kontak: ${docModel.recipientPhone}',
                              style: const pw.TextStyle(fontSize: 9)),
                      ],
                    ),
                  ),
                  pw.SizedBox(width: 24),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text('Petugas / Pengemudi:',
                          style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                      pw.Text(
                        docModel.driverOrPickerName.isNotEmpty ? docModel.driverOrPickerName : '-',
                        style: const pw.TextStyle(fontSize: 10),
                      ),
                      if (docModel.vehicleNumber.isNotEmpty)
                        pw.Text('No. Kendaraan: ${docModel.vehicleNumber}',
                            style: const pw.TextStyle(fontSize: 9)),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 16),

              // Items Table
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text('No',
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text('Nama Barang',
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text('Qty',
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text('Satuan',
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text('Keterangan',
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                      ),
                    ],
                  ),
                  for (int i = 0; i < items.length; i++)
                    pw.TableRow(
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text('${i + 1}', style: const pw.TextStyle(fontSize: 9)),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text(items[i].name, style: const pw.TextStyle(fontSize: 9)),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text(
                            items[i].qty == items[i].qty.truncateToDouble()
                                ? items[i].qty.toInt().toString()
                                : items[i].qty.toStringAsFixed(1),
                            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text(items[i].unit, style: const pw.TextStyle(fontSize: 9)),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text(items[i].note, style: const pw.TextStyle(fontSize: 9)),
                        ),
                      ],
                    ),
                ],
              ),
              pw.SizedBox(height: 12),

              if (docModel.note.isNotEmpty) ...[
                pw.Text('Catatan: ${docModel.note}',
                    style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey800)),
                pw.SizedBox(height: 20),
              ],

              pw.Spacer(),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    children: [
                      pw.Text('Penerima', style: const pw.TextStyle(fontSize: 9)),
                      pw.SizedBox(height: 50),
                      pw.Text('( ................................ )',
                          style: const pw.TextStyle(fontSize: 9)),
                    ],
                  ),
                  pw.Column(
                    children: [
                      pw.Text('Pengemudi / Pengambil', style: const pw.TextStyle(fontSize: 9)),
                      pw.SizedBox(height: 50),
                      pw.Text('( ................................ )',
                          style: const pw.TextStyle(fontSize: 9)),
                    ],
                  ),
                  pw.Column(
                    children: [
                      pw.Text('Petugas Gudang / Kasir', style: const pw.TextStyle(fontSize: 9)),
                      pw.SizedBox(height: 50),
                      pw.Text('( ................................ )',
                          style: const pw.TextStyle(fontSize: 9)),
                    ],
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => doc.save(),
      name: '${docModel.docType}_${docModel.docNumber}',
    );
  }

  // Generate and Print Formal Invoice Penagihan (Debt Invoice)
  static Future<void> printDebtInvoice({
    required CustomerDebtModel debt,
    required String storeName,
    required String storeAddress,
    required String storePhone,
    String? logoPath,
  }) async {
    final doc = pw.Document();
    final logoImg = await _loadLogo(logoPath);

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Row(
                    children: [
                      if (logoImg != null)
                        pw.Container(
                          width: 42,
                          height: 42,
                          margin: const pw.EdgeInsets.only(right: 10),
                          child: pw.Image(logoImg, fit: pw.BoxFit.contain),
                        ),
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(storeName,
                              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
                          pw.Text(storeAddress, style: const pw.TextStyle(fontSize: 9)),
                          pw.Text('Telp: $storePhone', style: const pw.TextStyle(fontSize: 9)),
                        ],
                      ),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text('SURAT INVOICE PENAGIHAN',
                          style: pw.TextStyle(
                              fontSize: 14,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.red900)),
                      pw.Text('No. Nota: ${debt.invoiceNumber}',
                          style: const pw.TextStyle(fontSize: 10)),
                      pw.Text('Tanggal Nota: ${DateHelper.formatShort(debt.transactionDate)}',
                          style: const pw.TextStyle(fontSize: 9)),
                    ],
                  ),
                ],
              ),
              pw.Divider(thickness: 1.5, height: 20),

              pw.Text('Kepada Yth.',
                  style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
              pw.Text(debt.customerName,
                  style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
              if (debt.customerPhone.isNotEmpty)
                pw.Text('No. Telp / WA: ${debt.customerPhone}',
                    style: const pw.TextStyle(fontSize: 9)),
              pw.SizedBox(height: 16),

              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey400),
                  borderRadius: pw.BorderRadius.circular(6),
                ),
                child: pw.Column(
                  children: [
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('Total Tagihan Kasbon', style: const pw.TextStyle(fontSize: 11)),
                        pw.Text(CurrencyHelper.format(debt.totalDebt),
                            style: const pw.TextStyle(fontSize: 11)),
                      ],
                    ),
                    pw.Divider(thickness: 0.5),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('Sudah Dibayar', style: const pw.TextStyle(fontSize: 11)),
                        pw.Text(CurrencyHelper.format(debt.paidDebt),
                            style: const pw.TextStyle(fontSize: 11)),
                      ],
                    ),
                    pw.Divider(thickness: 0.5),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('SISA TAGIHAN',
                            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                        pw.Text(
                          CurrencyHelper.format(debt.remainingDebt),
                          style: pw.TextStyle(
                              fontSize: 13,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.red800),
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 8),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('Jatuh Tempo Pembayaran',
                            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                        pw.Text(DateHelper.formatShort(debt.dueDate),
                            style: pw.TextStyle(
                                fontSize: 10,
                                fontWeight: pw.FontWeight.bold,
                                color: PdfColors.red800)),
                      ],
                    ),
                  ],
                ),
              ),

              pw.Spacer(),
              pw.Text(
                'Mohon melakukan pelunasan ke toko atau transfer ke rekening resmi kami sebelum tanggal jatuh tempo.',
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey800),
              ),
              pw.SizedBox(height: 20),

              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    children: [
                      pw.Text('Pelanggan', style: const pw.TextStyle(fontSize: 9)),
                      pw.SizedBox(height: 45),
                      pw.Text('( ${debt.customerName} )', style: const pw.TextStyle(fontSize: 9)),
                    ],
                  ),
                  pw.Column(
                    children: [
                      pw.Text('Hormat Kami / Bagian Keuangan',
                          style: const pw.TextStyle(fontSize: 9)),
                      pw.SizedBox(height: 45),
                      pw.Text('( ................................ )',
                          style: const pw.TextStyle(fontSize: 9)),
                    ],
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => doc.save(),
      name: 'Invoice_Tagihan_${debt.invoiceNumber}',
    );
  }

  // Generate and Print Nota Servis (Thermal 58/80mm or A4 Laser)
  static Future<void> printServiceOrderNote({
    required ServiceOrderModel order,
    required String storeName,
    required String storeAddress,
    required String storePhone,
    String? logoPath,
    String? thermalPaperSize, // null = A4, '58mm' or '80mm'
  }) async {
    final doc = pw.Document();
    final logoImg = await _loadLogo(logoPath);

    final isThermal = thermalPaperSize == '58mm' || thermalPaperSize == '80mm';
    final pageFormat = isThermal
        ? PdfPageFormat(
            (thermalPaperSize == '80mm' ? 72 : 58) * PdfPageFormat.mm,
            double.infinity,
            marginAll: 2.5 * PdfPageFormat.mm,
          )
        : PdfPageFormat.a4;

    final fs = isThermal ? 8.0 : 10.0;

    doc.addPage(
      pw.Page(
        pageFormat: pageFormat,
        margin: isThermal ? null : const pw.EdgeInsets.all(32),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Center(
                child: pw.Column(
                  children: [
                    if (logoImg != null) ...[
                      pw.Container(
                        width: isThermal ? 32 : 46,
                        height: isThermal ? 32 : 46,
                        child: pw.Image(logoImg, fit: pw.BoxFit.contain),
                      ),
                      pw.SizedBox(height: 4),
                    ],
                    pw.Text(storeName, style: pw.TextStyle(fontSize: fs + 4, fontWeight: pw.FontWeight.bold)),
                    if (storeAddress.isNotEmpty)
                      pw.Text(storeAddress, style: pw.TextStyle(fontSize: fs - 1), textAlign: pw.TextAlign.center),
                    if (storePhone.isNotEmpty)
                      pw.Text('Telp: $storePhone', style: pw.TextStyle(fontSize: fs - 1)),
                    pw.SizedBox(height: 4),
                    pw.Text('NOTA PENERIMAAN & SERVIS',
                        style: pw.TextStyle(fontSize: fs + 1, fontWeight: pw.FontWeight.bold)),
                  ],
                ),
              ),
              pw.Divider(thickness: 1),
              pw.Text('No. Tiket   : ${order.ticketNumber}',
                  style: pw.TextStyle(fontSize: fs, fontWeight: pw.FontWeight.bold)),
              pw.Text('Tgl Masuk   : ${DateHelper.formatFull(order.createdAt)}', style: pw.TextStyle(fontSize: fs)),
              pw.Text('Status      : ${ServiceStatus.label(order.status)}',
                  style: pw.TextStyle(fontSize: fs, fontWeight: pw.FontWeight.bold)),
              pw.Text('Pelanggan   : ${order.customerName} (${order.customerPhone})', style: pw.TextStyle(fontSize: fs)),
              pw.Divider(thickness: 0.5),
              pw.Text('Perangkat   : ${order.deviceType} ${order.brand} ${order.model}',
                  style: pw.TextStyle(fontSize: fs, fontWeight: pw.FontWeight.bold)),
              if (order.imeiSn.isNotEmpty)
                pw.Text('IMEI / SN   : ${order.imeiSn}', style: pw.TextStyle(fontSize: fs)),
              if (order.accessories.isNotEmpty)
                pw.Text('Kelengkapan : ${order.accessories}', style: pw.TextStyle(fontSize: fs)),
              if (order.physicalCondition.isNotEmpty)
                pw.Text('Kondisi     : ${order.physicalCondition}', style: pw.TextStyle(fontSize: fs)),
              pw.Text('Keluhan     : ${order.complaint}', style: pw.TextStyle(fontSize: fs)),
              pw.Text('Teknisi     : ${order.technicianName}', style: pw.TextStyle(fontSize: fs)),
              pw.Divider(thickness: 0.5),

              if (order.parts.isNotEmpty) ...[
                pw.Text('Rincian Sparepart:', style: pw.TextStyle(fontSize: fs, fontWeight: pw.FontWeight.bold)),
                for (final part in order.parts)
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Expanded(
                        child: pw.Text('${part.qty.toInt()} ${part.unitName} ${part.productName}',
                            style: pw.TextStyle(fontSize: fs)),
                      ),
                      pw.Text(CurrencyHelper.format(part.subtotal), style: pw.TextStyle(fontSize: fs)),
                    ],
                  ),
                pw.Divider(thickness: 0.5),
              ],

              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Estimasi Biaya', style: pw.TextStyle(fontSize: fs)),
                  pw.Text(CurrencyHelper.format(order.estimatedCost), style: pw.TextStyle(fontSize: fs)),
                ],
              ),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Biaya Jasa', style: pw.TextStyle(fontSize: fs)),
                  pw.Text(CurrencyHelper.format(order.serviceFee), style: pw.TextStyle(fontSize: fs)),
                ],
              ),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('TOTAL BIAYA', style: pw.TextStyle(fontSize: fs + 1, fontWeight: pw.FontWeight.bold)),
                  pw.Text(
                    CurrencyHelper.format(order.totalCost > 0 ? order.totalCost : order.estimatedCost),
                    style: pw.TextStyle(fontSize: fs + 1, fontWeight: pw.FontWeight.bold),
                  ),
                ],
              ),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('DP / Sudah Bayar', style: pw.TextStyle(fontSize: fs)),
                  pw.Text(CurrencyHelper.format(order.paidAmount), style: pw.TextStyle(fontSize: fs)),
                ],
              ),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('SISA PEMBAYARAN', style: pw.TextStyle(fontSize: fs, fontWeight: pw.FontWeight.bold)),
                  pw.Text(CurrencyHelper.format(order.remainingPayment),
                      style: pw.TextStyle(fontSize: fs, fontWeight: pw.FontWeight.bold)),
                ],
              ),
              pw.SizedBox(height: 8),
              pw.Center(
                child: pw.BarcodeWidget(
                  barcode: pw.Barcode.qrCode(),
                  data: 'SRV|${order.ticketNumber}',
                  width: isThermal ? 42 : 60,
                  height: isThermal ? 42 : 60,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Center(
                child: pw.Text(
                  'Garansi Servis ${order.warrantyDays} Hari • Simpan nota ini untuk pengambilan perangkat.',
                  style: pw.TextStyle(fontSize: fs - 1.5),
                  textAlign: pw.TextAlign.center,
                ),
              ),
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => doc.save(),
      name: 'Nota_Servis_${order.ticketNumber}',
    );
  }
}
