import 'dart:convert';
import 'dart:typed_data';
import '../../models/receipt_config.dart';
import '../../models/service_order.dart';
import '../../models/transaction.dart';
import '../../utils/currency_format.dart';
import '../../utils/date_format.dart';
import 'esc_pos_image_helper.dart';

class ProductLabelItem {
  final String name;
  final String sku;
  final String barcodeData;
  final double price;
  final int copyCount;

  const ProductLabelItem({
    required this.name,
    required this.sku,
    required this.barcodeData,
    required this.price,
    this.copyCount = 1,
  });
}

class EscPosGenerator {
  static final List<int> _cmdInit = [0x1B, 0x40];
  static final List<int> _cmdAlignLeft = [0x1B, 0x61, 0x00];
  static final List<int> _cmdAlignCenter = [0x1B, 0x61, 0x01];
  static final List<int> _cmdBoldOn = [0x1B, 0x45, 0x01];
  static final List<int> _cmdBoldOff = [0x1B, 0x45, 0x00];
  static final List<int> _cmdCut = [0x1D, 0x56, 0x42, 0x03];
  static final List<int> cashDrawerPulse = [0x1B, 0x70, 0x00, 0x19, 0xFA];

  static String _sanitizeAscii(String text) {
    // Strip characters unsupported by standard ASCII/CP437 thermal printers
    return text.replaceAll(RegExp(r'[^\x20-\x7E\n]'), ' ');
  }

  static void _addLine(List<int> buffer, String line) {
    buffer.addAll(latin1.encode('${_sanitizeAscii(line)}\n'));
  }

  static String _lr(String left, String right, int width) {
    final l = _sanitizeAscii(left);
    final r = _sanitizeAscii(right);
    if (l.length + r.length + 1 <= width) {
      return l + (' ' * (width - l.length - r.length)) + r;
    }
    final maxLeft = (width - r.length - 1).clamp(4, width);
    final clipped = l.length > maxLeft ? l.substring(0, maxLeft) : l;
    final space = (width - clipped.length - r.length).clamp(1, width);
    return '$clipped${' ' * space}$r';
  }

  static String _divider(ReceiptConfigModel config, int width) {
    final ch = config.dividerStyle.isNotEmpty ? config.dividerStyle[0] : '-';
    return ch * width;
  }

  static Uint8List buildTestPrint({
    required String storeName,
    required String printerName,
    required int charWidth,
  }) {
    final out = <int>[];
    out.addAll(_cmdInit);
    out.addAll(_cmdAlignCenter);
    out.addAll(_cmdBoldOn);
    _addLine(out, 'TEST PRINT KASIRTOKO');
    out.addAll(_cmdBoldOff);
    _addLine(out, storeName);
    _addLine(out, '-' * charWidth);
    out.addAll(_cmdAlignLeft);
    _addLine(out, 'Printer : $printerName');
    _addLine(out, 'Lebar   : $charWidth kolom');
    _addLine(out, 'Waktu   : ${DateHelper.formatFull(DateTime.now())}');
    _addLine(out, 'Status  : KONEKSI ESC/POS OK');
    _addLine(out, '-' * charWidth);
    out.addAll(_cmdAlignCenter);
    _addLine(out, 'Siap digunakan untuk cetak!');
    out.addAll([0x0A, 0x0A, 0x0A]);
    out.addAll(_cmdCut);
    return Uint8List.fromList(out);
  }

