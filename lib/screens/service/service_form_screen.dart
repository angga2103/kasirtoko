import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/customer.dart';
import '../../models/service_order.dart';
import '../../models/user.dart';
import '../../providers/auth_provider.dart';
import '../../providers/cash_flow_provider.dart';
import '../../providers/customer_provider.dart';
import '../../providers/service_order_provider.dart';
import '../../providers/settings_provider.dart';
import '../../utils/app_theme.dart';
import '../../widgets/image_picker_cropper.dart';
import '../scanner/barcode_scanner_screen.dart';

class ServiceFormScreen extends StatefulWidget {
  final ServiceOrderModel? existingOrder;

  const ServiceFormScreen({super.key, this.existingOrder});

  @override
  State<ServiceFormScreen> createState() => _ServiceFormScreenState();
}

class _ServiceFormScreenState extends State<ServiceFormScreen> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _ticketCtrl;
  late TextEditingController _customerNameCtrl;
  late TextEditingController _customerPhoneCtrl;
  late TextEditingController _deviceTypeCtrl;
  late TextEditingController _brandCtrl;
  late TextEditingController _modelCtrl;
  late TextEditingController _imeiCtrl;
  late TextEditingController _accessoriesCtrl;
  late TextEditingController _complaintCtrl;
  late TextEditingController _physicalCtrl;
  late TextEditingController _estimatedCtrl;
  late TextEditingController _serviceFeeCtrl;
  late TextEditingController _dpCtrl;
  late TextEditingController _warrantyCtrl;
  late TextEditingController _notesCtrl;

  int? _customerId;
  int? _technicianId;
  String _technicianName = 'Belum Ditentukan';
  List<String> _photoPaths = [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final o = widget.existingOrder;
    final srvProv = Provider.of<ServiceOrderProvider>(context, listen: false);

    _ticketCtrl = TextEditingController(text: o?.ticketNumber ?? srvProv.generateTicketNumber());
    _customerNameCtrl = TextEditingController(text: o?.customerName ?? '');
    _customerPhoneCtrl = TextEditingController(text: o?.customerPhone ?? '');
    _deviceTypeCtrl = TextEditingController(text: o?.deviceType ?? 'HP / Smartphone');
    _brandCtrl = TextEditingController(text: o?.brand ?? '');
    _modelCtrl = TextEditingController(text: o?.model ?? '');
    _imeiCtrl = TextEditingController(text: o?.imeiSn ?? '');
    _accessoriesCtrl = TextEditingController(text: o?.accessories ?? '');
    _complaintCtrl = TextEditingController(text: o?.complaint ?? '');
    _physicalCtrl = TextEditingController(text: o?.physicalCondition ?? '');
    _estimatedCtrl = TextEditingController(text: o != null ? o.estimatedCost.toInt().toString() : '0');
    _serviceFeeCtrl = TextEditingController(text: o != null ? o.serviceFee.toInt().toString() : '0');
    _dpCtrl = TextEditingController(text: o != null ? o.downPayment.toInt().toString() : '0');
    _warrantyCtrl = TextEditingController(text: (o?.warrantyDays ?? 7).toString());
    _notesCtrl = TextEditingController(text: o?.notes ?? '');

    _customerId = o?.customerId;
    _technicianId = o?.technicianId;
    _technicianName = o?.technicianName ?? 'Belum Ditentukan';
    _photoPaths = o != null ? List.from(o.photoPaths) : [];
  }

  @override
  void dispose() {
    _ticketCtrl.dispose();
    _customerNameCtrl.dispose();
    _customerPhoneCtrl.dispose();
    _deviceTypeCtrl.dispose();
    _brandCtrl.dispose();
    _modelCtrl.dispose();
    _imeiCtrl.dispose();
    _accessoriesCtrl.dispose();
    _complaintCtrl.dispose();
    _physicalCtrl.dispose();
    _estimatedCtrl.dispose();
    _serviceFeeCtrl.dispose();
    _dpCtrl.dispose();
    _warrantyCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  void _pickCustomer() {
    final customers = Provider.of<CustomerProvider>(context, listen: false).customers;
    if (customers.isEmpty) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pilih Pelanggan'),
        content: SizedBox(
          width: 360,
          height: 300,
          child: ListView.builder(
            itemCount: customers.length,
            itemBuilder: (_, i) {
              final CustomerModel c = customers[i];
              return ListTile(
                title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(c.phone),
                onTap: () {
                  setState(() {
                    _customerId = c.id;
                    _customerNameCtrl.text = c.name;
                    _customerPhoneCtrl.text = c.phone;
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

  Future<void> _scanImei() async {
    final code = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => const BarcodeScannerScreen(
          title: 'Scan Barcode IMEI / Serial Number',
          continuousMode: false,
        ),
      ),
    );
    if (code != null && code.isNotEmpty && mounted) {
      setState(() => _imeiCtrl.text = code);
    }
  }

  Future<void> _addDevicePhoto() async {
    final path = await ImagePickerHelper.pickAndCropImage(
      context,
      prefix: 'srv_dev',
      title: 'Foto Kondisi Perangkat Servis',
    );
    if (path != null && mounted) {
      setState(() => _photoPaths.add(path));
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final srvProv = Provider.of<ServiceOrderProvider>(context, listen: false);
    final cashFlow = Provider.of<CashFlowProvider>(context, listen: false);

    final est = double.tryParse(_estimatedCtrl.text) ?? 0.0;
    final fee = double.tryParse(_serviceFeeCtrl.text) ?? 0.0;
    final dp = double.tryParse(_dpCtrl.text) ?? 0.0;
    final warranty = int.tryParse(_warrantyCtrl.text) ?? 7;

    final existing = widget.existingOrder;
    final order = ServiceOrderModel(
      id: existing?.id,
      ticketNumber: _ticketCtrl.text.trim(),
      customerId: _customerId,
      customerName: _customerNameCtrl.text.trim(),
      customerPhone: _customerPhoneCtrl.text.trim(),
      deviceType: _deviceTypeCtrl.text.trim(),
      brand: _brandCtrl.text.trim(),
      model: _modelCtrl.text.trim(),
      imeiSn: _imeiCtrl.text.trim(),
      accessories: _accessoriesCtrl.text.trim(),
      complaint: _complaintCtrl.text.trim(),
      physicalCondition: _physicalCtrl.text.trim(),
      photoPaths: _photoPaths,
      technicianId: _technicianId,
      technicianName: _technicianName,
      estimatedCost: est,
      serviceFee: fee,
      partsTotal: existing?.partsTotal ?? 0.0,
      downPayment: existing != null ? existing.downPayment : dp,
      paidAmount: existing != null ? existing.paidAmount : dp,
      status: existing?.status ?? ServiceStatus.diterima,
      createdAt: existing?.createdAt,
      updatedAt: DateTime.now(),
      completedAt: existing?.completedAt,
      pickedUpAt: existing?.pickedUpAt,
      warrantyDays: warranty,
      notes: _notesCtrl.text.trim(),
      parts: existing?.parts,
    );

    if (existing == null) {
      await srvProv.createOrder(
        order,
        shiftId: cashFlow.currentShift?.id,
        cashierName: auth.currentUser?.name ?? 'Kasir',
      );
      await cashFlow.checkOpenShift();
      await auth.logAction('servis_baru', 'Pendaftaran servis #${order.ticketNumber} (${order.customerName})');
    } else {
      await srvProv.updateOrder(order);
      await auth.logAction('servis_ubah', 'Memperbarui tiket servis #${order.ticketNumber}');
    }

    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final settings = Provider.of<SettingsProvider>(context);
    final techs = auth.technicians;
    final isEdit = widget.existingOrder != null;

    return Scaffold(
      appBar: AppBar(title: Text(isEdit ? 'Edit Data Servis' : 'Pendaftaran Servis Baru')),
      body: Form(
        key: _formKey,
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
                        const Text('Tiket & Data Pelanggan', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _ticketCtrl,
                          readOnly: isEdit,
                          decoration: const InputDecoration(labelText: 'Nomor Tiket Otomatis'),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _customerNameCtrl,
                                decoration: const InputDecoration(labelText: 'Nama Pelanggan *'),
                                validator: (v) => v == null || v.trim().isEmpty ? 'Wajib diisi' : null,
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
                        TextFormField(
                          controller: _customerPhoneCtrl,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(labelText: 'Nomor Telepon / WhatsApp'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: AppTheme.cardDecoration(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Detail Perangkat & Keluhan', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _deviceTypeCtrl,
                                decoration: const InputDecoration(labelText: 'Jenis Perangkat (HP, Laptop, TV) *'),
                                validator: (v) => v == null || v.trim().isEmpty ? 'Wajib diisi' : null,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _brandCtrl,
                                decoration: const InputDecoration(labelText: 'Merek (Samsung, Oppo, Asus)'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _modelCtrl,
                                decoration: const InputDecoration(labelText: 'Tipe / Model'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _imeiCtrl,
                                      decoration: const InputDecoration(labelText: 'IMEI / Serial Number'),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.qr_code_scanner_rounded, color: AppTheme.primaryGreen),
                                    onPressed: _scanImei,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _accessoriesCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Kelengkapan (Charger, Dus, SIM Tray, Casing)',
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _physicalCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Kondisi Fisik Awal (Layar retak, lecet bezel, mati total)',
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: _complaintCtrl,
                          maxLines: 2,
                          decoration: const InputDecoration(labelText: 'Keluhan Kerusakan *'),
                          validator: (v) => v == null || v.trim().isEmpty ? 'Keluhan wajib diisi' : null,
                        ),
                        const SizedBox(height: 12),

                        // Photos
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Foto Kondisi Perangkat:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                            TextButton.icon(
                              onPressed: _addDevicePhoto,
                              icon: const Icon(Icons.add_a_photo_rounded, size: 18),
                              label: const Text('Tambah Foto'),
                            ),
                          ],
                        ),
                        if (_photoPaths.isNotEmpty)
                          SizedBox(
                            height: 88,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: _photoPaths.length,
                              separatorBuilder: (_, __) => const SizedBox(width: 8),
                              itemBuilder: (_, i) {
                                final f = File(_photoPaths[i]);
                                return Stack(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(10),
                                      child: SizedBox(
                                        width: 88,
                                        height: 88,
                                        child: f.existsSync()
                                            ? Image.file(f, fit: BoxFit.cover)
                                            : const Icon(Icons.broken_image),
                                      ),
                                    ),
                                    Positioned(
                                      right: 2,
                                      top: 2,
                                      child: InkWell(
                                        onTap: () => setState(() => _photoPaths.removeAt(i)),
                                        child: const CircleAvatar(
                                          radius: 11,
                                          backgroundColor: Colors.black87,
                                          child: Icon(Icons.close, size: 14, color: Colors.white),
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: AppTheme.cardDecoration(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Teknisi & Biaya', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        const SizedBox(height: 10),
                        DropdownButtonFormField<int?>(
                          value: techs.any((t) => t.id == _technicianId) ? _technicianId : null,
                          decoration: const InputDecoration(labelText: 'Tugaskan Teknisi'),
                          items: [
                            const DropdownMenuItem<int?>(value: null, child: Text('Belum Ditentukan')),
                            ...techs.map((UserModel t) => DropdownMenuItem<int?>(
                                  value: t.id,
                                  child: Text('${t.name} (${t.roleDisplay})'),
                                )),
                          ],
                          onChanged: (id) {
                            setState(() {
                              _technicianId = id;
                              _technicianName = id == null
                                  ? 'Belum Ditentukan'
                                  : techs.firstWhere((t) => t.id == id).name;
                            });
                          },
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _estimatedCtrl,
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(
                                  labelText: 'Estimasi Biaya',
                                  prefixText: settings.currencySymbol,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _serviceFeeCtrl,
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(
                                  labelText: 'Biaya Jasa Final',
                                  prefixText: settings.currencySymbol,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            if (!isEdit)
                              Expanded(
                                child: TextField(
                                  controller: _dpCtrl,
                                  keyboardType: TextInputType.number,
                                  decoration: InputDecoration(
                                    labelText: 'Uang Muka / DP (Tunai)',
                                    prefixText: settings.currencySymbol,
                                  ),
                                ),
                              ),
                            if (!isEdit) const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _warrantyCtrl,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(labelText: 'Garansi (Hari)'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _notesCtrl,
                          decoration: const InputDecoration(labelText: 'Catatan Teknisi / Lainnya'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: const Icon(Icons.save_rounded),
                      label: Text(_saving ? 'MENYIMPAN...' : (isEdit ? 'PERBARUI TIKET SERVIS' : 'SIMPAN TIKET SERVIS')),
                    ),
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
