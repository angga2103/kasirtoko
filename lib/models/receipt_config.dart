import 'dart:convert';

class ReceiptTemplateType {
  static const String minimalist = 'minimalis';
  static const String professional = 'profesional';
  static const String retail = 'retail';
  static const String phoneCounter = 'konter_hp';
  static const String service = 'servis';

  static const List<String> all = [
    minimalist,
    professional,
    retail,
    phoneCounter,
    service,
  ];

  static String label(String t) {
    switch (t) {
      case minimalist:
        return 'Minimalis';
      case professional:
        return 'Profesional';
      case retail:
        return 'Retail / Minimarket';
      case phoneCounter:
        return 'Konter HP & Elektronik';
      case service:
        return 'Jasa Servis';
      default:
        return t;
    }
  }
}

class ReceiptConfigModel {
  final String template; // minimalis | profesional | retail | konter_hp | servis
  final String paperSize; // 58mm | 80mm | a4 | continuous
  final String fontSize; // small | normal | large
  final String headerAlignment; // left | center
  final double lineSpacing; // 1.0 | 1.2 | 1.4
  final String dividerStyle; // '-' | '=' | '*'
  final bool showLogo;
  final bool hideStoreNameWithLogo;
  final bool showAddress;
  final bool showPhone;
  final bool showCashier;
  final bool showCustomer;
  final bool showUnitPrice;
  final bool showQty;
  final bool showDiscount;
  final bool showTotal;
  final bool showPaymentMethod;
  final bool showPaidAndChange;
  final bool showQrInvoice;
  final String warrantyInfo;
  final String returnPolicy;
  final String footerText;
  final bool autoPrint;
  final int copyCount;

  const ReceiptConfigModel({
    this.template = ReceiptTemplateType.professional,
    this.paperSize = '58mm',
    this.fontSize = 'normal',
    this.headerAlignment = 'center',
    this.lineSpacing = 1.2,
    this.dividerStyle = '-',
    this.showLogo = true,
    this.hideStoreNameWithLogo = false,
    this.showAddress = true,
    this.showPhone = true,
    this.showCashier = true,
    this.showCustomer = true,
    this.showUnitPrice = true,
    this.showQty = true,
    this.showDiscount = true,
    this.showTotal = true,
    this.showPaymentMethod = true,
    this.showPaidAndChange = true,
    this.showQrInvoice = true,
    this.warrantyInfo = '',
    this.returnPolicy = 'Barang yang sudah dibeli dapat ditukar maksimal 2 hari dengan nota asli.',
    this.footerText = 'Terima kasih telah berbelanja di toko kami!',
    this.autoPrint = false,
    this.copyCount = 1,
  });

  double get basePdfFontSize {
    switch (fontSize) {
      case 'small':
        return 7.5;
      case 'large':
        return 10.0;
      default:
        return 8.5;
    }
  }

  Map<String, dynamic> toMap() => {
        'template': template,
        'paper_size': paperSize,
        'font_size': fontSize,
        'header_alignment': headerAlignment,
        'line_spacing': lineSpacing,
        'divider_style': dividerStyle,
        'show_logo': showLogo,
        'hide_store_name_with_logo': hideStoreNameWithLogo,
        'show_address': showAddress,
        'show_phone': showPhone,
        'show_cashier': showCashier,
        'show_customer': showCustomer,
        'show_unit_price': showUnitPrice,
        'show_qty': showQty,
        'show_discount': showDiscount,
        'show_total': showTotal,
        'show_payment_method': showPaymentMethod,
        'show_paid_and_change': showPaidAndChange,
        'show_qr_invoice': showQrInvoice,
        'warranty_info': warrantyInfo,
        'return_policy': returnPolicy,
        'footer_text': footerText,
        'auto_print': autoPrint,
        'copy_count': copyCount,
      };