  static Uint8List buildTransactionReceipt({
    required TransactionModel transaction,
    required String storeName,
    required String storeAddress,
    required String storePhone,
    required ReceiptConfigModel config,
    required int charWidth,
    String? logoPath,
    bool autoCut = true,
    bool openDrawer = false,
  }) {
    final out = <int>[];
    out.addAll(_cmdInit);

    // Alignment
    out.addAll(config.headerAlignment == 'left' ? _cmdAlignLeft : _cmdAlignCenter);

    bool logoPrinted = false;
    if (config.showLogo && logoPath != null && logoPath.isNotEmpty) {
      final rasterLogo = EscPosImageHelper.encodeEscPosRasterLogo(
        logoPath,
        maxWidthDots: charWidth >= 42 ? 320 : 220,
      );
      if (rasterLogo.isNotEmpty) {
        out.addAll(rasterLogo);
        out.add(0x0A);
        logoPrinted = true;
      }
    }

    final shouldPrintStoreName = !(config.showLogo && config.hideStoreNameWithLogo && logoPrinted);
    if (shouldPrintStoreName) {
      out.addAll(_cmdBoldOn);
      _addLine(out, storeName.toUpperCase());
      out.addAll(_cmdBoldOff);
    }
    if (config.showAddress && storeAddress.isNotEmpty) {
      _addLine(out, storeAddress);
    }
    if (config.showPhone && storePhone.isNotEmpty) {
      _addLine(out, 'Telp: $storePhone');
    }

    out.addAll(_cmdAlignLeft);
    _addLine(out, _divider(config, charWidth));
    _addLine(out, 'Nota    : ${transaction.invoiceNumber}');
    _addLine(out, 'Tanggal : ${DateHelper.formatReceipt(transaction.date)}');
    if (config.showCashier) {
      _addLine(out, 'Kasir   : ${transaction.cashierName}');
    }
    if (config.showCustomer && transaction.customerName != 'Pelanggan Umum') {
      _addLine(out, 'Plg     : ${transaction.customerName}');
    }
    _addLine(out, _divider(config, charWidth));

    for (final item in transaction.items) {
      out.addAll(_cmdBoldOn);
      _addLine(out, item.productName);
      out.addAll(_cmdBoldOff);
      final qtyStr = item.qty.toStringAsFixed(item.qty.truncateToDouble() == item.qty ? 0 : 1);
      final leftPart = config.showQty
          ? (config.showUnitPrice
              ? ' $qtyStr ${item.unitName} x ${CurrencyHelper.format(item.unitPrice)}'
              : ' $qtyStr ${item.unitName}')
          : '';
      _addLine(out, _lr(leftPart, CurrencyHelper.format(item.subtotal), charWidth));
      if (config.showDiscount && item.discount > 0) {
        _addLine(out, '   Diskon: -${CurrencyHelper.format(item.discount)}');
      }
    }

    _addLine(out, _divider(config, charWidth));
    if (config.showTotal) {
      _addLine(out, _lr('Subtotal', CurrencyHelper.format(transaction.subtotal), charWidth));
      if (config.showDiscount && transaction.discountTotal > 0) {
        _addLine(out, _lr('Diskon', '-${CurrencyHelper.format(transaction.discountTotal)}', charWidth));
      }
      if (transaction.taxAmount > 0) {
        _addLine(out, _lr('Pajak', CurrencyHelper.format(transaction.taxAmount), charWidth));
      }
      out.addAll(_cmdBoldOn);
      _addLine(out, _lr('TOTAL', CurrencyHelper.format(transaction.grandTotal), charWidth));
      out.addAll(_cmdBoldOff);
    }

    if (config.showPaymentMethod) {
      _addLine(out, _lr('Metode', transaction.paymentMethod.toUpperCase(), charWidth));
    }
    if (config.showPaidAndChange) {
      if (transaction.creditUsed > 0) {
        _addLine(out, _lr('Potong Kredit', '-${CurrencyHelper.format(transaction.creditUsed)}', charWidth));
      }
      _addLine(out, _lr('Bayar', CurrencyHelper.format(transaction.amountPaid), charWidth));
      _addLine(out, _lr('Kembali', CurrencyHelper.format(transaction.changeAmount), charWidth));
    }

    // Native ESC/POS QR Code (GS ( k)
    if (config.showQrInvoice && transaction.qrCodePayload.isNotEmpty) {
      out.addAll(_cmdAlignCenter);
      _addLine(out, '');
      final qrData = latin1.encode(transaction.qrCodePayload);
      final storeLen = qrData.length + 3;
      final pL = storeLen % 256;
      final pH = storeLen ~/ 256;
      // Model 2, size 4, ECC L
      out.addAll([0x1D, 0x28, 0x6B, 0x04, 0x00, 0x31, 0x41, 0x32, 0x00]);
      out.addAll([0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x43, 0x04]);
      out.addAll([0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x45, 0x30]);
      out.addAll([0x1D, 0x28, 0x6B, pL, pH, 0x31, 0x50, 0x30]);
      out.addAll(qrData);
      out.addAll([0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x51, 0x30]);
      _addLine(out, '');
      _addLine(out, 'Scan QR u/ Cek/Retur Nota');
    }

    _addLine(out, _divider(config, charWidth));
    out.addAll(_cmdAlignCenter);
    if (config.warrantyInfo.isNotEmpty) {
      _addLine(out, config.warrantyInfo);
    }
    if (config.returnPolicy.isNotEmpty) {
      _addLine(out, config.returnPolicy);
    }
    if (config.footerText.isNotEmpty) {
      _addLine(out, config.footerText);
    }

    out.addAll([0x0A, 0x0A, 0x0A]);
    if (autoCut) out.addAll(_cmdCut);
    if (openDrawer) out.addAll(cashDrawerPulse);
    return Uint8List.fromList(out);
  }

