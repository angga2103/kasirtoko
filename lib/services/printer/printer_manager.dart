import 'dart:typed_data';
import '../../models/customer_debt.dart';
import '../../models/printer_device.dart';
import '../../models/receipt_config.dart';
import '../../models/service_order.dart';
import '../../models/transaction.dart';
import '../../models/warehouse_doc.dart';
import '../document_service.dart';
import '../hardware_bridge.dart';
import '../thermal_printer_service.dart';
import 'esc_p_generator.dart';
import 'esc_pos_generator.dart';
import 'printer_adapter.dart';

class HardwarePrinterAdapter implements PrinterAdapter {
  @override
  final PrinterDeviceModel device;

  HardwarePrinterAdapter(this.device);

  @override
  Future<PrinterOperationResult> testConnection() async {
    switch (device.connectionType) {
      case PrinterConnectionType.bluetooth:
        final res = await HardwareBridge.testBluetoothConnection(device.address);
        return PrinterOperationResult(success: res.success, message: res.message);
      case PrinterConnectionType.usb:
        final res = await HardwareBridge.testUsbConnection(device.address);
        return PrinterOperationResult(success: res.success, message: res.message);
      case PrinterConnectionType.lan:
        final res = await HardwareBridge.testTcpConnection(device.address, device.port);
        return PrinterOperationResult(success: res.success, message: res.message);
      case PrinterConnectionType.system:
        return PrinterOperationResult(
          success: true,
          message: 'Android Print Service siap digunakan untuk pratinjau/cetak PDF.',
        );
      default:
        return PrinterOperationResult(
          success: false,
          message: 'Tipe koneksi printer tidak dikenal: ${device.connectionType}',
        );
    }
  }

  @override
  Future<PrinterOperationResult> printRawBytes(Uint8List bytes) async {
    switch (device.connectionType) {
      case PrinterConnectionType.bluetooth:
        final res = await HardwareBridge.printBluetoothBytes(device.address, bytes);
        return PrinterOperationResult(success: res.success, message: res.message);
      case PrinterConnectionType.usb:
        final res = await HardwareBridge.printUsbBytes(device.address, bytes);
        return PrinterOperationResult(success: res.success, message: res.message);
      case PrinterConnectionType.lan:
        final res = await HardwareBridge.printTcpBytes(device.address, device.port, bytes);
        return PrinterOperationResult(success: res.success, message: res.message);
      case PrinterConnectionType.system:
        return PrinterOperationResult(
          success: false,
          message: 'Printer ini menggunakan mode PDF Sistem, gunakan adapter PDF untuk mencetak.',
        );
      default:
        return PrinterOperationResult(success: false, message: 'Koneksi tidak didukung.');
    }
  }

  @override
  Future<PrinterOperationResult> openCashDrawer() async {
    if (device.connectionType == PrinterConnectionType.system) {
      return PrinterOperationResult(
        success: false,
        message: 'Laci kasir RJ11 memerlukan printer Thermal yang terhubung via Bluetooth, USB OTG, atau LAN.',
      );
    }
    return await printRawBytes(Uint8List.fromList(EscPosGenerator.cashDrawerPulse));
  }
}

class PrinterManager {
  static PrinterAdapter adapterFor(PrinterDeviceModel device) {
    return HardwarePrinterAdapter(device);
  }

  static Future<PrinterOperationResult> testPrinter(
    PrinterDeviceModel printer, {
    required String storeName,
    bool alsoSendTestPage = false,
  }) async {
    final adapter = adapterFor(printer);
    final conn = await adapter.testConnection();
    if (!conn.success) return conn;

    if (!alsoSendTestPage || printer.connectionType == PrinterConnectionType.system) {
      return conn;
    }

    if (printer.protocol == PrinterProtocol.escP || printer.category == PrinterCategory.dotMatrix) {
      final bytes = EscPGenerator.buildTestPrint(storeName: storeName, printerName: printer.name);
      return await adapter.printRawBytes(bytes);
    } else {
      final bytes = EscPosGenerator.buildTestPrint(
        storeName: storeName,
        printerName: printer.name,
        charWidth: printer.escCharWidth,
      );
      return await adapter.printRawBytes(bytes);
    }
  }

