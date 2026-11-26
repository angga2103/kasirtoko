import 'dart:async';
import 'dart:convert';
import 'dart:math';

import '../../database/db_helper.dart';
import '../../database/multi_device_dao.dart';
import '../../models/cash_register.dart';
import '../../models/paired_terminal.dart';
import '../../models/print_job.dart';
import '../../models/product.dart';
import '../../models/product_unit.dart';
import '../../models/promo.dart';
import '../../models/receipt_config.dart';
import '../../models/transaction.dart';
import '../../models/transaction_item.dart';
import '../../models/user.dart';

class CheckoutDomainException implements Exception {
  final int httpStatus;
  final String errorCode;
  final String message;
  final Map<String, dynamic> details;

  const CheckoutDomainException({
    required this.httpStatus,
    required this.errorCode,
    required this.message,
    this.details = const {},
  });

  @override
  String toString() => '$errorCode: $message';
}

class AuthoritativeCheckoutResult {
  final TransactionModel transaction;
  final bool idempotentReplay;
  final PrintJobModel? printJob;

  const AuthoritativeCheckoutResult({
    required this.transaction,
    required this.idempotentReplay,
    this.printJob,
  });
}

class AuthoritativeCheckoutService {
  final DatabaseHelper _dbHelper;
  final MultiDeviceDao _dao;

  /// Serializes asynchronous checkout orchestration so concurrent requests from N
  /// terminals never race pricing, stock, credit balance, or invoice generation.
  Future<void> _mutexChain = Future<void>.value();

  AuthoritativeCheckoutService({
    DatabaseHelper? dbHelper,
    MultiDeviceDao? dao,
  })  : _dbHelper = dbHelper ?? DatabaseHelper.instance,
        _dao = dao ?? MultiDeviceDao(dbHelper: dbHelper);

  Future<T> _synchronized<T>(Future<T> Function() action) {
    final prev = _mutexChain;
    final completer = Completer<void>();
    _mutexChain = completer.future;
    return prev.then((_) => action()).whenComplete(() {
      if (!completer.isCompleted) completer.complete();
    });
  }

  Future<AuthoritativeCheckoutResult> executeStaffCheckout({
    required PairedTerminalModel terminal,
    required UserModel cashier,
    required String idempotencyKey,
    required Map<String, dynamic> payload,
  }) {
    return _synchronized(() => _executeLocked(
          terminal: terminal,
          cashier: cashier,
          idempotencyKey: idempotencyKey,
          payload: payload,
        ));
  }

