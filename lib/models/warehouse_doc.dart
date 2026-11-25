import 'dart:convert';

class WarehouseDocItem {
  int? productId;
  String name;
  double qty;
  String unit;
  String note;

  WarehouseDocItem({
    this.productId,
    required this.name,
    required this.qty,
    this.unit = 'Pcs',
    this.note = '',
  });

  Map<String, dynamic> toMap() => {
        'product_id': productId,
        'name': name,
        'qty': qty,
        'unit': unit,
        'note': note,
      };

  factory WarehouseDocItem.fromMap(Map<String, dynamic> map) {
    return WarehouseDocItem(
      productId: map['product_id'] as int?,
      name: (map['name'] ?? '').toString(),
      qty: (map['qty'] as num?)?.toDouble() ?? 1.0,
      unit: (map['unit'] ?? 'Pcs').toString(),
      note: (map['note'] ?? '').toString(),
    );
  }
}

class WarehouseDocModel {
  final int? id;
  final String docNumber;
  final String docType; // 'surat_jalan', 'surat_ambil_barang', 'invoice_penagihan'
  final DateTime date;
  final DateTime? deliveryDate;
  final String recipientName;
  final String recipientAddress;
  final String recipientPhone;
  final String driverOrPickerName;
  final String vehicleNumber;
  final String note;
  final String status; // 'draft', 'dikirim', 'selesai'
  final String itemsJson;

  WarehouseDocModel({
    this.id,
    required this.docNumber,
    required this.docType,
    required this.date,
    this.deliveryDate,
    required this.recipientName,
    this.recipientAddress = '',
    this.recipientPhone = '',
    this.driverOrPickerName = '',
    this.vehicleNumber = '',
    this.note = '',
    this.status = 'draft',
    required this.itemsJson,
  });

  List<WarehouseDocItem> get parsedItems {
    try {
      final decoded = jsonDecode(itemsJson) as List<dynamic>;
      return decoded
          .map((e) => WarehouseDocItem.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  String get docTitle {
    switch (docType) {
      case 'surat_jalan':
        return 'SURAT JALAN (DELIVERY ORDER)';
      case 'surat_ambil_barang':
        return 'SURAT PENGAMBILAN BARANG GUDANG';
      case 'invoice_penagihan':
        return 'INVOICE PENAGIHAN PEMBAYARAN';
      default:
        return docType.toUpperCase();
    }
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'doc_number': docNumber,
      'doc_type': docType,
      'date': date.toIso8601String(),
      'delivery_date': deliveryDate?.toIso8601String(),
      'recipient_name': recipientName,
      'recipient_address': recipientAddress,
      'recipient_phone': recipientPhone,
      'driver_or_picker_name': driverOrPickerName,
      'vehicle_number': vehicleNumber,
      'note': note,
      'status': status,
      'items_json': itemsJson,
    };
  }

  factory WarehouseDocModel.fromMap(Map<String, dynamic> map) {
    return WarehouseDocModel(
      id: map['id'] as int?,
      docNumber: map['doc_number'],
      docType: map['doc_type'],
      date: DateTime.parse(map['date']),
      deliveryDate: map['delivery_date'] != null
          ? DateTime.tryParse(map['delivery_date'].toString())
          : null,
      recipientName: map['recipient_name'] ?? '',
      recipientAddress: map['recipient_address'] ?? '',
      recipientPhone: map['recipient_phone'] ?? '',
      driverOrPickerName: map['driver_or_picker_name'] ?? '',
      vehicleNumber: map['vehicle_number'] ?? '',
      note: map['note'] ?? '',
      status: map['status'] ?? 'selesai',
      itemsJson: map['items_json'] ?? '[]',
    );
  }
}