  factory ReceiptConfigModel.fromMap(Map<String, dynamic> map) {
    return ReceiptConfigModel(
      template: (map['template'] ?? ReceiptTemplateType.professional).toString(),
      paperSize: (map['paper_size'] ?? '58mm').toString(),
      fontSize: (map['font_size'] ?? 'normal').toString(),
      headerAlignment: (map['header_alignment'] ?? 'center').toString(),
      lineSpacing: (map['line_spacing'] as num?)?.toDouble() ?? 1.2,
      dividerStyle: (map['divider_style'] ?? '-').toString(),
      showLogo: map['show_logo'] ?? true,
      hideStoreNameWithLogo: map['hide_store_name_with_logo'] ?? false,
      showAddress: map['show_address'] ?? true,
      showPhone: map['show_phone'] ?? true,
      showCashier: map['show_cashier'] ?? true,
      showCustomer: map['show_customer'] ?? true,
      showUnitPrice: map['show_unit_price'] ?? true,
      showQty: map['show_qty'] ?? true,
      showDiscount: map['show_discount'] ?? true,
      showTotal: map['show_total'] ?? true,
      showPaymentMethod: map['show_payment_method'] ?? true,
      showPaidAndChange: map['show_paid_and_change'] ?? true,
      showQrInvoice: map['show_qr_invoice'] ?? true,
      warrantyInfo: (map['warranty_info'] ?? '').toString(),
      returnPolicy: (map['return_policy'] ?? '').toString(),
      footerText: (map['footer_text'] ?? 'Terima kasih telah berbelanja!').toString(),
      autoPrint: map['auto_print'] ?? false,
      copyCount: (map['copy_count'] as num?)?.toInt() ?? 1,
    );
  }

  String toJson() => jsonEncode(toMap());

  factory ReceiptConfigModel.fromJson(String raw) {
    if (raw.isEmpty) return const ReceiptConfigModel();
    try {
      return ReceiptConfigModel.fromMap(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
    } catch (_) {
      return const ReceiptConfigModel();
    }
  }

  ReceiptConfigModel copyWith({
    String? template,
    String? paperSize,
    String? fontSize,
    String? headerAlignment,
    double? lineSpacing,
    String? dividerStyle,
    bool? showLogo,
    bool? hideStoreNameWithLogo,
    bool? showAddress,
    bool? showPhone,
    bool? showCashier,
    bool? showCustomer,
    bool? showUnitPrice,
    bool? showQty,
    bool? showDiscount,
    bool? showTotal,
    bool? showPaymentMethod,
    bool? showPaidAndChange,
    bool? showQrInvoice,
    String? warrantyInfo,
    String? returnPolicy,
    String? footerText,
    bool? autoPrint,
    int? copyCount,
  }) {
    return ReceiptConfigModel(
      template: template ?? this.template,
      paperSize: paperSize ?? this.paperSize,
      fontSize: fontSize ?? this.fontSize,
      headerAlignment: headerAlignment ?? this.headerAlignment,
      lineSpacing: lineSpacing ?? this.lineSpacing,
      dividerStyle: dividerStyle ?? this.dividerStyle,
      showLogo: showLogo ?? this.showLogo,
      hideStoreNameWithLogo: hideStoreNameWithLogo ?? this.hideStoreNameWithLogo,
      showAddress: showAddress ?? this.showAddress,
      showPhone: showPhone ?? this.showPhone,
      showCashier: showCashier ?? this.showCashier,
      showCustomer: showCustomer ?? this.showCustomer,
      showUnitPrice: showUnitPrice ?? this.showUnitPrice,
      showQty: showQty ?? this.showQty,
      showDiscount: showDiscount ?? this.showDiscount,
      showTotal: showTotal ?? this.showTotal,
      showPaymentMethod: showPaymentMethod ?? this.showPaymentMethod,
      showPaidAndChange: showPaidAndChange ?? this.showPaidAndChange,
      showQrInvoice: showQrInvoice ?? this.showQrInvoice,
      warrantyInfo: warrantyInfo ?? this.warrantyInfo,
      returnPolicy: returnPolicy ?? this.returnPolicy,
      footerText: footerText ?? this.footerText,
      autoPrint: autoPrint ?? this.autoPrint,
      copyCount: copyCount ?? this.copyCount,
    );
  }
}
