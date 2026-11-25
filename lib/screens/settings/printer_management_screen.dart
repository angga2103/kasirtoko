import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/printer_device.dart';
import '../../models/user.dart';
import '../../providers/auth_provider.dart';
import '../../providers/printer_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/hardware_bridge.dart';
import '../../utils/app_theme.dart';

class PrinterManagementScreen extends StatefulWidget {
  const PrinterManagementScreen({super.key});

  @override
  State<PrinterManagementScreen> createState() => _PrinterManagementScreenState();
}

class _PrinterManagementScreenState extends State<PrinterManagementScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<PrinterProvider>(context, listen: false).loadPrinters();
    });
  }

  void _openPrinterForm({PrinterDeviceModel? printer}) {
    showDialog(
      context: context,
      builder: (_) => _PrinterFormDialog(printer: printer),
    );
  }

  Future<void> _runTest(PrinterDeviceModel p, {required bool sendPage}) async {
    final prov = Provider.of<PrinterProvider>(context, listen: false);
    final settings = Provider.of<SettingsProvider>(context, listen: false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Menguji koneksi ke ${p.name}...'), duration: const Duration(seconds: 2)),
    );

    final res = await prov.testPrinter(p, storeName: settings.storeName, sendTestPage: sendPage);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(res.message),
        backgroundColor: res.success ? AppTheme.success : AppTheme.accentRed,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    if (!auth.hasPermission(AppPermissions.managePrinters)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Manajemen Printer')),
        body: const Center(child: Text('Anda tidak memiliki izin mengelola printer.')),
      );
    }

    final prov = Provider.of<PrinterProvider>(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Manajemen Printer (Thermal / Laser / Dot Matrix)')),
      body: prov.isLoading
          ? const Center(child: CircularProgressIndicator())
          : prov.printers.isEmpty
              ? const Center(child: Text('Belum ada printer terdaftar.'))
              : ListView.separated(
                  padding: const EdgeInsets.all(14),
                  itemCount: prov.printers.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final p = prov.printers[index];
                    final liveStatus = prov.getLiveStatus(p.id);
                    final statusMsg = prov.getLastMessage(p.id);

                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: p.isDefault ? AppTheme.primaryGreenSoft : Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    p.category == PrinterCategory.thermal
                                        ? Icons.receipt_long_rounded
                                        : (p.category == PrinterCategory.dotMatrix
                                            ? Icons.view_headline_rounded
                                            : Icons.print_rounded),
                                    color: p.isDefault ? AppTheme.primaryGreen : AppTheme.textMuted,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              p.name,
                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                            ),
                                          ),
                                          if (p.isDefault)
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: AppTheme.primaryGreen,
                                                borderRadius: BorderRadius.circular(10),
                                              ),
                                              child: const Text(
                                                'PRINTER UTAMA',
                                                style: TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.bold),
                                              ),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${PrinterCategory.label(p.category)} • ${PrinterConnectionType.label(p.connectionType)} • ${p.paperSize.toUpperCase()}',
                                        style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                                      ),
                                      if (p.address.isNotEmpty && p.address != 'system_pdf')
                                        Text(
                                          'Alamat: ${p.address}${p.connectionType == PrinterConnectionType.lan ? ":${p.port}" : ""}',
                                          style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            if (statusMsg != null) ...[
                              const SizedBox(height: 8),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: liveStatus == true ? Colors.green.shade50 : Colors.red.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  'Status Terakhir: $statusMsg',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: liveStatus == true ? Colors.green.shade800 : Colors.red.shade800,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                            const Divider(height: 18),
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: [
                                OutlinedButton.icon(
                                  icon: const Icon(Icons.wifi_tethering_rounded, size: 16),
                                  label: const Text('Cek Koneksi', style: TextStyle(fontSize: 12)),
                                  onPressed: () => _runTest(p, sendPage: false),
                                ),
                                OutlinedButton.icon(
                                  icon: const Icon(Icons.print_outlined, size: 16),
                                  label: const Text('Test Print', style: TextStyle(fontSize: 12)),
                                  onPressed: () => _runTest(p, sendPage: true),
                                ),
                                if (!p.isDefault)
                                  TextButton.icon(
                                    icon: const Icon(Icons.star_outline_rounded, size: 16),
                                    label: const Text('Jadikan Utama', style: TextStyle(fontSize: 12)),
                                    onPressed: () => prov.setDefaultPrinter(p.id!),
                                  ),
                                TextButton.icon(
                                  icon: const Icon(Icons.edit_outlined, size: 16),
                                  label: const Text('Edit', style: TextStyle(fontSize: 12)),
                                  onPressed: () => _openPrinterForm(printer: p),
                                ),
                                if (prov.printers.length > 1)
                                  TextButton.icon(
                                    icon: const Icon(Icons.delete_outline, size: 16, color: AppTheme.accentRed),
                                    label: const Text('Hapus', style: TextStyle(fontSize: 12, color: AppTheme.accentRed)),
                                    onPressed: () => prov.deletePrinter(p.id!),
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
        onPressed: () => _openPrinterForm(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Tambah Printer'),
      ),
    );
  }
}

class _PrinterFormDialog extends StatefulWidget {
  final PrinterDeviceModel? printer;

  const _PrinterFormDialog({this.printer});

  @override
  State<_PrinterFormDialog> createState() => _PrinterFormDialogState();
}

class _PrinterFormDialogState extends State<_PrinterFormDialog> {
  late TextEditingController _nameCtrl;
  late TextEditingController _addressCtrl;
  late TextEditingController _portCtrl;
  late String _category;
  late String _connectionType;
  late String _paperSize;
  late String _protocol;
  bool _isDefault = false;
  bool _autoCut = true;
  bool _openDrawer = true;

  @override
  void initState() {
    super.initState();
    final p = widget.printer;
    _nameCtrl = TextEditingController(text: p?.name ?? '');
    _addressCtrl = TextEditingController(text: p?.address ?? '');
    _portCtrl = TextEditingController(text: (p?.port ?? 9100).toString());
    _category = p?.category ?? PrinterCategory.thermal;
    _connectionType = p?.connectionType ?? PrinterConnectionType.bluetooth;
    _paperSize = p?.paperSize ?? '58mm';
    _protocol = p?.protocol ?? PrinterProtocol.escPos;
    _isDefault = p?.isDefault ?? false;
    _autoCut = p?.autoCut ?? true;
    _openDrawer = p?.openDrawer ?? true;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _addressCtrl.dispose();
    _portCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickBluetoothDevice() async {
    try {
      final devices = await HardwareBridge.getPairedBluetoothDevices();
      if (!mounted) return;
      if (devices.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tidak ada perangkat Bluetooth ter-pair di Android Settings.')),
        );
        return;
      }
      final picked = await showDialog<PairedBluetoothDevice>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Pilih Printer Bluetooth Ter-pair'),
          content: SizedBox(
            width: 360,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: devices.length,
              itemBuilder: (_, i) => ListTile(
                leading: const Icon(Icons.bluetooth_rounded, color: AppTheme.accentBlue),
                title: Text(devices[i].name),
                subtitle: Text(devices[i].address),
                onTap: () => Navigator.pop(ctx, devices[i]),
              ),
            ),
          ),
        ),
      );
      if (picked != null && mounted) {
        setState(() {
          if (_nameCtrl.text.trim().isEmpty) _nameCtrl.text = picked.name;
          _addressCtrl.text = picked.address;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _pickUsbDevice() async {
    try {
      final devices = await HardwareBridge.getUsbDevices();
      if (!mounted) return;
      if (devices.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tidak ada perangkat USB OTG terdeteksi.')),
        );
        return;
      }
      final picked = await showDialog<ConnectedUsbDevice>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Pilih Printer USB OTG'),
          content: SizedBox(
            width: 360,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: devices.length,
              itemBuilder: (_, i) => ListTile(
                leading: const Icon(Icons.usb_rounded, color: AppTheme.primaryGreen),
                title: Text(devices[i].productName),
                subtitle: Text(devices[i].deviceName),
                onTap: () => Navigator.pop(ctx, devices[i]),
              ),
            ),
          ),
        ),
      );
      if (picked != null && mounted) {
        setState(() {
          if (_nameCtrl.text.trim().isEmpty) _nameCtrl.text = picked.productName;
          _addressCtrl.text = picked.deviceName;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.printer == null ? 'Tambah Printer Baru' : 'Edit Printer'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nama Printer *',
                  hintText: 'Contoh: Epson TM-T82 Kasir / LX-310 Gudang',
                ),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: _category,
                decoration: const InputDecoration(labelText: 'Kategori Printer'),
                items: const [
                  DropdownMenuItem(value: PrinterCategory.thermal, child: Text('Thermal (Struk / Label)')),
                  DropdownMenuItem(value: PrinterCategory.laser, child: Text('Laser / Inkjet (A4 PDF)')),
                  DropdownMenuItem(value: PrinterCategory.dotMatrix, child: Text('Dot Matrix (Continuous ESC/P)')),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setState(() {
                    _category = v;
                    if (v == PrinterCategory.thermal) {
                      _paperSize = '58mm';
                      _protocol = PrinterProtocol.escPos;
                      if (_connectionType == PrinterConnectionType.system) {
                        _connectionType = PrinterConnectionType.bluetooth;
                      }
                    } else if (v == PrinterCategory.laser) {
                      _paperSize = 'a4';
                      _protocol = PrinterProtocol.pdf;
                      _connectionType = PrinterConnectionType.system;
                    } else {
                      _paperSize = 'continuous';
                      _protocol = PrinterProtocol.escP;
                      _connectionType = PrinterConnectionType.usb;
                    }
                  });
                },
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _connectionType,
                      decoration: const InputDecoration(labelText: 'Koneksi'),
                      items: const [
                        DropdownMenuItem(value: PrinterConnectionType.bluetooth, child: Text('Bluetooth')),
                        DropdownMenuItem(value: PrinterConnectionType.usb, child: Text('USB OTG')),
                        DropdownMenuItem(value: PrinterConnectionType.lan, child: Text('LAN / Wi-Fi')),
                        DropdownMenuItem(value: PrinterConnectionType.system, child: Text('Android Print PDF')),
                      ],
                      onChanged: (v) => setState(() => _connectionType = v ?? _connectionType),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _paperSize,
                      decoration: const InputDecoration(labelText: 'Ukuran Kertas'),
                      items: const [
                        DropdownMenuItem(value: '58mm', child: Text('Thermal 58 mm')),
                        DropdownMenuItem(value: '80mm', child: Text('Thermal 80 mm')),
                        DropdownMenuItem(value: 'a4', child: Text('A4')),
                        DropdownMenuItem(value: 'continuous', child: Text('Continuous 80-col')),
                      ],
                      onChanged: (v) => setState(() => _paperSize = v ?? _paperSize),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (_connectionType != PrinterConnectionType.system) ...[
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _addressCtrl,
                        decoration: InputDecoration(
                          labelText: _connectionType == PrinterConnectionType.lan
                              ? 'IP Address Printer'
                              : (_connectionType == PrinterConnectionType.usb
                                  ? 'Nama Device USB'
                                  : 'Alamat MAC Bluetooth'),
                          hintText: _connectionType == PrinterConnectionType.lan ? '192.168.1.200' : '',
                        ),
                      ),
                    ),
                    if (_connectionType == PrinterConnectionType.bluetooth) ...[
                      const SizedBox(width: 8),
                      IconButton.filledTonal(
                        icon: const Icon(Icons.bluetooth_searching_rounded),
                        tooltip: 'Pilih Bluetooth',
                        onPressed: _pickBluetoothDevice,
                      ),
                    ] else if (_connectionType == PrinterConnectionType.usb) ...[
                      const SizedBox(width: 8),
                      IconButton.filledTonal(
                        icon: const Icon(Icons.usb_rounded),
                        tooltip: 'Scan USB OTG',
                        onPressed: _pickUsbDevice,
                      ),
                    ],
                  ],
                ),
                if (_connectionType == PrinterConnectionType.lan) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: _portCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Port TCP (Standar 9100)'),
                  ),
                ],
              ],
              const SizedBox(height: 8),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('Jadikan Printer Utama'),
                value: _isDefault,
                onChanged: (v) => setState(() => _isDefault = v),
              ),
              if (_category == PrinterCategory.thermal) ...[
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Auto-Cut Kertas Setelah Cetak'),
                  value: _autoCut,
                  onChanged: (v) => setState(() => _autoCut = v),
                ),
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Buka Laci Kasir Otomatis (RJ11) Saat Tunai'),
                  value: _openDrawer,
                  onChanged: (v) => setState(() => _openDrawer = v),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
        ElevatedButton(
          onPressed: () async {
            if (_nameCtrl.text.trim().isEmpty) return;
            final model = PrinterDeviceModel(
              id: widget.printer?.id,
              name: _nameCtrl.text.trim(),
              category: _category,
              connectionType: _connectionType,
              address: _connectionType == PrinterConnectionType.system ? 'system_pdf' : _addressCtrl.text.trim(),
              port: int.tryParse(_portCtrl.text.trim()) ?? 9100,
              paperSize: _paperSize,
              protocol: _protocol,
              isDefault: _isDefault,
              autoCut: _autoCut,
              openDrawer: _openDrawer,
            );
            await Provider.of<PrinterProvider>(context, listen: false).savePrinter(model);
            if (mounted) Navigator.pop(context);
          },
          child: const Text('Simpan Printer'),
        ),
      ],
    );
  }
}
