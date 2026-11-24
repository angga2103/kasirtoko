import 'dart:convert';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/warehouse_doc.dart';
import '../models/customer_debt.dart';
import '../utils/currency_format.dart';
import '../utils/date_format.dart';

class DocumentService {
  // Generate and Print / Preview Surat Jalan or Surat Ambil Barang
  static Future<void> printWarehouseDoc({
    required WarehouseDocModel docModel,
    required String storeName,
    required String storeAddress,
    required String storePhone,
  }) async {
    final doc = pw.Document();

    List<dynamic> items = [];
    try {
      items = jsonDecode(docModel.itemsJson);
    } catch (_) {}

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
                children: [
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
                  pw.Column(
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
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
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
                          child: pw.Text(items[i]['name'] ?? '',
                              style: const pw.TextStyle(fontSize: 9)),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text('${items[i]['qty'] ?? 1}',
                              style: const pw.TextStyle(fontSize: 9)),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text(items[i]['unit'] ?? 'Pcs',
                              style: const pw.TextStyle(fontSize: 9)),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text(items[i]['note'] ?? '',
                              style: const pw.TextStyle(fontSize: 9)),
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

              // Signatures
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
  }) async {
    final doc = pw.Document();

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
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(storeName,
                          style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
                      pw.Text(storeAddress, style: const pw.TextStyle(fontSize: 9)),
                      pw.Text('Telp: $storePhone', style: const pw.TextStyle(fontSize: 9)),
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
}