  Future<AuthoritativeCheckoutResult> _executeLocked({
    required PairedTerminalModel terminal,
    required UserModel cashier,
    required String idempotencyKey,
    required Map<String, dynamic> payload,
  }) async {
    final cleanIdem = idempotencyKey.trim();
    if (cleanIdem.isEmpty) {
      throw const CheckoutDomainException(
        httpStatus: 400,
        errorCode: 'VALIDATION_ERROR',
        message: 'Header X-Idempotency-Key wajib disertakan untuk transaksi.',
      );
    }

    // 1. Idempotency replay guard
    final existingTrx = await _dao.getTransactionByIdempotencyKey(cleanIdem);
    if (existingTrx != null) {
      final existingJob = await _findAutoPrintJobForKey(cleanIdem);
      return AuthoritativeCheckoutResult(
        transaction: existingTrx,
        idempotentReplay: true,
        printJob: existingJob,
      );
    }

    final rawItems = payload['items'];
    if (rawItems is! List || rawItems.isEmpty) {
      throw const CheckoutDomainException(
        httpStatus: 400,
        errorCode: 'VALIDATION_ERROR',
        message: 'Keranjang belanja kosong.',
      );
    }

    // 2. Shift & Cash Register validation
    final requestedShiftId = (payload['shift_id'] as num?)?.toInt();
    final requestedRegId = (payload['cash_register_id'] as num?)?.toInt();

    late final CashRegisterModel authorizedReg;
    try {
      authorizedReg = await _dbHelper.resolveAuthorizedCashRegister(
        cashierId: cashier.id!,
        terminalId: terminal.terminalId,
        requestedRegisterId: requestedRegId,
      );
    } catch (e) {
      throw CheckoutDomainException(
        httpStatus: 409,
        errorCode: 'REGISTER_UNAUTHORIZED',
        message: e.toString().replaceFirst('Bad state: ', ''),
      );
    }

    final activeShift = await _dbHelper.getCurrentOpenShift(
      cashierId: cashier.id,
      terminalId: terminal.terminalId,
      cashRegisterId: authorizedReg.id,
    );
    if (activeShift == null || !activeShift.isOpen) {
      throw const CheckoutDomainException(
        httpStatus: 409,
        errorCode: 'SHIFT_CLOSED',
        message: 'Shift pada laci kas yang ditugaskan belum dibuka.',
      );
    }
    if (requestedShiftId != null && requestedShiftId != activeShift.id) {
      throw CheckoutDomainException(
        httpStatus: 409,
        errorCode: 'SHIFT_CONFLICT',
        message: 'Shift aktif saat ini adalah #${activeShift.id}, bukan #$requestedShiftId.',
      );
    }
    if (activeShift.drawerMode == DrawerMode.individualDrawer &&
        activeShift.cashierId != cashier.id) {
      throw const CheckoutDomainException(
        httpStatus: 409,
        errorCode: 'SHIFT_CONFLICT',
        message: 'Mode INDIVIDUAL_DRAWER: kasir wajib bertransaksi pada shift pribadinya sendiri.',
      );
    }

    // 3. Discounts permission verification
    final manualDiscount = ((payload['manual_discount'] as num?)?.toDouble() ?? 0.0).clamp(0.0, double.infinity);
    var hasItemDiscount = false;
    for (final raw in rawItems) {
      final m = Map<String, dynamic>.from(raw as Map);
      if (((m['item_discount'] as num?)?.toDouble() ?? 0.0) > 0.0) {
        hasItemDiscount = true;
        break;
      }
    }
    if ((manualDiscount > 0 || hasItemDiscount) &&
        !cashier.hasPermission(AppPermissions.applyDiscount)) {
      throw const CheckoutDomainException(
        httpStatus: 403,
        errorCode: 'PERMISSION_DENIED',
        message: 'Akun Anda tidak memiliki izin memberikan diskon manual.',
      );
    }

    // 4. Authoritative line items, units, tiered pricing & stock resolution
    final db = await _dbHelper.database;
    final resolvedItems = <TransactionItemModel>[];
    final requestedQtyPerProduct = <int, double>{};

    for (final raw in rawItems) {
      if (raw is! Map) {
        throw const CheckoutDomainException(
          httpStatus: 400,
          errorCode: 'VALIDATION_ERROR',
          message: 'Format item transaksi tidak valid.',
        );
      }
      final m = Map<String, dynamic>.from(raw);
      final productId = (m['product_id'] as num?)?.toInt();
      final qty = (m['qty'] as num?)?.toDouble() ?? 0.0;
      final unitNameReq = (m['unit_name'] ?? '').toString().trim();
      final itemDiscount = ((m['item_discount'] as num?)?.toDouble() ?? 0.0).clamp(0.0, double.infinity);

      if (productId == null || qty <= 0) {
        throw const CheckoutDomainException(
          httpStatus: 400,
          errorCode: 'VALIDATION_ERROR',
          message: 'Produk ID dan qty (> 0) wajib valid.',
        );
      }

      final pRows = await db.query(
        'products',
        where: 'id = ? AND is_active = 1',
        whereArgs: [productId],
        limit: 1,
      );
      if (pRows.isEmpty) {
        throw CheckoutDomainException(
          httpStatus: 409,
          errorCode: 'PRICE_OR_PROMO_CHANGED',
          message: 'Produk ID #$productId tidak ditemukan atau sudah dinonaktifkan Admin.',
        );
      }
      final ProductModel product = await _dbHelper.hydrateProductTxn(db, pRows.first);

      String finalUnitName = product.baseUnit;
      double conversion = 1.0;
      double unitPrice = product.tieredPrices.isNotEmpty
          ? product.getPriceForQty(qty)
          : product.sellingPrice;

      if (unitNameReq.isNotEmpty && unitNameReq != product.baseUnit) {
        ProductUnitModel? matchedUnit;
        for (final u in product.units) {
          if (u.unitName.toLowerCase() == unitNameReq.toLowerCase()) {
            matchedUnit = u;
            break;
          }
        }
        if (matchedUnit == null) {
          throw CheckoutDomainException(
            httpStatus: 409,
            errorCode: 'PRICE_OR_PROMO_CHANGED',
            message: 'Satuan "$unitNameReq" pada "${product.name}" telah berubah di Admin.',
          );
        }
        finalUnitName = matchedUnit.unitName;
        conversion = matchedUnit.conversionFactor;
        unitPrice = matchedUnit.sellingPrice;
      }

      final grossLine = qty * unitPrice;
      if (itemDiscount > grossLine + 0.01) {
        throw CheckoutDomainException(
          httpStatus: 400,
          errorCode: 'VALIDATION_ERROR',
          message: 'Diskon item "${product.name}" melebihi subtotal item.',
        );
      }
      final netLine = (grossLine - itemDiscount).clamp(0.0, double.infinity);
      final baseDeduct = product.isService ? 0.0 : qty * conversion;

      if (product.managesStock) {
        requestedQtyPerProduct[product.id!] =
            (requestedQtyPerProduct[product.id!] ?? 0.0) + baseDeduct;
        if (requestedQtyPerProduct[product.id!]! > product.stock + 0.0001) {
          throw CheckoutDomainException(
            httpStatus: 409,
            errorCode: 'INSUFFICIENT_STOCK',
            message:
                'Stok "${product.name}" tidak mencukupi (tersedia ${product.stock}, diminta ${requestedQtyPerProduct[product.id!]}).',
            details: {
              'product_id': product.id,
              'available_stock': product.stock,
              'requested_qty': requestedQtyPerProduct[product.id!],
            },
          );
        }
      }

      resolvedItems.add(
        TransactionItemModel(
          productId: product.id!,
          productCode: product.code,
          productName: product.name,
          unitName: finalUnitName,
          conversionFactor: conversion,
          qty: qty,
          unitPrice: unitPrice,
          discount: itemDiscount,
          subtotal: netLine,
          costPrice: product.costPrice, // Stored safely on Admin DB ONLY; stripped from LAN response!
          isService: product.isService,
        ),
      );
    }

    final subtotal = resolvedItems.fold<double>(0.0, (s, e) => s + e.subtotal);

    // 5. Promo evaluation
    PromoModel? promo;
    final promoId = (payload['promo_id'] as num?)?.toInt();
    double promoDiscount = 0.0;
    if (promoId != null) {
      final promos = await _dbHelper.getActivePromos();
      for (final p in promos) {
        if (p.id == promoId && p.isRunning) {
          promo = p;
          break;
        }
      }
      if (promo == null) {
        throw const CheckoutDomainException(
          httpStatus: 409,
          errorCode: 'PRICE_OR_PROMO_CHANGED',
          message: 'Promo yang dipilih sudah tidak aktif atau berakhir.',
        );
      }
      promoDiscount = _computePromoDiscount(promo, subtotal, resolvedItems);
    }

    final combinedDiscount = (manualDiscount + promoDiscount).clamp(0.0, subtotal);
    final discountedSubtotal = (subtotal - combinedDiscount).clamp(0.0, subtotal);

    // 6. Tax & Store Settings
    final settings = await _dbHelper.getAllSettings();
    final taxEnabled = (settings['tax_enabled'] ?? '0') == '1';
    final taxRate = double.tryParse(settings['tax_rate'] ?? '0') ?? 0.0;
    final taxAmount = (taxEnabled && taxRate > 0) ? discountedSubtotal * (taxRate / 100.0) : 0.0;
    final grandTotal = discountedSubtotal + taxAmount;

    final expectedGrandTotal = (payload['expected_grand_total'] as num?)?.toDouble();
    if (expectedGrandTotal != null && (expectedGrandTotal - grandTotal).abs() > 1.0) {
      throw CheckoutDomainException(
        httpStatus: 409,
        errorCode: 'PRICE_OR_PROMO_CHANGED',
        message:
            'Total server berubah (Server Rp ${grandTotal.toStringAsFixed(0)} vs Terminal Rp ${expectedGrandTotal.toStringAsFixed(0)}). Sinkronkan katalog terlebih dahulu.',
        details: {
          'server_grand_total': grandTotal,
          'expected_grand_total': expectedGrandTotal,
          'server_subtotal': subtotal,
          'server_discount_total': combinedDiscount,
          'server_tax_amount': taxAmount,
        },
      );
    }

    // 7. Customer & Payment validation
    final customerId = (payload['customer_id'] as num?)?.toInt();
    String customerName = (payload['customer_name'] ?? 'Pelanggan Umum').toString().trim();
    String customerPhone = (payload['customer_phone'] ?? '').toString().trim();
    if (customerName.isEmpty) customerName = 'Pelanggan Umum';

    final requestedMethod = (payload['payment_method'] ?? 'tunai').toString().trim().toLowerCase();
    const allowedMethods = {'tunai', 'qris', 'transfer', 'kasbon', 'saldo_kredit'};
    if (!allowedMethods.contains(requestedMethod)) {
      throw const CheckoutDomainException(
        httpStatus: 400,
        errorCode: 'VALIDATION_ERROR',
        message: 'Metode pembayaran tidak valid.',
      );
    }

    final creditUsed = ((payload['credit_used'] as num?)?.toDouble() ?? 0.0).clamp(0.0, grandTotal);
    final netDue = (grandTotal - creditUsed).clamp(0.0, grandTotal);
    final effectiveMethod = netDue <= 0.01 && creditUsed > 0 ? 'saldo_kredit' : requestedMethod;
    final rawAmountPaid = (payload['amount_paid'] as num?)?.toDouble() ?? 0.0;

    if (effectiveMethod == 'tunai' && rawAmountPaid + 0.01 < netDue) {
      throw CheckoutDomainException(
        httpStatus: 400,
        errorCode: 'VALIDATION_ERROR',
        message:
            'Nominal uang tunai kurang (Tagihan Rp ${netDue.toStringAsFixed(0)}, Dibayar Rp ${rawAmountPaid.toStringAsFixed(0)}).',
      );
    }
    if ((effectiveMethod == 'kasbon' || effectiveMethod == 'saldo_kredit' || creditUsed > 0) &&
        (customerId == null || customerName.toLowerCase() == 'pelanggan umum')) {
      throw const CheckoutDomainException(
        httpStatus: 409,
        errorCode: 'INVALID_CUSTOMER_RULE',
        message: 'Pelanggan Umum tidak dapat menggunakan Kasbon atau Saldo Kredit. Pilih pelanggan terdaftar.',
      );
    }
    if (creditUsed > 0 && customerId != null) {
      final bal = await _dbHelper.getCustomerCreditBalance(customerId);
      if (bal + 0.01 < creditUsed) {
        throw CheckoutDomainException(
          httpStatus: 409,
          errorCode: 'INSUFFICIENT_CREDIT',
          message:
              'Saldo kredit tidak mencukupi (Tersedia Rp ${bal.toStringAsFixed(0)}, Diminta Rp ${creditUsed.toStringAsFixed(0)}).',
        );
      }
    }

    final double finalPaid = (effectiveMethod == 'tunai' || effectiveMethod == 'kasbon')
        ? rawAmountPaid
        : netDue;
    final double finalChange = effectiveMethod == 'tunai'
        ? (finalPaid - netDue).clamp(0.0, double.infinity)
        : 0.0;

    // 8. Official Server Invoice & Atomic DB Insert
    final now = DateTime.now();
    final invoiceNumber = _generateServerInvoice(
      prefix: settings['invoice_prefix'] ?? 'INV',
      terminalCode: terminal.terminalCode.isNotEmpty ? terminal.terminalCode : terminal.terminalId,
      now: now,
    );
    final receiptConfigRaw = settings['receipt_config_json'] ?? '';
    final receiptConfig = receiptConfigRaw.isNotEmpty
        ? ReceiptConfigModel.fromJson(receiptConfigRaw)
        : ReceiptConfigModel(
            paperSize: settings['printer_paper_size'] ?? '58mm',
            footerText: settings['receipt_footer'] ?? 'Terima kasih atas kunjungan Anda!',
          );
    final snapshot = {
      'store_name': settings['store_name'] ?? 'KasirToko',
      'store_address': settings['store_address'] ?? '',
      'store_phone': settings['store_phone'] ?? '',
      'receipt_config': receiptConfig.toMap(),
      'printed_at': now.toIso8601String(),
    };

    final trx = TransactionModel(
      invoiceNumber: invoiceNumber,
      date: now,
      cashierId: cashier.id!,
      cashierName: cashier.name,
      terminalId: terminal.terminalId,
      cashRegisterId: authorizedReg.id ?? 1,
      idempotencyKey: cleanIdem,
      customerId: customerId,
      shiftId: activeShift.id,
      customerName: customerName,
      customerPhone: customerPhone,
      subtotal: subtotal,
      discountTotal: combinedDiscount,
      taxAmount: taxAmount,
      promoName: promo?.name ?? '',
      grandTotal: grandTotal,
      paymentMethod: effectiveMethod,
      creditUsed: creditUsed,
      amountPaid: finalPaid,
      changeAmount: finalChange,
      status: 'completed',
      qrCodePayload: 'TRX|$invoiceNumber|${grandTotal.toInt()}',
      note: (payload['note'] ?? '').toString(),
      printerSnapshotJson: jsonEncode(snapshot),
      items: resolvedItems,
    );

    late final int insertedId;
    try {
      insertedId = await _dbHelper.insertTransactionWithBroadcast(
        trx,
        shiftId: activeShift.id,
        terminalId: terminal.terminalId,
        cashRegisterId: authorizedReg.id,
      );
    } catch (e) {
      throw CheckoutDomainException(
        httpStatus: 409,
        errorCode: 'INSUFFICIENT_STOCK',
        message: e.toString().replaceFirst('Bad state: ', ''),
      );
    }

    await db.insert('audit_logs', {
      'timestamp': now.toIso8601String(),
      'user_id': cashier.id ?? 0,
      'user_name': cashier.name,
      'user_role': cashier.role,
      'action_type': 'transaksi_staff',
      'module': 'POS Multi-Perangkat',
      'object_id': invoiceNumber,
      'before_value': '',
      'after_value':
          'terminal=${terminal.terminalId}, shift=${activeShift.id}, reg=${authorizedReg.id}, total=${grandTotal.toStringAsFixed(0)}, method=$effectiveMethod',
      'details': 'Transaksi $invoiceNumber disahkan oleh server untuk ${terminal.terminalName} (${cashier.name}).',
    });

    final savedTrx = (await _dao.getTransactionById(insertedId))!;

    // 9. Post-commit Print Enqueue with strict drawer guards
    final autoPrintSetting = (settings['auto_print_staff_transactions'] ?? '1') == '1';
    final requestPrint = payload['request_print'] is bool
        ? payload['request_print'] as bool
        : autoPrintSetting;

    PrintJobModel? printJob;
    if (requestPrint) {
      final printerId = terminal.defaultPrinterId ?? authorizedReg.printerId;
      final canAutoOpenDrawer =
          effectiveMethod == 'tunai' && terminal.allowAutoOpenDrawer;
      printJob = await _dao.enqueuePrintJob(
        terminalId: terminal.terminalId,
        cashierId: cashier.id,
        transactionId: savedTrx.id,
        invoiceNumber: savedTrx.invoiceNumber,
        printerId: printerId,
        jobType: PrintJobType.receipt,
        isReprint: false,
        openDrawerRequested: canAutoOpenDrawer,
        idempotencyKey: 'AUTO:$cleanIdem',
      );
    }

    return AuthoritativeCheckoutResult(
      transaction: savedTrx,
      idempotentReplay: false,
      printJob: printJob,
    );
  }

