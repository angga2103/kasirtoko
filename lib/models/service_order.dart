import 'dart:convert';
import 'package:flutter/material.dart';

class ServiceStatus {
  static const String diterima = 'diterima';
  static const String menungguPemeriksaan = 'menunggu_pemeriksaan';
  static const String menungguPersetujuan = 'menunggu_persetujuan';
  static const String dalamPengerjaan = 'dalam_pengerjaan';
  static const String menungguSparepart = 'menunggu_sparepart';
  static const String selesai = 'selesai';
  static const String sudahDiambil = 'sudah_diambil';
  static const String dibatalkan = 'dibatalkan';

  static const List<String> all = [
    diterima,
    menungguPemeriksaan,
    menungguPersetujuan,
    dalamPengerjaan,
    menungguSparepart,
    selesai,
    sudahDiambil,
    dibatalkan,
  ];

  static String label(String status) {
    switch (status) {
      case diterima:
        return 'Diterima';
      case menungguPemeriksaan:
        return 'Menunggu Pemeriksaan';
      case menungguPersetujuan:
        return 'Menunggu Persetujuan';
      case dalamPengerjaan:
        return 'Dalam Pengerjaan';
      case menungguSparepart:
        return 'Menunggu Sparepart';
      case selesai:
        return 'Selesai';
      case sudahDiambil:
        return 'Sudah Diambil';
      case dibatalkan:
        return 'Dibatalkan';
      default:
        return status;
    }
  }

  static Color color(String status) {
    switch (status) {
      case diterima:
        return Colors.blue;
      case menungguPemeriksaan:
        return Colors.indigo;
      case menungguPersetujuan:
        return Colors.amber.shade800;
      case dalamPengerjaan:
        return Colors.orange.shade800;
      case menungguSparepart:
        return Colors.deepPurple;
      case selesai:
        return Colors.teal;
      case sudahDiambil:
        return Colors.green;
      case dibatalkan:
        return Colors.red;
      default:
        return Colors.grey;
    }
  }
}

class ServicePartModel {
  final int? id;
  final int? serviceOrderId;
  final int? productId;
  final String productName;
  final double qty;
  final String unitName;
  final double conversionFactor;
  final double unitPrice;
  final double costPrice;
  final double subtotal;

  ServicePartModel({
    this.id,
    this.serviceOrderId,
    this.productId,
    required this.productName,
    this.qty = 1.0,
    this.unitName = 'Pcs',
    this.conversionFactor = 1.0,
    required this.unitPrice,
    this.costPrice = 0.0,
    required this.subtotal,
  });

  double get baseStockQty => qty * conversionFactor;

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'service_order_id': serviceOrderId,
        'product_id': productId,
        'product_name': productName,
        'qty': qty,
        'unit_name': unitName,
        'conversion_factor': conversionFactor,
        'unit_price': unitPrice,
        'cost_price': costPrice,
        'subtotal': subtotal,
      };

  factory ServicePartModel.fromMap(Map<String, dynamic> map) {
    return ServicePartModel(
      id: map['id'] as int?,
      serviceOrderId: map['service_order_id'] as int?,
      productId: map['product_id'] as int?,
      productName: (map['product_name'] ?? '').toString(),
      qty: (map['qty'] as num?)?.toDouble() ?? 1.0,
      unitName: (map['unit_name'] ?? 'Pcs').toString(),
      conversionFactor: (map['conversion_factor'] as num?)?.toDouble() ?? 1.0,
      unitPrice: (map['unit_price'] as num).toDouble(),
      costPrice: (map['cost_price'] as num?)?.toDouble() ?? 0.0,
      subtotal: (map['subtotal'] as num).toDouble(),
    );
  }
}

class ServiceOrderModel {
  final int? id;
  final String ticketNumber;
  final int? customerId;
  final String customerName;
  final String customerPhone;
  final String deviceType; // 'HP', 'Laptop', 'TV', 'Elektronik', dll
  final String brand;
  final String model;
  final String imeiSn;
  final String accessories; // Dus, Charger, SIM Tray, Casing, dll
  final String complaint;
  final String physicalCondition;
  final List<String> photoPaths;
  final int? technicianId;
  final String technicianName;
  final double estimatedCost;
  final double serviceFee;
  final double partsTotal;
  final double downPayment;
  final double paidAmount;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? completedAt;
  final DateTime? pickedUpAt;
  final int warrantyDays;
  final String notes;
  final List<ServicePartModel> parts;

