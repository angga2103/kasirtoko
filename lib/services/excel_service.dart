import 'dart:io';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/product.dart';
import '../models/transaction.dart';
import '../utils/date_format.dart';

class ExcelImportResult {
  final int successCount;
  final int failedCount;
  final List<String> errors;

  ExcelImportResult({
    required this.successCount,
    required this.failedCount,
    required this.errors,
  });
}

class ExcelService {
  static Future<List<ProductModel>> pickAndParseProductsExcel() async {
    final pickedFile = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls'],
    );

    if (pickedFile == null || pickedFile.path == null) {
      return [];
    }

    final file = File(pickedFile.path!);
    final bytes = await file.readAsBytes();
    final excel = Excel.decodeBytes(bytes);

    final List<ProductModel> products = [];

    for (final table in excel.tables.keys) {
      final sheet = excel.tables[table]!;
      for (int rowIndex = 1; rowIndex < sheet.rows.length; rowIndex++) {
        final row = sheet.rows[rowIndex];
        if (row.isEmpty || row[0] == null) continue;

        try {
          final code = row[0]?.value?.toString().trim() ?? '';
          final name = row.length > 1 ? row[1]?.value?.toString().trim() ?? '' : '';
          if (name.isEmpty) continue;

          final category = row.length > 2 ? row[2]?.value?.toString().trim() ?? 'Umum' : 'Umum';
          final barcode = row.length > 3 ? row[3]?.value?.toString().trim() ?? '' : '';
          final baseUnit = row.length > 4 ? row[4]?.value?.toString().trim() ?? 'Pcs' : 'Pcs';

          final costPrice = row.length > 5
              ? double.tryParse(row[5]?.value?.toString() ?? '0') ?? 0.0
              : 0.0;
          final sellingPrice = row.length > 6
              ? double.tryParse(row[6]?.value?.toString() ?? '0') ?? 0.0
              : 0.0;
          final stock = row.length > 7
              ? double.tryParse(row[7]?.value?.toString() ?? '0') ?? 0.0
              : 0.0;
          final minStock = row.length > 8
              ? double.tryParse(row[8]?.value?.toString() ?? '5') ?? 5.0
              : 5.0;
          final isServiceStr = row.length > 9 ? row[9]?.value?.toString().trim() ?? '0' : '0';
          final isService = isServiceStr == '1' ||
              isServiceStr.toLowerCase() == 'ya' ||
              isServiceStr.toLowerCase() == 'jasa';

          products.add(
            ProductModel(
              code: code.isNotEmpty ? code : 'PRD-${DateTime.now().millisecondsSinceEpoch}-$rowIndex',
              name: name,
              category: category,
              barcode: barcode,
              baseUnit: baseUnit,
              costPrice: costPrice,
              sellingPrice: sellingPrice,
              stock: stock,
              minStockAlert: minStock,
              isService: isService,
            ),
          );
        } catch (_) {}
      }
      break;
    }

    return products;
  }

  static Future<String> exportProductsToExcel(List<ProductModel> products) async {
    final excel = Excel.createExcel();
    final sheet = excel['Master Produk'];
    excel.delete('Sheet1');

    sheet.appendRow([
      TextCellValue('Kode Produk'),
      TextCellValue('Nama Produk'),
      TextCellValue('Kategori'),
      TextCellValue('Barcode'),
      TextCellValue('Satuan'),
      TextCellValue('Harga Modal'),
      TextCellValue('Harga Jual'),
      TextCellValue('Stok'),
      TextCellValue('Min Stok Alert'),
      TextCellValue('Tipe (Barang/Jasa)'),
    ]);

    for (final p in products) {
      sheet.appendRow([
        TextCellValue(p.code),
        TextCellValue(p.name),
        TextCellValue(p.category),
        TextCellValue(p.barcode),
        TextCellValue(p.baseUnit),
        DoubleCellValue(p.costPrice),
        DoubleCellValue(p.sellingPrice),
        DoubleCellValue(p.stock),
        DoubleCellValue(p.minStockAlert),
        TextCellValue(p.isService ? 'Jasa' : 'Barang'),
      ]);
    }

    final bytes = excel.encode();
    if (bytes == null) return '';

    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/Master_Produk_${DateTime.now().millisecondsSinceEpoch}.xlsx');
    await file.writeAsBytes(bytes);

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        text: 'Export Master Produk KasirToko',
      ),
    );
    return file.path;
  }

  static Future<String> exportTransactionsToExcel(List<TransactionModel> transactions) async {
    final excel = Excel.createExcel();
    final sheet = excel['Laporan Penjualan'];
    excel.delete('Sheet1');

    sheet.appendRow([
      TextCellValue('No. Nota'),
      TextCellValue('Tanggal'),
      TextCellValue('Kasir'),
      TextCellValue('Pelanggan'),
      TextCellValue('Metode Bayar'),
      TextCellValue('Subtotal'),
      TextCellValue('Diskon'),
      TextCellValue('Pajak'),
      TextCellValue('Total Transaksi'),
      TextCellValue('Status'),
    ]);

    for (final t in transactions) {
      sheet.appendRow([
        TextCellValue(t.invoiceNumber),
        TextCellValue(DateHelper.formatFull(t.date)),
        TextCellValue(t.cashierName),
        TextCellValue(t.customerName),
        TextCellValue(t.paymentMethod.toUpperCase()),
        DoubleCellValue(t.subtotal),
        DoubleCellValue(t.discountTotal),
        DoubleCellValue(t.taxAmount),
        DoubleCellValue(t.grandTotal),
        TextCellValue(t.status),
      ]);
    }

    final bytes = excel.encode();
    if (bytes == null) return '';

    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/Laporan_Penjualan_${DateTime.now().millisecondsSinceEpoch}.xlsx');
    await file.writeAsBytes(bytes);

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        text: 'Export Laporan Penjualan KasirToko',
      ),
    );
    return file.path;
  }
}