  Future<PrintJobModel?> _findAutoPrintJobForKey(String idemKey) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'print_jobs',
      where: 'idempotency_key = ?',
      whereArgs: ['AUTO:$idemKey'],
      limit: 1,
    );
    return rows.isNotEmpty ? PrintJobModel.fromMap(rows.first) : null;
  }

  double _computePromoDiscount(
    PromoModel promo,
    double subtotal,
    List<TransactionItemModel> items,
  ) {
    if (promo.promoType == 'diskon_persen') {
      if (subtotal < promo.minPurchase) return 0.0;
      return subtotal * (promo.discountValue.clamp(0.0, 100.0) / 100.0);
    }
    if (promo.promoType == 'potongan_nominal') {
      if (subtotal < promo.minPurchase) return 0.0;
      return promo.discountValue.clamp(0.0, subtotal);
    }
    if (promo.promoType == 'beli_x_gratis_y') {
      final buyQty = promo.buyQty ?? 0;
      final getQty = promo.getQty ?? 0;
      if (buyQty <= 0 || getQty <= 0) return 0.0;
      double freeDiscount = 0.0;
      for (final item in items) {
        if (promo.targetProductId != null && item.productId != promo.targetProductId) {
          continue;
        }
        final groupSize = buyQty + getQty;
        final eligibleGroups = item.qty ~/ groupSize;
        if (eligibleGroups > 0) {
          freeDiscount += eligibleGroups * getQty * item.unitPrice;
        }
      }
      return freeDiscount;
    }
    return 0.0;
  }

  String _generateServerInvoice({
    required String prefix,
    required String terminalCode,
    required DateTime now,
  }) {
    final cleanPrefix = prefix.trim().isEmpty ? 'INV' : prefix.trim();
    final dateStr =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final rand = (Random.secure().nextInt(9000) + 1000).toString();
    final shortTerm = terminalCode.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    final tag = shortTerm.length > 6 ? shortTerm.substring(shortTerm.length - 6) : shortTerm;
    return '$cleanPrefix-$tag-$dateStr-$rand';
  }
}
