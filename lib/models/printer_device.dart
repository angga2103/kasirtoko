class PrinterCategory {
  static const String thermal = 'thermal';
  static const String laser = 'laser';
  static const String dotMatrix = 'dot_matrix';

  static String label(String cat) {
    switch (cat) {
      case thermal:
        return 'Thermal';
      case laser:
        return 'Laser / Inkjet (A4)';
      case dotMatrix:
        return 'Dot Matrix (Continuous)';
      default:
        return cat;
    }
  }
}

class PrinterConnectionType {
  static const String bluetooth = 'bluetooth';
  static const String usb = 'usb';
  static const String lan = 'lan';
  static const String system = 'system';

  static String label(String type) {
    switch (type) {
      case bluetooth:
        return 'Bluetooth';
      case usb:
        return 'USB OTG';
      case lan:
        return 'LAN / Wi-Fi (TCP)';
      case system:
        return 'Android Print Service';
      default:
        return type;
    }
  }
}

class PrinterProtocol {
  static const String escPos = 'esc_pos';
  static const String escP = 'esc_p';
  static const String pdf = 'pdf';

  static String label(String proto) {
    switch (proto) {
      case escPos:
        return 'ESC/POS (Thermal)';
      case escP:
        return 'ESC/P (Dot Matrix)';
      case pdf:
        return 'PDF / Android Print Framework';
      default:
        return proto;
    }
  }
}

class PrinterDeviceModel {
  final int? id;
  final String name;
  final String category; // thermal | laser | dot_matrix
  final String connectionType; // bluetooth | usb | lan | system
  final String address; // BT MAC, USB device name, or IP address
  final int port; // Default 9100 for LAN
  final String paperSize; // '58mm' | '80mm' | 'a4' | 'continuous'
  final String protocol; // 'esc_pos' | 'esc_p' | 'pdf'
  final bool isDefault;
  final bool autoCut;
  final bool openDrawer;

  PrinterDeviceModel({
    this.id,
    required this.name,
    required this.category,
    required this.connectionType,
    this.address = '',
    this.port = 9100,
    this.paperSize = '58mm',
    this.protocol = 'esc_pos',
    this.isDefault = false,
    this.autoCut = true,
    this.openDrawer = true,
  });

  int get escCharWidth => paperSize == '80mm' ? 48 : (paperSize == 'continuous' ? 80 : 32);

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'category': category,
        'connection_type': connectionType,
        'address': address,
        'port': port,
        'paper_size': paperSize,
        'protocol': protocol,
        'is_default': isDefault ? 1 : 0,
        'auto_cut': autoCut ? 1 : 0,
        'open_drawer': openDrawer ? 1 : 0,
      };

  factory PrinterDeviceModel.fromMap(Map<String, dynamic> map) {
    return PrinterDeviceModel(
      id: map['id'] as int?,
      name: (map['name'] ?? '').toString(),
      category: (map['category'] ?? PrinterCategory.thermal).toString(),
      connectionType: (map['connection_type'] ?? PrinterConnectionType.system).toString(),
      address: (map['address'] ?? '').toString(),
      port: (map['port'] as num?)?.toInt() ?? 9100,
      paperSize: (map['paper_size'] ?? '58mm').toString(),
      protocol: (map['protocol'] ?? PrinterProtocol.pdf).toString(),
      isDefault: (map['is_default'] ?? 0) == 1,
      autoCut: (map['auto_cut'] ?? 1) == 1,
      openDrawer: (map['open_drawer'] ?? 1) == 1,
    );
  }

  PrinterDeviceModel copyWith({
    int? id,
    String? name,
    String? category,
    String? connectionType,
    String? address,
    int? port,
    String? paperSize,
    String? protocol,
    bool? isDefault,
    bool? autoCut,
    bool? openDrawer,
  }) {
    return PrinterDeviceModel(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      connectionType: connectionType ?? this.connectionType,
      address: address ?? this.address,
      port: port ?? this.port,
      paperSize: paperSize ?? this.paperSize,
      protocol: protocol ?? this.protocol,
      isDefault: isDefault ?? this.isDefault,
      autoCut: autoCut ?? this.autoCut,
      openDrawer: openDrawer ?? this.openDrawer,
    );
  }
}
