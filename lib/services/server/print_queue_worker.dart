import 'dart:async';

import '../../database/db_helper.dart';
import '../../database/multi_device_dao.dart';
import '../../models/print_job.dart';
import '../../models/printer_device.dart';
import '../../models/receipt_config.dart';
import '../../models/transaction.dart';
import '../printer/printer_adapter.dart';
import '../printer/printer_manager.dart';

typedef PrintReceiptExecutor = Future<PrinterOperationResult> Function(
  PrinterDeviceModel? printer,
  TransactionModel transaction, {
  required String storeName,
  required String storeAddress,
  required String storePhone,
  required ReceiptConfigModel receiptConfig,
  String? logoPath,
  required bool isReprint,
  required bool allowDrawerPulse,
});

typedef OpenDrawerExecutor = Future<PrinterOperationResult> Function(
  PrinterDeviceModel? printer,
);

class PrintQueueWorker {
  final DatabaseHelper _dbHelper;
  final MultiDeviceDao _dao;
  final PrintReceiptExecutor? _customReceiptExecutor;
  final OpenDrawerExecutor? _customDrawerExecutor;
  final int maxAttempts;
  final Duration retryDelay;

  final Set<int> _activePrinterQueues = {};
  bool _disposed = false;

  PrintQueueWorker({
    DatabaseHelper? dbHelper,
    MultiDeviceDao? dao,
    PrintReceiptExecutor? customReceiptExecutor,
    OpenDrawerExecutor? customDrawerExecutor,
    this.maxAttempts = 3,
    this.retryDelay = const Duration(milliseconds: 250),
  })  : _dbHelper = dbHelper ?? DatabaseHelper.instance,
        _dao = dao ?? MultiDeviceDao(dbHelper: dbHelper),
        _customReceiptExecutor = customReceiptExecutor,
        _customDrawerExecutor = customDrawerExecutor;

  void dispose() {
    _disposed = true;
  }

  /// Schedules asynchronous FIFO draining for [printerId] (or default queue `0`).
  void scheduleDrain({int? printerId}) {
    if (_disposed) return;
    final key = printerId ?? 0;
    if (_activePrinterQueues.contains(key)) return;
    _activePrinterQueues.add(key);
    unawaited(_drainLoop(key, printerId));
  }

  /// Synchronously awaits draining for tests or immediate diagnostic flushes.
  Future<void> drainNow({int? printerId}) async {
    final key = printerId ?? 0;
    while (_activePrinterQueues.contains(key)) {
      await Future.delayed(const Duration(milliseconds: 20));
    }
    _activePrinterQueues.add(key);
    await _drainLoop(key, printerId);
  }

  Future<void> _drainLoop(int queueKey, int? printerId) async {
    try {
      while (!_disposed) {
        final job = await _dao.claimNextQueuedPrintJob(printerId: printerId);
        if (job == null) break;
        _notifyUpdate(job);
        await _executeJob(job);
      }
    } finally {
      _activePrinterQueues.remove(queueKey);
    }
  }

