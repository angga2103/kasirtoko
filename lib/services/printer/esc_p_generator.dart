import 'dart:convert';
import 'dart:typed_data';
import '../../models/customer_debt.dart';
import '../../models/service_order.dart';
import '../../models/warehouse_doc.dart';
import '../../utils/currency_format.dart';
import '../../utils/date_format.dart';

/// ESC/P Byte Generator for Dot Matrix Continuous Paper Printers (Epson LX-310, etc.)
class EscPGenerator {
  static final List<int> _cmdInit = [0x1B, 0x40]; // ESC @
  static final List<int> _cmdBoldOn = [0x1B, 0x45]; // ESC E
  static final List<int> _cmdBoldOff = [0x1B, 0x46]; // ESC F
  static final List<int> _cmdFormFeed = [0x0C];

  static String _ascii(String s) => s.replaceAll(RegExp(r'[^\x20-\x7E]'), ' ');

  static void _line(List<int> out, String text) {
    out.addAll(latin1.encode('${_ascii(text)}\r\n'));
  }

  static String _padRight(String s, int width) {
    final clean = _ascii(s);
    if (clean.length >= width) return clean.substring(0, width);
    return clean + (' ' * (width - clean.length));
  }

  static String _lr(String l, String r, int width) {
    final al = _ascii(l);
    final ar = _ascii(r);
    if (al.length + ar.length + 1 <= width) {
      return '$al${' ' * (width - al.length - ar.length)}$ar';
    }
    return '${_padRight(al, (width - ar.length - 1).clamp(10, width))} $ar';
  }

  static Uint8List buildTestPrint({
    required String storeName,
    required String printerName,
  }) {
    final out = <int>[];
    out.addAll(_cmdInit);
    out.addAll(_cmdBoldOn);
    _line(out, 'TEST PRINT DOT MATRIX (ESC/P)');
    out.addAll(_cmdBoldOff);
    _line(out, '=' * 80);
    _line(out, 'Toko    : $storeName');
    _line(out, 'Printer : $printerName');
    _line(out, 'Waktu   : ${DateHelper.formatFull(DateTime.now())}');
    _line(out, 'Lebar   : Continuous Paper 80 Kolom');
    _line(out, '=' * 80);
    _line(out, 'Koneksi ESC/P berjalan normal.');
    out.addAll([0x0D, 0x0A, 0x0D, 0x0A]);
    out.addAll(_cmdFormFeed);
    return Uint8List.fromList(out);
  }

  static Uint8List buildWarehouseDoc({
    required WarehouseDocModel doc,
    required String storeName,
    required String storeAddress,
    required String storePhone,
  }) {
    const width = 80;
    final out = <int>[];
    out.addAll(_cmdInit);

    out.addAll(_cmdBoldOn);
    _line(out, _lr(storeName.toUpperCase(), doc.docTitle, width));
    out.addAll(_cmdBoldOff);
    _line(out, _lr(storeAddress, 'No: ${doc.docNumber}', width));
    _line(out, _lr('Telp: $storePhone', 'Tanggal: ${DateHelper.formatShort(doc.date)}', width));
    _line(out, '=' * width);

    _line(out, _lr('Kepada / Penerima : ${doc.recipientName}', 'Supir/Petugas: ${doc.driverOrPickerName.isEmpty ? "-" : doc.driverOrPickerName}', width));
    _line(out, _lr('Alamat            : ${doc.recipientAddress.isEmpty ? "-" : doc.recipientAddress}', 'No. Kendaraan: ${doc.vehicleNumber.isEmpty ? "-" : doc.vehicleNumber}', width));
    if (doc.deliveryDate != null) {
      _line(out, 'Tgl Kirim / Ambil : ${DateHelper.formatShort(doc.deliveryDate!)} | Status: ${doc.status.toUpperCase()}');
    }
    _line(out, '-' * width);
    out.addAll(_cmdBoldOn);
    _line(out, '${_padRight('NO', 4)} ${_padRight('NAMA BARANG', 34)} ${_padRight('QTY', 10)} ${_padRight('SATUAN', 10)} ${_padRight('KET', 18)}');
    out.addAll(_cmdBoldOff);
    _line(out, '-' * width);

    final items = doc.parsedItems;
    for (int i = 0; i < items.length; i++) {
      final it = items[i];
      final qtyStr = it.qty == it.qty.truncateToDouble() ? it.qty.toInt().toString() : it.qty.toStringAsFixed(1);
      _line(
        out,
        '${_padRight('${i + 1}', 4)} ${_padRight(it.name, 34)} ${_padRight(qtyStr, 10)} ${_padRight(it.unit, 10)} ${_padRight(it.note, 18)}',
      );
    }

    _line(out, '-' * width);
    if (doc.note.isNotEmpty) {
      _line(out, 'Catatan: ${doc.note}');
    }
    out.addAll([0x0D, 0x0A]);
    _line(out, '   Penerima                  Pengemudi                  Petugas Gudang');
    out.addAll([0x0D, 0x0A, 0x0D, 0x0A, 0x0D, 0x0A]);
    _line(out, '(______________)          (______________)             (______________)');
    out.addAll(_cmdFormFeed);
    return Uint8List.fromList(out);
  }