  ServiceOrderModel({
    this.id,
    required this.ticketNumber,
    this.customerId,
    required this.customerName,
    this.customerPhone = '',
    required this.deviceType,
    this.brand = '',
    this.model = '',
    this.imeiSn = '',
    this.accessories = '',
    required this.complaint,
    this.physicalCondition = '',
    List<String>? photoPaths,
    this.technicianId,
    this.technicianName = 'Belum Ditentukan',
    this.estimatedCost = 0.0,
    this.serviceFee = 0.0,
    this.partsTotal = 0.0,
    this.downPayment = 0.0,
    this.paidAmount = 0.0,
    this.status = ServiceStatus.diterima,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.completedAt,
    this.pickedUpAt,
    this.warrantyDays = 7,
    this.notes = '',
    List<ServicePartModel>? parts,
  })  : photoPaths = photoPaths ?? [],
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now(),
        parts = parts ?? [];

  double get computedPartsTotal => parts.fold(0.0, (sum, p) => sum + p.subtotal);
  double get totalCost => serviceFee + (parts.isNotEmpty ? computedPartsTotal : partsTotal);
  double get remainingPayment {
    final rem = totalCost - paidAmount;
    return rem > 0 ? rem : 0.0;
  }

  bool get isPaidOff => totalCost > 0 ? paidAmount >= totalCost : paidAmount >= estimatedCost && estimatedCost == 0;

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'ticket_number': ticketNumber,
        'customer_id': customerId,
        'customer_name': customerName,
        'customer_phone': customerPhone,
        'device_type': deviceType,
        'brand': brand,
        'model': model,
        'imei_sn': imeiSn,
        'accessories': accessories,
        'complaint': complaint,
        'physical_condition': physicalCondition,
        'photo_paths_json': jsonEncode(photoPaths),
        'technician_id': technicianId,
        'technician_name': technicianName,
        'estimated_cost': estimatedCost,
        'service_fee': serviceFee,
        'parts_total': parts.isNotEmpty ? computedPartsTotal : partsTotal,
        'down_payment': downPayment,
        'paid_amount': paidAmount,
        'status': status,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        'completed_at': completedAt?.toIso8601String(),
        'picked_up_at': pickedUpAt?.toIso8601String(),
        'warranty_days': warrantyDays,
        'notes': notes,
      };

  factory ServiceOrderModel.fromMap(Map<String, dynamic> map) {
    List<String> photos = [];
    final rawPhotos = map['photo_paths_json'] as String?;
    if (rawPhotos != null && rawPhotos.isNotEmpty) {
      try {
        photos = (jsonDecode(rawPhotos) as List<dynamic>).map((e) => e.toString()).toList();
      } catch (_) {}
    }

    return ServiceOrderModel(
      id: map['id'] as int?,
      ticketNumber: (map['ticket_number'] ?? '').toString(),
      customerId: map['customer_id'] as int?,
      customerName: (map['customer_name'] ?? '').toString(),
      customerPhone: (map['customer_phone'] ?? '').toString(),
      deviceType: (map['device_type'] ?? 'HP').toString(),
      brand: (map['brand'] ?? '').toString(),
      model: (map['model'] ?? '').toString(),
      imeiSn: (map['imei_sn'] ?? '').toString(),
      accessories: (map['accessories'] ?? '').toString(),
      complaint: (map['complaint'] ?? '').toString(),
      physicalCondition: (map['physical_condition'] ?? '').toString(),
      photoPaths: photos,
      technicianId: map['technician_id'] as int?,
      technicianName: (map['technician_name'] ?? 'Belum Ditentukan').toString(),
      estimatedCost: (map['estimated_cost'] as num?)?.toDouble() ?? 0.0,
      serviceFee: (map['service_fee'] as num?)?.toDouble() ?? 0.0,
      partsTotal: (map['parts_total'] as num?)?.toDouble() ?? 0.0,
      downPayment: (map['down_payment'] as num?)?.toDouble() ?? 0.0,
      paidAmount: (map['paid_amount'] as num?)?.toDouble() ?? 0.0,
      status: (map['status'] ?? ServiceStatus.diterima).toString(),
      createdAt: DateTime.parse(map['created_at']),
      updatedAt: DateTime.parse(map['updated_at']),
      completedAt: map['completed_at'] != null ? DateTime.tryParse(map['completed_at'].toString()) : null,
      pickedUpAt: map['picked_up_at'] != null ? DateTime.tryParse(map['picked_up_at'].toString()) : null,
      warrantyDays: (map['warranty_days'] as num?)?.toInt() ?? 7,
      notes: (map['notes'] ?? '').toString(),
    );
  }
}