  static Future<PrinterOperationResult> printTransactionReceipt({
    required PrinterDeviceModel? printer,
    required TransactionModel transaction,
    required String storeName,
    required String storeAddress,
    required String storePhone,
    required ReceiptConfigModel receiptConfig,
    String? logoPath,
    bool isReprint = false,
  }) async {
    final target = printer ??
        PrinterDeviceModel(
          name: 'Android Print Service',
          category: PrinterCategory.laser,
          connectionType: PrinterConnectionType.system,
          paperSize: receiptConfig.paperSize,
          protocol: PrinterProtocol.pdf,
          isDefault: true,
        );

    final copies = receiptConfig.copyCount.clamp(1, 5);

    if (target.connectionType == PrinterConnectionType.system ||
        target.protocol == PrinterProtocol.pdf) {
      await ThermalPrinterService.printReceiptWithConfig(
        transaction: transaction,
        storeName: storeName,
        storeAddress: storeAddress,
        storePhone: storePhone,
        config: receiptConfig,
        logoPath: logoPath,
        isReprint: isReprint,
      );
      return PrinterOperationResult(
        success: true,
        message: 'Dialog cetak PDF dibuka.',
      );
    }

    final adapter = adapterFor(target);
    final bytes = EscPosGenerator.buildTransactionReceipt(
      transaction: transaction,
      storeName: storeName,
      storeAddress: storeAddress,
      storePhone: storePhone,
      config: receiptConfig,
      charWidth: target.escCharWidth,
      logoPath: logoPath,
      autoCut: target.autoCut,
      openDrawer: !isReprint && target.openDrawer && transaction.paymentMethod == 'tunai',
    );

    PrinterOperationResult lastResult =
        PrinterOperationResult(success: false, message: 'Tidak ada salinan tercetak');
    for (int i = 0; i < copies; i++) {
      lastResult = await adapter.printRawBytes(bytes);
      if (!lastResult.success) return lastResult;
    }
    return lastResult;
  }

  static Future<PrinterOperationResult> printServiceNote({
    required PrinterDeviceModel? printer,
    required ServiceOrderModel order,
    required String storeName,
    required String storeAddress,
    required String storePhone,
    required ReceiptConfigModel receiptConfig,
    String? logoPath,
  }) async {
    final target = printer ??
        PrinterDeviceModel(
          name: 'Android Print Service',
          category: PrinterCategory.laser,
          connectionType: PrinterConnectionType.system,
          paperSize: receiptConfig.paperSize,
          protocol: PrinterProtocol.pdf,
          isDefault: true,
        );

    if (target.connectionType == PrinterConnectionType.system ||
        target.protocol == PrinterProtocol.pdf) {
      await DocumentService.printServiceOrderNote(
        order: order,
        storeName: storeName,
        storeAddress: storeAddress,
        storePhone: storePhone,
        logoPath: logoPath,
        thermalPaperSize: target.category == PrinterCategory.thermal ? target.paperSize : null,
      );
      return PrinterOperationResult(success: true, message: 'Nota servis dibuka via PDF Print.');
    }

    final adapter = adapterFor(target);
    final bytes = (target.protocol == PrinterProtocol.escP ||
            target.category == PrinterCategory.dotMatrix)
        ? EscPGenerator.buildServiceNote(
            order: order,
            storeName: storeName,
            storeAddress: storeAddress,
            storePhone: storePhone,
          )
        : EscPosGenerator.buildServiceNote(
            order: order,
            storeName: storeName,
            storeAddress: storeAddress,
            storePhone: storePhone,
            config: receiptConfig,
            charWidth: target.escCharWidth,
            autoCut: target.autoCut,
          );
    return await adapter.printRawBytes(bytes);
  }