  static Uint8List buildServiceNote({
    required ServiceOrderModel order,
    required String storeName,
    required String storeAddress,
    required String storePhone,
    required ReceiptConfigModel config,
    required int charWidth,
    bool autoCut = true,
  }) {
    final out = <int>[];
    out.addAll(_cmdInit);
    out.addAll(_cmdAlignCenter);
    out.addAll(_cmdBoldOn);
    _addLine(out, storeName.toUpperCase());
    out.addAll(_cmdBoldOff);
    if (storeAddress.isNotEmpty) _addLine(out, storeAddress);
    if (storePhone.isNotEmpty) _addLine(out, 'Telp: $storePhone');
    _addLine(out, '=== TANDA TERIMA SERVIS ===');

    out.addAll(_cmdAlignLeft);
    _addLine(out, 'Tiket    : ${order.ticketNumber}');
    _addLine(out, 'Tgl Masuk: ${DateHelper.formatReceipt(order.createdAt)}');
    _addLine(out, 'Pelanggan: ${order.customerName}');
    if (order.customerPhone.isNotEmpty) {
      _addLine(out, 'HP / WA  : ${order.customerPhone}');
    }
    _addLine(out, 'Status   : ${ServiceStatus.label(order.status)}');
    _addLine(out, _divider(config, charWidth));
    _addLine(out, 'Perangkat: ${order.deviceType} ${order.brand} ${order.model}');
    if (order.imeiSn.isNotEmpty) _addLine(out, 'IMEI/SN  : ${order.imeiSn}');
    if (order.accessories.isNotEmpty) _addLine(out, 'Kelengkp : ${order.accessories}');
    _addLine(out, 'Keluhan  : ${order.complaint}');
    _addLine(out, 'Teknisi  : ${order.technicianName}');
    _addLine(out, _divider(config, charWidth));

    if (order.parts.isNotEmpty) {
      out.addAll(_cmdBoldOn);
      _addLine(out, 'Sparepart:');
      out.addAll(_cmdBoldOff);
      for (final p in order.parts) {
        _addLine(out, _lr(' ${p.qty.toInt()}x ${p.productName}', CurrencyHelper.format(p.subtotal), charWidth));
      }
    }

    _addLine(out, _lr('Estimasi', CurrencyHelper.format(order.estimatedCost), charWidth));
    _addLine(out, _lr('Biaya Jasa', CurrencyHelper.format(order.serviceFee), charWidth));
    out.addAll(_cmdBoldOn);
    _addLine(out, _lr('TOTAL BIAYA', CurrencyHelper.format(order.totalCost > 0 ? order.totalCost : order.estimatedCost), charWidth));
    out.addAll(_cmdBoldOff);
    _addLine(out, _lr('Sudah Bayar/DP', CurrencyHelper.format(order.paidAmount), charWidth));
    _addLine(out, _lr('Sisa Bayar', CurrencyHelper.format(order.remainingPayment), charWidth));
    _addLine(out, _divider(config, charWidth));

    out.addAll(_cmdAlignCenter);
    _addLine(out, 'Garansi Servis: ${order.warrantyDays} Hari');
    _addLine(out, 'Simpan nota ini saat pengambilan.');
    out.addAll([0x0A, 0x0A, 0x0A]);
    if (autoCut) out.addAll(_cmdCut);
    return Uint8List.fromList(out);
  }

