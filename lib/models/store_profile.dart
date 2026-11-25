enum BusinessType {
  retail('retail', 'Toko Retail & Minimarket', 'Toko kelontong, minimarket, & ritel harian'),
  wholesale('wholesale', 'Toko Grosir & Agen', 'Penjualan bertingkat, multi-satuan, & surat jalan'),
  phoneCounter('phone_counter', 'Konter HP & Aksesoris', 'HP baru/bekas, IMEI/SN, aksesoris, & pulsa/servis'),
  electronics('electronics', 'Toko Elektronik', 'Elektronik rumah tangga, SN, garansi, & pengiriman'),
  serviceCenter('service_center', 'Jasa Servis HP & Elektronik', 'Fokus penerimaan servis, teknisi, & sparepart'),
  general('general', 'Usaha Perdagangan Umum', 'Semua fitur POS, gudang, kasbon, & servis aktif');

  final String code;
  final String label;
  final String description;

  const BusinessType(this.code, this.label, this.description);

  static BusinessType fromCode(String code) {
    return BusinessType.values.firstWhere(
      (e) => e.code == code,
      orElse: () => BusinessType.general,
    );
  }

  bool get prioritizeService =>
      this == phoneCounter || this == electronics || this == serviceCenter || this == general;

  bool get showImeiDeviceFields =>
      this == phoneCounter || this == electronics || this == serviceCenter || this == general;

  bool get prioritizeExpiry =>
      this == retail || this == wholesale || this == general;

  bool get prioritizeDeliveryDocs =>
      this == wholesale || this == electronics || this == general;

  List<String> get defaultCategories {
    switch (this) {
      case BusinessType.phoneCounter:
        return ['Semua', 'HP Baru', 'HP Bekas', 'Aksesoris', 'Sparepart', 'Jasa Servis', 'Umum'];
      case BusinessType.electronics:
        return ['Semua', 'Elektronik', 'Audio/TV', 'Aksesoris', 'Sparepart', 'Jasa', 'Umum'];
      case BusinessType.serviceCenter:
        return ['Semua', 'Sparepart HP', 'Sparepart Elektronik', 'Jasa Servis', 'Aksesoris', 'Umum'];
      case BusinessType.wholesale:
        return ['Semua', 'Sembako', 'Makanan', 'Minuman', 'Kebutuhan Rumah', 'Karton/Dus', 'Umum'];
      case BusinessType.retail:
        return ['Semua', 'Sembako', 'Makanan', 'Minuman', 'Kebutuhan Rumah', 'Rokok', 'Umum'];
      case BusinessType.general:
        return ['Semua', 'Sembako', 'Makanan', 'Minuman', 'Elektronik', 'Aksesoris', 'Jasa', 'Umum'];
    }
  }
}