  static Future<PrinterOperationResult> printWarehouseDoc({
    required PrinterDeviceModel? printer,
    required WarehouseDocModel doc,
    required String storeName,
    required String storeAddress,
    required String storePhone,
    String? logoPath,
  }) async {
    if (printer != null &&
        printer.connectionType != PrinterConnectionType.system &&
        (printer.protocol == PrinterProtocol.escP ||
            printer.category == PrinterCategory.dotMatrix)) {
      final bytes = EscPGenerator.buildWarehouseDoc(
        doc: doc,
        storeName: storeName,
        storeAddress: storeAddress,
        storePhone: storePhone,
      );
      return await adapterFor(printer).printRawBytes(bytes);
    }

    await DocumentService.printWarehouseDoc(
      docModel: doc,
      storeName: storeName,
      storeAddress: storeAddress,
      storePhone: storePhone,
      logoPath: logoPath,
    );
    return PrinterOperationResult(success: true, message: 'Dokumen A4 dibuka via Print Service.');
  }

  static Future<PrinterOperationResult> printDebtInvoice({
    required PrinterDeviceModel? printer,
    required CustomerDebtModel debt,
    required String storeName,
    required String storeAddress,
    required String storePhone,
    String? logoPath,
  }) async {
    if (printer != null &&
        printer.connectionType != PrinterConnectionType.system &&
        (printer.protocol == PrinterProtocol.escP ||
            printer.category == PrinterCategory.dotMatrix)) {
      final bytes = EscPGenerator.buildDebtInvoice(
        debt: debt,
        storeName: storeName,
        storeAddress: storeAddress,
        storePhone: storePhone,
      );
      return await adapterFor(printer).printRawBytes(bytes);
    }

    await DocumentService.printDebtInvoice(
      debt: debt,
      storeName: storeName,
      storeAddress: storeAddress,
      storePhone: storePhone,
      logoPath: logoPath,
    );
    return PrinterOperationResult(success: true, message: 'Invoice A4 dibuka via Print Service.');
  }

  static Future<PrinterOperationResult> printProductLabels({
    required PrinterDeviceModel? printer,
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
    if (items.isEmpty) {
      return PrinterOperationResult(success: false, message: 'Tidak ada label produk yang dipilih.');
    }

    if (printer != null &&
        printer.connectionType != PrinterConnectionType.system &&
        printer.protocol == PrinterProtocol.escPos &&
        !isA4StickerGrid) {
      final bytes = EscPosGenerator.buildProductLabels(
        items: items
            .map((i) => ProductLabelItem(
                  name: i.name,
                  sku: i.sku,
                  barcodeData: i.barcodeData,
                  price: i.price,
                  copyCount: i.copyCount,
                ))
            .toList(),
        storeName: storeName,
        charWidth: printer.escCharWidth,
        isQrCode: isQrCode,
        showStoreName: showStoreName,
        showPrice: showPrice,
        showSku: showSku,
        autoCut: printer.autoCut,
      );
      return await adapterFor(printer).printRawBytes(bytes);
    }

    await ThermalPrinterService.printProductLabelsBatch(
      items: items,
      storeName: storeName,
      isQrCode: isQrCode,
      showPrice: showPrice,
      showStoreName: showStoreName,
      showSku: showSku,
      labelWidthMm: labelWidthMm,
      labelHeightMm: labelHeightMm,
      isA4StickerGrid: isA4StickerGrid,
    );
    return PrinterOperationResult(
      success: true,
      message: isA4StickerGrid
          ? 'Lembar stiker PDF A4 dibuka lewat Print Service.'
          : 'Label stiker PDF dibuka lewat Print Service.',
    );
  }

  static Future<PrinterOperationResult> openCashDrawer(PrinterDeviceModel? printer) async {
    if (printer == null) {
      return PrinterOperationResult(
        success: false,
        message: 'Belum ada printer Thermal Bluetooth/USB/LAN yang dipilih untuk membuka laci kasir.',
      );
    }
    return await adapterFor(printer).openCashDrawer();
  }
}
