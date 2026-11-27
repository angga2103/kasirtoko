import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../database/db_helper.dart';
import '../../models/customer.dart';
import '../../models/product.dart';
import '../../models/warehouse_doc.dart';
import '../../providers/auth_provider.dart';
import '../../providers/customer_provider.dart';
import '../../providers/printer_provider.dart';
import '../../providers/product_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/printer/printer_manager.dart';
import '../../utils/app_theme.dart';
import '../../utils/date_format.dart';
import '../../widgets/quantity_stepper.dart';

class WarehouseDocsScreen extends StatefulWidget {
  const WarehouseDocsScreen({super.key});

  @override
  State<WarehouseDocsScreen> createState() => _WarehouseDocsScreenState();
}

class _WarehouseDocsScreenState extends State<WarehouseDocsScreen> {
  List<WarehouseDocModel> _docs = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDocs();
  }

  Future<void> _loadDocs() async {
    final list = await DatabaseHelper.instance.getWarehouseDocs();
    if (!mounted) return;
    setState(() {
      _docs = list;
      _isLoading = false;
    });
  }

  void _openDocForm({WarehouseDocModel? docToEdit}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WarehouseDocFormScreen(
          docToEdit: docToEdit,
          onSaved: _loadDocs,
        ),
      ),
    );
  }

  Future<void> _printDoc(WarehouseDocModel d) async {
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final printerProv = Provider.of<PrinterProvider>(context, listen: false);
    final res = await PrinterManager.printWarehouseDoc(
      printer: printerProv.defaultPrinter,
      doc: d,
      storeName: settings.storeName,
      storeAddress: settings.storeAddress,
      storePhone: settings.storePhone,
      logoPath: settings.logoPath,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res.message)));
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'draft':
        return Colors.grey.shade700;
      case 'dikirim':
        return AppTheme.accentOrange;
      case 'selesai':
        return AppTheme.success;
      default:
        return AppTheme.textMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Surat Jalan & Pengambilan Gudang')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _docs.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.local_shipping_outlined, size: 54, color: AppTheme.textMuted),
                      const SizedBox(height: 12),
                      const Text('Belum ada dokumen surat jalan / ambil gudang.'),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.add),
                        label: const Text('Buat Surat Baru'),
                        onPressed: () => _openDocForm(),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(14),
                  itemCount: _docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final d = _docs[index];
                    final isSuratJalan = d.docType == 'surat_jalan';
                    final parsedItems = d.parsedItems;

                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  backgroundColor: isSuratJalan ? Colors.deepPurple.shade50 : Colors.teal.shade50,
                                  child: Icon(
                                    isSuratJalan ? Icons.local_shipping_rounded : Icons.warehouse_rounded,
                                    color: isSuratJalan ? Colors.deepPurple : Colors.teal,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        d.docNumber,
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                      ),
                                      Text(
                                        '${isSuratJalan ? "Surat Jalan" : "Surat Ambil Gudang"} • ${DateHelper.formatShort(d.date)}',
                                        style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: _statusColor(d.status).withValues(alpha: 0.14),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    d.status.toUpperCase(),
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: _statusColor(d.status),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const Divider(height: 16),
                            Text('Penerima: ${d.recipientName}',
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                            if (d.recipientAddress.isNotEmpty)
                              Text('Alamat: ${d.recipientAddress}', style: const TextStyle(fontSize: 11.5, color: AppTheme.textMuted)),
                            Text(
                              'Sopir/Petugas: ${d.driverOrPickerName.isEmpty ? "-" : d.driverOrPickerName} (${d.vehicleNumber.isEmpty ? "-" : d.vehicleNumber}) • ${parsedItems.length} Baris Produk',
                              style: const TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              children: [
                                OutlinedButton.icon(
                                  icon: const Icon(Icons.edit_outlined, size: 16),
                                  label: const Text('Edit / Ubah Qty', style: TextStyle(fontSize: 12)),
                                  onPressed: () => _openDocForm(docToEdit: d),
                                ),
                                ElevatedButton.icon(
                                  icon: const Icon(Icons.print_rounded, size: 16),
                                  label: const Text('Cetak Dokumen', style: TextStyle(fontSize: 12)),
                                  onPressed: () => _printDoc(d),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppTheme.primaryGreen,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Buat Dokumen'),
        onPressed: () => _openDocForm(),
      ),
    );
  }
}

class WarehouseDocFormScreen extends StatefulWidget {
  final WarehouseDocModel? docToEdit;
  final VoidCallback onSaved;

  const WarehouseDocFormScreen({
    super.key,
    this.docToEdit,
    required this.onSaved,
  });

  @override
  State<WarehouseDocFormScreen> createState() => _WarehouseDocFormScreenState();
}

class _WarehouseDocFormScreenState extends State<WarehouseDocFormScreen> {
  late String _docType;
  late String _status;
  late DateTime _deliveryDate;
  late TextEditingController _noCtrl;
  late TextEditingController _recipientCtrl;
  late TextEditingController _addressCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _driverCtrl;
  late TextEditingController _vehicleCtrl;
  late TextEditingController _noteCtrl;

  List<WarehouseDocItem> _items = [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final d = widget.docToEdit;
    _docType = d?.docType ?? 'surat_jalan';
    _status = d?.status ?? 'draft';
    _deliveryDate = d?.deliveryDate ?? DateTime.now();

    _noCtrl = TextEditingController(
      text: d?.docNumber ?? _genDocNo(_docType),
    );
    _recipientCtrl = TextEditingController(text: d?.recipientName ?? '');
    _addressCtrl = TextEditingController(text: d?.recipientAddress ?? '');
    _phoneCtrl = TextEditingController(text: d?.recipientPhone ?? '');
    _driverCtrl = TextEditingController(text: d?.driverOrPickerName ?? '');
    _vehicleCtrl = TextEditingController(text: d?.vehicleNumber ?? '');
    _noteCtrl = TextEditingController(text: d?.note ?? '');

    if (d != null && d.parsedItems.isNotEmpty) {
      _items = d.parsedItems;
    } else {
      _items = [WarehouseDocItem(name: '', qty: 1, unit: 'Pcs', note: '')];
    }
  }

  String _genDocNo(String type) {
    final prefix = type == 'surat_jalan' ? 'SJ' : 'SAB';
    final now = DateTime.now();
    return '$prefix-${now.year}${now.month.toString().padLeft(2, '0')}-${Random().nextInt(9000) + 1000}';
  }

  @override
  void dispose() {
    _noCtrl.dispose();
    _recipientCtrl.dispose();
    _addressCtrl.dispose();
    _phoneCtrl.dispose();
    _driverCtrl.dispose();
    _vehicleCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  void _pickCustomer() {
    final customers = Provider.of<CustomerProvider>(context, listen: false).customers;
    if (customers.isEmpty) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        title: const Text('Pilih Pelanggan'),
        content: SizedBox(
          width: AppBreakpoints.boundedDialogWidth(ctx, maxWidth: 400),
          height: (MediaQuery.sizeOf(ctx).height * 0.5).clamp(160.0, 300.0),
          child: ListView.builder(
            itemCount: customers.length,
            itemBuilder: (_, i) {
              final CustomerModel c = customers[i];
              return ListTile(
                title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('${c.phone} • ${c.address}'),
                onTap: () {
                  setState(() {
                    _recipientCtrl.text = c.name;
                    _phoneCtrl.text = c.phone;
                    _addressCtrl.text = c.address;
                  });
                  Navigator.pop(ctx);
                },
              );
            },
          ),
        ),
      ),
    );
  }

  void _pickProductForRow(int index) {
    final products = Provider.of<ProductProvider>(context, listen: false).allProducts;
    if (products.isEmpty) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        title: const Text('Pilih Produk dari Katalog'),
        content: SizedBox(
          width: AppBreakpoints.boundedDialogWidth(ctx, maxWidth: 420),
          height: (MediaQuery.sizeOf(ctx).height * 0.55).clamp(180.0, 360.0),
          child: ListView.builder(
            itemCount: products.length,
            itemBuilder: (_, i) {
              final ProductModel p = products[i];
              return ListTile(
                title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                subtitle: Text('${p.code} • Stok: ${p.stock.toInt()} ${p.baseUnit}'),
                onTap: () {
                  setState(() {
                    _items[index].productId = p.id;
                    _items[index].name = p.name;
                    _items[index].unit = p.baseUnit;
                  });
                  Navigator.pop(ctx);
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _save({required bool printAfter}) async {
    if (_recipientCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nama penerima / tujuan wajib diisi.')),
      );
      return;
    }

    final validItems = _items.where((i) => i.name.trim().isNotEmpty).toList();
    if (validItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tambahkan minimal 1 barang dengan nama yang terisi.')),
      );
      return;
    }

    setState(() => _saving = true);

    final doc = WarehouseDocModel(
      id: widget.docToEdit?.id,
      docNumber: _noCtrl.text.trim(),
      docType: _docType,
      date: widget.docToEdit?.date ?? DateTime.now(),
      deliveryDate: _deliveryDate,
      recipientName: _recipientCtrl.text.trim(),
      recipientAddress: _addressCtrl.text.trim(),
      recipientPhone: _phoneCtrl.text.trim(),
      driverOrPickerName: _driverCtrl.text.trim(),
      vehicleNumber: _vehicleCtrl.text.trim(),
      note: _noteCtrl.text.trim(),
      status: _status,
      itemsJson: jsonEncode(validItems.map((e) => e.toMap()).toList()),
    );

    if (widget.docToEdit == null) {
      await DatabaseHelper.instance.insertWarehouseDoc(doc);
    } else {
      await DatabaseHelper.instance.updateWarehouseDoc(doc);
    }

    if (mounted) {
      await Provider.of<AuthProvider>(context, listen: false).logAction(
        'surat_jalan',
        '${widget.docToEdit == null ? "Buat" : "Edit"} ${doc.docTitle} #${doc.docNumber} (${doc.status})',
      );
    }

    widget.onSaved();

    if (printAfter && mounted) {
      final settings = Provider.of<SettingsProvider>(context, listen: false);
      final printerProv = Provider.of<PrinterProvider>(context, listen: false);
      await PrinterManager.printWarehouseDoc(
        printer: printerProv.defaultPrinter,
        doc: doc,
        storeName: settings.storeName,
        storeAddress: settings.storeAddress,
        storePhone: settings.storePhone,
        logoPath: settings.logoPath,
      );
    }

    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.docToEdit != null;

    return Scaffold(
      appBar: AppBar(title: Text(isEdit ? 'Edit Dokumen Surat Jalan' : 'Buat Surat Jalan / Ambil Gudang')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 740),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: AppTheme.cardDecoration(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: ChoiceChip(
                                label: const Center(child: Text('Surat Jalan (Kirim)')),
                                selected: _docType == 'surat_jalan',
                                selectedColor: AppTheme.primaryGreenSoft,
                                onSelected: (val) {
                                  if (val && !isEdit) {
                                    setState(() {
                                      _docType = 'surat_jalan';
                                      _noCtrl.text = _genDocNo('surat_jalan');
                                    });
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ChoiceChip(
                                label: const Center(child: Text('Surat Ambil Gudang')),
                                selected: _docType == 'surat_ambil_barang',
                                selectedColor: AppTheme.primaryGreenSoft,
                                onSelected: (val) {
                                  if (val && !isEdit) {
                                    setState(() {
                                      _docType = 'surat_ambil_barang';
                                      _noCtrl.text = _genDocNo('surat_ambil_barang');
                                    });
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _noCtrl,
                                decoration: const InputDecoration(labelText: 'Nomor Dokumen'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                value: _status,
                                isExpanded: true,
                                decoration: const InputDecoration(labelText: 'Status'),
                                items: const [
                                  DropdownMenuItem(value: 'draft', child: Text('Draft', overflow: TextOverflow.ellipsis)),
                                  DropdownMenuItem(value: 'dikirim', child: Text('Dikirim', overflow: TextOverflow.ellipsis)),
                                  DropdownMenuItem(value: 'selesai', child: Text('Selesai', overflow: TextOverflow.ellipsis)),
                                ],
                                onChanged: (v) => setState(() => _status = v ?? 'draft'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _recipientCtrl,
                                decoration: InputDecoration(
                                  labelText: _docType == 'surat_jalan' ? 'Pelanggan / Tujuan *' : 'Nama Pengambil *',
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton.filledTonal(
                              icon: const Icon(Icons.contacts_rounded, color: AppTheme.primaryGreen),
                              tooltip: 'Pilih Pelanggan',
                              onPressed: _pickCustomer,
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _phoneCtrl,
                                keyboardType: TextInputType.phone,
                                decoration: const InputDecoration(labelText: 'No. HP Penerima'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: InkWell(
                                onTap: () async {
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: _deliveryDate,
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime(2035),
                                  );
                                  if (picked != null) setState(() => _deliveryDate = picked);
                                },
                                child: InputDecorator(
                                  decoration: const InputDecoration(
                                    labelText: 'Tanggal Kirim',
                                    suffixIcon: Icon(Icons.calendar_today_rounded, size: 18),
                                  ),
                                  child: Text(DateHelper.formatShort(_deliveryDate)),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _addressCtrl,
                          maxLines: 2,
                          decoration: const InputDecoration(labelText: 'Alamat Tujuan Pengiriman'),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _driverCtrl,
                                decoration: const InputDecoration(labelText: 'Nama Sopir / Pengambil'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextField(
                                controller: _vehicleCtrl,
                                decoration: const InputDecoration(labelText: 'No. Kendaraan (Plat)'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Items Card List (FIX: Spacious full-width cards with clear visible [-] qty [+]!)
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Daftar Barang Dikirim / Diambil:',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: () {
                          setState(() {
                            _items.add(WarehouseDocItem(name: '', qty: 1, unit: 'Pcs', note: ''));
                          });
                        },
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Tambah Baris'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  ..._items.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final item = entry.value;

                    return Container(
                      key: ObjectKey(item),
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: AppTheme.cardDecoration(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 13,
                                backgroundColor: AppTheme.primaryGreenSoft,
                                child: Text('${idx + 1}',
                                    style: const TextStyle(
                                        fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.primaryGreen)),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextFormField(
                                  key: ValueKey('name_${idx}_${item.name}'),
                                  initialValue: item.name,
                                  decoration: AppTheme.denseInputDecoration(
                                    labelText: 'Nama Barang *',
                                    hintText: 'Ketik atau pilih produk...',
                                  ),
                                  onChanged: (v) => item.name = v,
                                ),
                              ),
                              const SizedBox(width: 6),
                              IconButton.filledTonal(
                                icon: const Icon(Icons.inventory_2_outlined, size: 18),
                                tooltip: 'Pilih dari Produk',
                                onPressed: () => _pickProductForRow(idx),
                              ),
                              if (_items.length > 1)
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, color: AppTheme.accentRed),
                                  onPressed: () => setState(() => _items.removeAt(idx)),
                                ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 12,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text('Qty: ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                  QuantityStepper(
                                    value: item.qty,
                                    minValue: 1,
                                    allowDecimal: true,
                                    onChanged: (newQty) {
                                      setState(() => item.qty = newQty);
                                    },
                                  ),
                                ],
                              ),
                              SizedBox(
                                width: 110,
                                child: TextFormField(
                                  key: ValueKey('unit_${idx}_${item.unit}'),
                                  initialValue: item.unit,
                                  decoration: AppTheme.denseInputDecoration(labelText: 'Satuan'),
                                  onChanged: (v) => item.unit = v,
                                ),
                              ),
                              SizedBox(
                                width: 180,
                                child: TextFormField(
                                  initialValue: item.note,
                                  decoration: AppTheme.denseInputDecoration(labelText: 'Keterangan'),
                                  onChanged: (v) => item.note = v,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  }),

                  const SizedBox(height: 8),
                  TextField(
                    controller: _noteCtrl,
                    decoration: const InputDecoration(labelText: 'Catatan Tambahan Dokumen (Opsional)'),
                  ),
                  const SizedBox(height: 20),

                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _saving ? null : () => _save(printAfter: false),
                          icon: const Icon(Icons.save_rounded),
                          label: const Text('Simpan Saja'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _saving ? null : () => _save(printAfter: true),
                          icon: const Icon(Icons.print_rounded),
                          label: const Text('Simpan & Cetak'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