  Future<void> _executeJob(PrintJobModel job) async {
    try {
      final printers = await _dbHelper.getPrinters();
      PrinterDeviceModel? printer = _resolvePrinter(printers, job.printerId);

      // Guard 1: Headless server cannot pop interactive Android Print PDF dialogs
      if (printer != null &&
          (printer.connectionType == PrinterConnectionType.system ||
              printer.protocol == PrinterProtocol.pdf)) {
        final terminalJob = await _dao.updatePrintJobState(
          job.id!,
          status: PrintJobStatus.failed,
          errorMessage:
              'PRINTER_NOT_HEADLESS: Printer target bertipe PDF/Android Print Service yang memerlukan interaksi layar Admin. Atur printer Bluetooth/USB/LAN sebagai printer kasir.',
          markCompleted: true,
        );
        _notifyUpdate(terminalJob);
        return;
      }

      if (job.jobType == PrintJobType.manualDrawer) {
        if (printer == null) {
          final failed = await _dao.updatePrintJobState(
            job.id!,
            status: PrintJobStatus.failed,
            errorMessage: 'PRINTER_OFFLINE: Tidak ada printer ESC/POS terdaftar untuk membuka laci.',
            markCompleted: true,
          );
          _notifyUpdate(failed);
          return;
        }
        final won = await _dao.claimOneShotDrawerPulse(job.id!);
        if (!won) {
          final done = await _dao.updatePrintJobState(
            job.id!,
            status: PrintJobStatus.submitted,
            markCompleted: true,
          );
          _notifyUpdate(done);
          return;
        }
        final res = await (_customDrawerExecutor != null
            ? _customDrawerExecutor(printer)
            : PrinterManager.openCashDrawer(printer));
        await _finishAttempt(job, res);
        return;
      }

      // Standard receipt or reprint job
      final trxId = job.transactionId;
      final trx = trxId != null
          ? await _dao.getTransactionById(trxId)
          : (job.invoiceNumber.isNotEmpty
              ? await _dbHelper.getTransactionByInvoice(job.invoiceNumber)
              : null);
      if (trx == null) {
        final failed = await _dao.updatePrintJobState(
          job.id!,
          status: PrintJobStatus.failed,
          errorMessage: 'Data transaksi tidak ditemukan untuk job cetak ${job.jobUuid}.',
          markCompleted: true,
        );
        _notifyUpdate(failed);
        return;
      }

      if (printer == null) {
        final failed = await _dao.updatePrintJobState(
          job.id!,
          status: PrintJobStatus.failed,
          errorMessage:
              'PRINTER_OFFLINE: Belum ada printer thermal/ESC/POS terhubung di Admin.',
          markCompleted: true,
        );
        _notifyUpdate(failed);
        return;
      }

      // Strict 6 cash drawer rules:
      // 1. Reprint NEVER opens drawer
      // 2. Only paymentMethod == 'tunai' may auto-open
      // 3. Only when job.openDrawerRequested == true (terminal allowed & permission checked)
      // 4. Only once globally via atomic claimOneShotDrawerPulse (drawer_pulse_sent 0->1)
      bool allowDrawerPulse = false;
      if (!job.isReprint &&
          job.openDrawerRequested &&
          !job.drawerPulseSent &&
          trx.paymentMethod == 'tunai' &&
          printer.openDrawer) {
        allowDrawerPulse = await _dao.claimOneShotDrawerPulse(job.id!);
      }

      final settings = await _dbHelper.getAllSettings();
      final storeName = settings['store_name'] ?? 'KasirToko';
      final storeAddress = settings['store_address'] ?? '';
      final storePhone = settings['store_phone'] ?? '';
      final logoPath = settings['logo_path'];
      final rawConfig = settings['receipt_config_json'] ?? '';
      final receiptConfig = rawConfig.isNotEmpty
          ? ReceiptConfigModel.fromJson(rawConfig)
          : ReceiptConfigModel(
              paperSize: printer.paperSize,
              footerText: settings['receipt_footer'] ?? 'Terima kasih atas kunjungan Anda!',
            );

      final res = await (_customReceiptExecutor != null
          ? _customReceiptExecutor(
              printer,
              trx,
              storeName: storeName,
              storeAddress: storeAddress,
              storePhone: storePhone,
              receiptConfig: receiptConfig,
              logoPath: logoPath,
              isReprint: job.isReprint,
              allowDrawerPulse: allowDrawerPulse,
            )
          : PrinterManager.printTransactionReceipt(
              printer: printer,
              transaction: trx,
              storeName: storeName,
              storeAddress: storeAddress,
              storePhone: storePhone,
              receiptConfig: receiptConfig,
              logoPath: logoPath,
              isReprint: job.isReprint,
              overrideOpenDrawer: allowDrawerPulse,
            ));

      await _finishAttempt(job, res);
    } catch (e) {
      await _finishAttempt(
        job,
        PrinterOperationResult(success: false, message: 'Gagal memproses job cetak: $e'),
      );
    }
  }

  Future<void> _finishAttempt(PrintJobModel job, PrinterOperationResult res) async {
    if (res.success) {
      final done = await _dao.updatePrintJobState(
        job.id!,
        status: PrintJobStatus.submitted,
        errorMessage: '',
        markCompleted: true,
      );
      _notifyUpdate(done);
      return;
    }

    if (job.attempts < maxAttempts) {
      final retrying = await _dao.updatePrintJobState(
        job.id!,
        status: PrintJobStatus.retrying,
        errorMessage: res.message,
      );
      _notifyUpdate(retrying);
      await Future.delayed(retryDelay);
    } else {
      final failed = await _dao.updatePrintJobState(
        job.id!,
        status: PrintJobStatus.failed,
        errorMessage: res.message,
        markCompleted: true,
      );
      _notifyUpdate(failed);
    }
  }

  PrinterDeviceModel? _resolvePrinter(List<PrinterDeviceModel> printers, int? preferredId) {
    if (printers.isEmpty) return null;
    if (preferredId != null) {
      for (final p in printers) {
        if (p.id == preferredId) return p;
      }
    }
    for (final p in printers) {
      if (p.isDefault && p.connectionType != PrinterConnectionType.system) return p;
    }
    for (final p in printers) {
      if (p.connectionType != PrinterConnectionType.system) return p;
    }
    return printers.first;
  }

  void _notifyUpdate(PrintJobModel job) {
    _dbHelper.onMultiDeviceEvent?.call('print_job_updated', job.toApiJson());
  }
}