  /// Generates ESC/POS thermal label stickers (supports both 1D Code128 and 2D QR Code)
  /// across multiple products and custom copy counts.
  static Uint8List buildProductLabels({
    required List<ProductLabelItem> items,
    required String storeName,
    required int charWidth,
    bool isQrCode = false,
    bool showStoreName = true,
    bool showPrice = true,
    bool showSku = true,
    bool autoCut = true,
  }) {
    final out = <int>[];
    out.addAll(_cmdInit);

    for (final item in items) {
      final cleanData = _sanitizeAscii(item.barcodeData).trim();
      final payload = cleanData.isEmpty ? '000000' : cleanData;
      final copies = item.copyCount.clamp(1, 200);

      for (int c = 0; c < copies; c++) {
        out.addAll(_cmdAlignCenter);
        if (showStoreName && storeName.isNotEmpty) {
          _addLine(out, storeName.toUpperCase());
        }
        out.addAll(_cmdBoldOn);
        _addLine(out, item.name.length > charWidth ? item.name.substring(0, charWidth) : item.name);
        out.addAll(_cmdBoldOff);
        if (showSku && item.sku.isNotEmpty) {
          _addLine(out, 'SKU: ${item.sku}');
        }

        if (isQrCode) {
          final qrData = latin1.encode(payload);
          final storeLen = qrData.length + 3;
          out.addAll([0x1D, 0x28, 0x6B, 0x04, 0x00, 0x31, 0x41, 0x32, 0x00]);
          out.addAll([0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x43, 0x05]);
          out.addAll([0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x45, 0x30]);
          out.addAll([0x1D, 0x28, 0x6B, storeLen % 256, storeLen ~/ 256, 0x31, 0x50, 0x30]);
          out.addAll(qrData);
          out.addAll([0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x51, 0x30]);
          out.add(0x0A);
          _addLine(out, payload);
        } else {
          // ESC/POS native Code128 (m = 73) with Code B subset {B (0x7B, 0x42)
          final codeBytes = latin1.encode(payload);
          final dataWithSubset = <int>[0x7B, 0x42, ...codeBytes];
          out.addAll([0x1D, 0x48, 0x02]); // HRI below barcode
          out.addAll([0x1D, 0x68, 0x48]); // Height = 72 dots
          out.addAll([0x1D, 0x77, charWidth >= 42 ? 0x03 : 0x02]); // Module width
          out.addAll([0x1D, 0x6B, 0x49, dataWithSubset.length]);
          out.addAll(dataWithSubset);
          out.add(0x0A);
        }

        if (showPrice) {
          out.addAll(_cmdBoldOn);
          _addLine(out, CurrencyHelper.format(item.price));
          out.addAll(_cmdBoldOff);
        }

        _addLine(out, '-' * charWidth);
        out.addAll([0x0A, 0x0A]);
        if (autoCut) {
          out.addAll(_cmdCut);
        }
      }
    }
    return Uint8List.fromList(out);
  }
}