  static Uint8List buildDebtInvoice({
    required CustomerDebtModel debt,
    required String storeName,
    required String storeAddress,
    required String storePhone,
  }) {
    const width = 80;
    final out = <int>[];
    out.addAll(_cmdInit);
    out.addAll(_cmdBoldOn);
    _line(out, _lr(storeName.toUpperCase(), 'SURAT INVOICE PENAGIHAN', width));
    out.addAll(_cmdBoldOff);
    _line(out, _lr(storeAddress, 'No. Nota: ${debt.invoiceNumber}', width));
    _line(out, _lr('Telp: $storePhone', 'Jatuh Tempo: ${DateHelper.formatShort(debt.dueDate)}', width));
    _line(out, '=' * width);
    _line(out, 'Kepada Yth : ${debt.customerName}');
    if (debt.customerPhone.isNotEmpty) _line(out, 'Telp / WA  : ${debt.customerPhone}');
    _line(out, '-' * width);
    _line(out, _lr('Total Tagihan', CurrencyHelper.format(debt.totalDebt), width));
    _line(out, _lr('Sudah Dibayar', CurrencyHelper.format(debt.paidDebt), width));
    out.addAll(_cmdBoldOn);
    _line(out, _lr('SISA TAGIHAN', CurrencyHelper.format(debt.remainingDebt), width));
    out.addAll(_cmdBoldOff);
    _line(out, '=' * width);
    out.addAll(_cmdFormFeed);
    return Uint8List.fromList(out);
  }

  static Uint8List buildServiceNote({
    required ServiceOrderModel order,
    required String storeName,
    required String storeAddress,
    required String storePhone,
  }) {
    const width = 80;
    final out = <int>[];
    out.addAll(_cmdInit);
    out.addAll(_cmdBoldOn);
    _line(out, _lr(storeName.toUpperCase(), 'NOTA SERVIS PERANGKAT', width));
    out.addAll(_cmdBoldOff);
    _line(out, _lr(storeAddress, 'No. Tiket: ${order.ticketNumber}', width));
    _line(out, '=' * width);
    _line(out, 'Pelanggan : ${order.customerName} (${order.customerPhone})');
    _line(out, 'Perangkat : ${order.deviceType} ${order.brand} ${order.model} | IMEI/SN: ${order.imeiSn}');
    _line(out, 'Keluhan   : ${order.complaint}');
    _line(out, 'Teknisi   : ${order.technicianName} | Status: ${ServiceStatus.label(order.status)}');
    _line(out, '-' * width);
    _line(out, _lr('Biaya Jasa', CurrencyHelper.format(order.serviceFee), width));
    for (final p in order.parts) {
      _line(out, _lr('Part: ${p.productName} (${p.qty.toInt()}x)', CurrencyHelper.format(p.subtotal), width));
    }
    out.addAll(_cmdBoldOn);
    _line(out, _lr('TOTAL BIAYA', CurrencyHelper.format(order.totalCost > 0 ? order.totalCost : order.estimatedCost), width));
    _line(out, _lr('DP / DIBAYAR', CurrencyHelper.format(order.paidAmount), width));
    _line(out, _lr('SISA PEMBAYARAN', CurrencyHelper.format(order.remainingPayment), width));
    out.addAll(_cmdBoldOff);
    _line(out, '=' * width);
    out.addAll(_cmdFormFeed);
    return Uint8List.fromList(out);
  }
}
