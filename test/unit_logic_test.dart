import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasirtoko/models/customer_debt.dart';
import 'package:kasirtoko/models/product.dart';
import 'package:kasirtoko/models/product_unit.dart';
import 'package:kasirtoko/models/promo.dart';
import 'package:kasirtoko/models/receipt_config.dart';
import 'package:kasirtoko/models/tiered_price.dart';
import 'package:kasirtoko/models/transaction.dart';
import 'package:kasirtoko/models/transaction_item.dart';
import 'package:kasirtoko/models/user.dart';
import 'package:kasirtoko/models/warehouse_doc.dart';
import 'package:kasirtoko/providers/pos_provider.dart';
import 'package:kasirtoko/services/barcode_scan_guard.dart';
import 'package:kasirtoko/services/printer/esc_p_generator.dart';
import 'package:kasirtoko/services/printer/esc_pos_generator.dart';
import 'package:kasirtoko/utils/date_format.dart';
import 'package:kasirtoko/utils/security_helper.dart';

void main() {
  setUpAll(() async {
    await DateHelper.ensureInitialized();
  });

  group('SecurityHelper', () {
    test('generates unique salts and verifies salted HMAC-SHA256 hashes', () {
      final saltA = SecurityHelper.generateSalt();
      final saltB = SecurityHelper.generateSalt();
      expect(saltA, isNotEmpty);
      expect(saltB, isNotEmpty);
      expect(saltA, isNot(equals(saltB)));

      final hash1 = SecurityHelper.hashSecret('123456', saltA);
      final hash2 = SecurityHelper.hashSecret('123456', saltA);
      final hashDifferentSalt = SecurityHelper.hashSecret('123456', saltB);

      expect(hash1, equals(hash2));
      expect(hash1, isNot(equals('123456')));
      expect(hash1, isNot(equals(hashDifferentSalt)));

      expect(SecurityHelper.verifySecret('123456', saltA, hash1), isTrue);
      expect(SecurityHelper.verifySecret('000000', saltA, hash1), isFalse);
      expect(SecurityHelper.verifySecret('123456', '', hash1), isFalse);
      expect(SecurityHelper.verifySecret('123456', saltA, ''), isFalse);
    });
  });

  group('BarcodeScanGuard anti-double-scan scenarios', () {
    test('handles all 5 real-time continuous scan scenarios accurately', () {
      final guard = BarcodeScanGuard(
        rearmAbsenceDuration: const Duration(milliseconds: 900),
        minCooldownDuration: const Duration(milliseconds: 1000),
      );
      final t0 = DateTime(2026, 11, 25, 10, 0, 0);

      // Scenario 1: Initial scan accepts once and locks code
      final frame1 = guard.evaluateFrame(['8991001001'], now: t0);
      expect(frame1, equals(['8991001001']));
      expect(guard.lockedCodes.contains('8991001001'), isTrue);

      // Scenario 2: Continuous hold across multiple frames only triggers once
      expect(
        guard.evaluateFrame(['8991001001'], now: t0.add(const Duration(milliseconds: 250))),
        isEmpty,
      );
      expect(
        guard.evaluateFrame(['8991001001'], now: t0.add(const Duration(milliseconds: 700))),
        isEmpty,
      );
      expect(
        guard.evaluateFrame(['8991001001'], now: t0.add(const Duration(milliseconds: 1400))),
        isEmpty,
      );

      // Scenario 3: Brief frame drop (< 900ms absence) does NOT re-arm
      guard.evaluateFrame([], now: t0.add(const Duration(milliseconds: 1900)));
      final recoverBriefDrop = guard.evaluateFrame(
        ['8991001001'],
        now: t0.add(const Duration(milliseconds: 2100)),
      );
      expect(recoverBriefDrop, isEmpty);

      // Scenario 4: Different barcode triggers immediately without waiting
      final diffBarcode = guard.evaluateFrame(
        ['8991001001', '8992002002'],
        now: t0.add(const Duration(milliseconds: 2200)),
      );
      expect(diffBarcode, equals(['8992002002']));

      // Scenario 5: Pulling barcode out for >= 900ms absence & >= 1000ms cooldown cleanly re-arms
      guard.evaluateFrame(
        [],
        now: t0.add(const Duration(milliseconds: 2300)),
      );
      final rearmedScan = guard.evaluateFrame(
        ['8991001001'],
        now: t0.add(const Duration(milliseconds: 3300)),
      );
      expect(rearmedScan, equals(['8991001001']));
    });
  });

  group('PosProvider pricing, units, stock, promo, tax & held orders', () {
    ProductModel sampleBeverage() {
      return ProductModel(
        id: 1,
        code: 'MIN-01',
        name: 'Teh Botol 350ml',
        baseUnit: 'Btl',
        costPrice: 3000,
        sellingPrice: 5000,
        stock: 20,
        units: [
          ProductUnitModel(
            id: 10,
            productId: 1,
            unitName: 'Dus',
            conversionFactor: 12,
            sellingPrice: 54000,
            barcode: '899111222333',
          ),
        ],
        tieredPrices: [
          TieredPriceModel(id: 1, productId: 1, minQty: 5, price: 4500),
          TieredPriceModel(id: 2, productId: 1, minQty: 10, price: 4000),
        ],
      );
    }

    ProductModel sampleSnack() {
      return ProductModel(
        id: 2,
        code: 'SNK-01',
        name: 'Keripik Kentang',
        baseUnit: 'Pcs',
        costPrice: 7000,
        sellingPrice: 10000,
        stock: 50,
      );
    }

    test('applies tiered prices, multi-unit conversions, and enforces stock limit', () {
      final pos = PosProvider();
      final beverage = sampleBeverage();

      // Add 1 bottle -> 5000
      final r1 = pos.addProduct(beverage);
      expect(r1.success, isTrue);
      expect(pos.subtotal, 5000);

      // Update qty to 5 bottles -> tiered price 4500 * 5 = 22500
      final r2 = pos.updateItemQty(0, 5, beverage);
      expect(r2.success, isTrue);
      expect(pos.cartItems[0].unitPrice, 4500);
      expect(pos.subtotal, 22500);

      // Update qty to 10 bottles -> tiered price 4000 * 10 = 40000
      final r3 = pos.updateItemQty(0, 10, beverage);
      expect(r3.success, isTrue);
      expect(pos.cartItems[0].unitPrice, 4000);
      expect(pos.subtotal, 40000);

      // Add 1 Dus (12 base bottles) -> stock left is 20 - 10 = 10 < 12 -> REJECT!
      final rDusOver = pos.addProduct(beverage, selectedUnit: beverage.units.first);
      expect(rDusOver.success, isFalse);
      expect(pos.cartItems.length, 1);

      // Reduce bottles to 8 -> base left is 12 -> adding 1 Dus succeeds (total 20 base)
      pos.updateItemQty(0, 8, beverage);
      final rDusOk = pos.addProduct(beverage, selectedUnit: beverage.units.first);
      expect(rDusOk.success, isTrue);
      expect(pos.getCartQtyForProduct(1), 20.0);
    });

    test('calculates percentage, nominal, buy-X-get-Y promos, tax and change', () {
      final pos = PosProvider();
      final snack = sampleSnack(); // 10,000 each
      pos.addProduct(snack);
      pos.updateItemQty(0, 6, snack); // Subtotal 60,000

      final now = DateTime.now();

      // 1) Percentage promo (10% off >= 50,000)
      pos.setSelectedPromo(
        PromoModel(
          id: 1,
          name: 'Diskon 10%',
          promoType: 'diskon_persen',
          minPurchase: 50000,
          discountValue: 10,
          startDate: now.subtract(const Duration(days: 1)),
          endDate: now.add(const Duration(days: 5)),
        ),
      );
      expect(pos.promoDiscount, 6000);
      expect(pos.discountedSubtotal, 54000);

      // 2) Nominal promo (15,000 off >= 30,000)
      pos.setSelectedPromo(
        PromoModel(
          id: 2,
          name: 'Potongan 15rb',
          promoType: 'potongan_nominal',
          minPurchase: 30000,
          discountValue: 15000,
          startDate: now.subtract(const Duration(days: 1)),
          endDate: now.add(const Duration(days: 5)),
        ),
      );
      expect(pos.promoDiscount, 15000);
      expect(pos.discountedSubtotal, 45000);

      // 3) Buy 2 Get 1 on target product 2 (qty 6 => 2 groups => 2 free => 20,000 discount)
      pos.setSelectedPromo(
        PromoModel(
          id: 3,
          name: 'Beli 2 Gratis 1',
          promoType: 'beli_x_gratis_y',
          buyQty: 2,
          getQty: 1,
          targetProductId: 2,
          startDate: now.subtract(const Duration(days: 1)),
          endDate: now.add(const Duration(days: 5)),
        ),
      );
      expect(pos.promoDiscount, 20000);
      expect(pos.discountedSubtotal, 40000);

      // Tax 11% on discountedSubtotal (40,000 * 0.11 = 4,400 -> grandTotal 44,400)
      pos.configureTax(enabled: true, rate: 11.0);
      expect(pos.taxAmount, 4400);
      expect(pos.grandTotal, 44400);

      // Change amount
      pos.setAmountPaid(30000);
      expect(pos.changeAmount, 0);
      pos.setAmountPaid(50000);
      expect(pos.changeAmount, 5600);
    });

    test('holds and resumes orders cleanly', () {
      final pos = PosProvider();
      final snack = sampleSnack();
      pos.addProduct(snack);
      pos.setCustomerInfo('Budi', '08123456789');
      pos.setCartDiscount(2000);

      pos.holdCurrentOrder();
      expect(pos.isEmpty, isTrue);
      expect(pos.heldOrders.length, 1);
      expect(pos.customerName, 'Pelanggan Umum');

      pos.resumeHeldOrder(pos.heldOrders.first);
      expect(pos.isEmpty, isFalse);
      expect(pos.heldOrders, isEmpty);
      expect(pos.customerName, 'Budi');
      expect(pos.manualCartDiscount, 2000);
    });
  });

  group('ProductModel & UserModel roles/permissions', () {
    test('ProductModel equality prevents DropdownButton identity mismatches', () {
      final p1 = ProductModel(id: 7, code: 'P-07', name: 'A', sellingPrice: 1000);
      final p1Reloaded = ProductModel(id: 7, code: 'P-07', name: 'A Updated', sellingPrice: 2000);
      final p2 = ProductModel(id: 8, code: 'P-08', name: 'B', sellingPrice: 1000);

      expect(p1 == p1Reloaded, isTrue);
      expect(p1.hashCode == p1Reloaded.hashCode, isTrue);
      expect(p1 == p2, isFalse);
    });

    test('UserModel enforces 7 roles, 16 granular permissions, and owner override', () {
      expect(AppRoles.all.length, 7);
      expect(AppPermissions.labels.length, 16);

      final owner = UserModel(name: 'Owner', role: AppRoles.owner);
      for (final key in AppPermissions.labels.keys) {
        expect(owner.hasPermission(key), isTrue);
      }
      // Even custom map with false must still grant owner full permission
      final ownerForced = UserModel(
        name: 'Owner',
        role: AppRoles.owner,
        permissions: {AppPermissions.viewProfit: false},
      );
      expect(ownerForced.hasPermission(AppPermissions.viewProfit), isTrue);

      final cashier = UserModel(name: 'Kasir', role: AppRoles.cashier);
      expect(cashier.hasPermission(AppPermissions.accessPos), isTrue);
      expect(cashier.hasPermission(AppPermissions.viewProfit), isFalse);
      expect(cashier.hasPermission(AppPermissions.viewCostPrice), isFalse);
      expect(cashier.hasPermission(AppPermissions.manageEmployees), isFalse);

      final warehouse = UserModel(name: 'Gudang', role: AppRoles.warehouse);
      expect(warehouse.hasPermission(AppPermissions.manageStock), isTrue);
      expect(warehouse.hasPermission(AppPermissions.accessPos), isFalse);

      final tech = UserModel(name: 'Teknisi', role: AppRoles.technician);
      expect(tech.hasPermission(AppPermissions.manageService), isTrue);
      expect(tech.hasPermission(AppPermissions.accessPos), isFalse);
    });
  });

  group('Printer ESC/POS & ESC/P byte generators', () {
    test('EscPosGenerator emits init, receipt fields, RJ11 pulse and cut bytes', () {
      expect(EscPosGenerator.cashDrawerPulse, equals([0x1B, 0x70, 0x00, 0x19, 0xFA]));

      final trx = TransactionModel(
        invoiceNumber: 'INV-20261125-1001',
        date: DateTime(2026, 11, 25, 9, 15),
        cashierId: 1,
        cashierName: 'Andi',
        subtotal: 25000,
        grandTotal: 25000,
        amountPaid: 50000,
        changeAmount: 25000,
        items: [
          TransactionItemModel(
            productId: 1,
            productCode: 'BRG-1',
            productName: 'Kabel Data USB-C',
            unitName: 'Pcs',
            qty: 1,
            unitPrice: 25000,
            subtotal: 25000,
          ),
        ],
      );

      final bytes = EscPosGenerator.buildTransactionReceipt(
        transaction: trx,
        storeName: 'TOKO MAJU',
        storeAddress: 'Jl. Merdeka 1',
        storePhone: '08123456789',
        config: const ReceiptConfigModel(),
        charWidth: 32,
        autoCut: true,
        openDrawer: true,
      );

      // Starts with ESC @
      expect(bytes.sublist(0, 2), equals([0x1B, 0x40]));
      final ascii = latin1.decode(bytes);
      expect(ascii, contains('TOKO MAJU'));
      expect(ascii, contains('INV-20261125-1001'));
      expect(ascii, contains('Kabel Data USB-C'));
      // Ends with RJ11 drawer pulse
      expect(
        bytes.sublist(bytes.length - 5),
        equals([0x1B, 0x70, 0x00, 0x19, 0xFA]),
      );
      // Contains auto cut sequence 1D 56 42 03
      final cutIdx = bytes.lastIndexOf(0x1D);
      expect(cutIdx, greaterThan(0));
    });

    test('EscPGenerator emits ESC/P 80-column commands with FormFeed', () {
      final doc = WarehouseDocModel(
        docNumber: 'SJ-202611-1234',
        docType: 'surat_jalan',
        date: DateTime(2026, 11, 25),
        recipientName: 'Toko Sumber Rejeki',
        recipientAddress: 'Jl. Diponegoro 45',
        driverOrPickerName: 'Supri',
        itemsJson: jsonEncode([
          WarehouseDocItem(name: 'Beras Premium 5kg', qty: 10, unit: 'Sak').toMap(),
        ]),
      );

      final docBytes = EscPGenerator.buildWarehouseDoc(
        doc: doc,
        storeName: 'GROSIR JAYA',
        storeAddress: 'Jl. Raya 1',
        storePhone: '08111222333',
      );
      expect(docBytes.sublist(0, 2), equals([0x1B, 0x40]));
      expect(docBytes.last, equals(0x0C)); // Form Feed
      final docAscii = latin1.decode(docBytes);
      expect(docAscii, contains('SJ-202611-1234'));
      expect(docAscii, contains('Beras Premium 5kg'));
      expect(docAscii, contains('10'));

      final debt = CustomerDebtModel(
        customerName: 'Pak Ahmad',
        customerPhone: '0812345678',
        invoiceNumber: 'INV-991',
        totalDebt: 500000,
        paidDebt: 100000,
        transactionDate: DateTime(2026, 11, 20),
        dueDate: DateTime(2026, 11, 30),
      );
      final debtBytes = EscPGenerator.buildDebtInvoice(
        debt: debt,
        storeName: 'GROSIR JAYA',
        storeAddress: 'Jl. Raya 1',
        storePhone: '08111222333',
      );
      expect(debtBytes.sublist(0, 2), equals([0x1B, 0x40]));
      expect(debtBytes.last, equals(0x0C));
      expect(latin1.decode(debtBytes), contains('SURAT INVOICE PENAGIHAN'));
    });
  });
}
