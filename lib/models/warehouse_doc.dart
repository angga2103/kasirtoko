class WarehouseDocModel {
  final int? id;
  final String docNumber;
  final String docType; // 'surat_jalan', 'surat_ambil_barang', 'invoice_penagihan'
  final DateTime date;
  final String recipientName;
  final String recipientAddress;
  final String recipientPhone;
  final String driverOrPickerName;
  final String vehicleNumber;
  final String note;
  final String status; // 'draft', 'dikirim', 'selesai'
  final String itemsJson; // Serialized list of items (name, qty, unit, note)

  WarehouseDocModel({
    this.id,
    required this.docNumber,
    required this.docType,
    required this.date,
    required this.recipientName,
    this.recipientAddress = '',
    this.recipientPhone = '',
    this.driverOrPickerName = '',
    this.vehicleNumber = '',
    this.note = '',
    this.status = 'selesai',
    required this.itemsJson,
  });

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
      'id': id,
      'doc_number': docNumber,
      'doc_type': docType,
      'date': date.toIso8601String(),
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
      id: map['id'],
      docNumber: map['doc_number'],
      docType: map['doc_type'],
      date: DateTime.parse(map['date']),
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
