import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../database/db_helper.dart';
import '../../models/cash_register.dart';
import '../../models/store_profile.dart';
import '../../models/user.dart';
import '../../providers/auth_provider.dart';
import '../../providers/cash_flow_provider.dart';
import '../../providers/debt_provider.dart';
import '../../providers/printer_provider.dart';
import '../../providers/product_provider.dart';
import '../../providers/service_order_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/backup_service.dart';
import '../../services/image_media_service.dart';
import '../../services/printer/printer_manager.dart';
import '../../services/server_lifecycle_bridge.dart';
import '../../utils/app_theme.dart';
import '../../widgets/image_picker_cropper.dart';
import '../employees/employee_management_screen.dart';
import 'multi_device_server_screen.dart';
import 'printer_management_screen.dart';
import 'receipt_settings_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _nameCtrl;
  late TextEditingController _branchCtrl;
  late TextEditingController _ownerNameCtrl;
  late TextEditingController _identityCtrl;
  late TextEditingController _addressCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _emailCtrl;
  late TextEditingController _ownerPhoneCtrl;
  late TextEditingController _footerCtrl;
  late TextEditingController _shiftHourCtrl;
  late TextEditingController _currencyCtrl;
  late TextEditingController _invoicePrefixCtrl;
  late TextEditingController _invoiceFormatCtrl;
  late TextEditingController _taxRateCtrl;

  late BusinessType _businessType;
  late String _paperSize;
  late String _logoPath;
  bool _taxEnabled = false;
  ServerLifecycleStatus _fgsStatus = const ServerLifecycleStatus();

  @override
  void initState() {
    super.initState();
    final s = Provider.of<SettingsProvider>(context, listen: false);
    _nameCtrl = TextEditingController(text: s.storeName);
    _branchCtrl = TextEditingController(text: s.branchName);
    _ownerNameCtrl = TextEditingController(text: s.ownerName);
    _identityCtrl = TextEditingController(text: s.businessIdentity);
    _addressCtrl = TextEditingController(text: s.storeAddress);
    _phoneCtrl = TextEditingController(text: s.storePhone);
    _emailCtrl = TextEditingController(text: s.storeEmail);
    _ownerPhoneCtrl = TextEditingController(text: s.ownerPhone);
    _footerCtrl = TextEditingController(text: s.receiptFooter);
    _shiftHourCtrl = TextEditingController(text: s.shiftStartHour);
    _currencyCtrl = TextEditingController(text: s.currencySymbol.trim());
    _invoicePrefixCtrl = TextEditingController(text: s.invoicePrefix);
    _invoiceFormatCtrl = TextEditingController(text: s.invoiceFormat);
    _taxRateCtrl = TextEditingController(text: s.taxRate.toStringAsFixed(0));
    _businessType = s.businessType;
    _paperSize = s.printerPaperSize;
    _logoPath = s.logoPath;
    _taxEnabled = s.taxEnabled;
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadFgsStatus());
  }

  Future<void> _loadFgsStatus() async {
    final status = await ServerLifecycleBridge.getStatus();
    if (mounted) {
      setState(() => _fgsStatus = status);
    }
  }

  Future<void> _showCashRegisterManagerDialog() async {
    final settingsProv = Provider.of<SettingsProvider>(context, listen: false);
    final authProv = Provider.of<AuthProvider>(context, listen: false);
    await settingsProv.refreshRegistersAndAssignments();
    if (!mounted) return;

    final codeCtrl = TextEditingController(text: 'REG-02');
    final nameCtrl = TextEditingController(text: 'Laci Kasir Staff 1');
    final termCtrl = TextEditingController(text: 'STAFF-01');
    final prioCtrl = TextEditingController(text: '10');
    int? selectedRegId = settingsProv.cashRegisters.isNotEmpty ? settingsProv.cashRegisters.first.id : 1;
    int? selectedCashierId;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dCtx, setDState) {
          final regs = settingsProv.cashRegisters;
          final assigns = settingsProv.assignments;
          final users = authProv.activeUsers;
          return AlertDialog(
            title: const Text('Kelola Laci Kas & Penugasan'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Daftar Laci Kas Terdaftar', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 6),
                    ...regs.map(
                      (r) => ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.point_of_sale_rounded,
                            color: r.isActive ? AppTheme.primaryGreen : AppTheme.textMuted),
                        title: Text('${r.registerCode} — ${r.name}'),
                        subtitle: Text(r.isShared ? 'Mode: Shared Drawer' : 'Mode: Individual Drawer'),
                      ),
                    ),
                    const Divider(),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: codeCtrl,
                            decoration: const InputDecoration(labelText: 'Kode Laci (cth: REG-02)'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: nameCtrl,
                            decoration: const InputDecoration(labelText: 'Nama Laci Kas'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () async {
                            final code = codeCtrl.text.trim().toUpperCase();
                            final name = nameCtrl.text.trim();
                            if (code.isEmpty || name.isEmpty) return;
                            try {
                              await DatabaseHelper.instance.insertCashRegister(
                                CashRegisterModel(registerCode: code, name: name, isShared: false),
                              );
                              await settingsProv.refreshRegistersAndAssignments();
                              setDState(() {
                                selectedRegId = settingsProv.cashRegisters.last.id;
                              });
                            } catch (e) {
                              if (dCtx.mounted) {
                                ScaffoldMessenger.of(dCtx).showSnackBar(
                                  SnackBar(content: Text('$e'), backgroundColor: AppTheme.accentRed),
                                );
                              }
                            }
                          },
                          child: const Text('Tambah'),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    const Text('Aturan Assignment (terminal+kasir > kasir > terminal)',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 6),
                    if (assigns.isEmpty)
                      const Text('Belum ada assignment khusus (menggunakan REG-MAIN pada mode SHARED_DRAWER).',
                          style: TextStyle(fontSize: 12, color: AppTheme.textMuted))
                    else
                      ...assigns.map(
                        (a) => ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            'Laci #${a.cashRegisterId} • Term: ${a.terminalId ?? "*"} • Kasir: ${a.cashierId ?? "*"}',
                          ),
                          subtitle: Text('Prioritas: ${a.priority} • Rank: ${a.specificityRank}'),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, color: AppTheme.accentRed, size: 18),
                            onPressed: () async {
                              if (a.id == null) return;
                              await DatabaseHelper.instance.deleteCashRegisterAssignment(a.id!);
                              await settingsProv.refreshRegistersAndAssignments();
                              setDState(() {});
                            },
                          ),
                        ),
                      ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<int>(
                      initialValue: selectedRegId,
                      decoration: const InputDecoration(labelText: 'Pilih Laci Kas'),
                      items: regs
                          .map((r) => DropdownMenuItem(value: r.id, child: Text('${r.registerCode} (${r.name})')))
                          .toList(),
                      onChanged: (v) => setDState(() => selectedRegId = v),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: termCtrl,
                            decoration: const InputDecoration(labelText: 'Terminal ID (opsional)'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: DropdownButtonFormField<int?>(
                            initialValue: selectedCashierId,
                            decoration: const InputDecoration(labelText: 'Kasir (opsional)'),
                            items: [
                              const DropdownMenuItem<int?>(value: null, child: Text('Semua Kasir (*)')),
                              ...users.map((u) => DropdownMenuItem<int?>(value: u.id, child: Text(u.name))),
                            ],
                            onChanged: (v) => setDState(() => selectedCashierId = v),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: prioCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Prioritas Angka'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () async {
                            if (selectedRegId == null) return;
                            try {
                              await DatabaseHelper.instance.saveCashRegisterAssignment(
                                CashRegisterAssignmentModel(
                                  cashRegisterId: selectedRegId!,
                                  terminalId: termCtrl.text.trim().isEmpty ? null : termCtrl.text.trim(),
                                  cashierId: selectedCashierId,
                                  priority: int.tryParse(prioCtrl.text.trim()) ?? 0,
                                  assignedBy: authProv.currentUser?.name ?? 'Admin',
                                ),
                                actor: authProv.currentUser,
                              );
                              await settingsProv.refreshRegistersAndAssignments();
                              setDState(() {});
                            } catch (e) {
                              if (dCtx.mounted) {
                                ScaffoldMessenger.of(dCtx).showSnackBar(
                                  SnackBar(content: Text('$e'), backgroundColor: AppTheme.accentRed),
                                );
                              }
                            }
                          },
                          child: const Text('Simpan Assignment'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Tutup')),
            ],
          );
        },
      ),
    ).whenComplete(() {
      codeCtrl.dispose();
      nameCtrl.dispose();
      termCtrl.dispose();
      prioCtrl.dispose();
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _branchCtrl.dispose();
    _ownerNameCtrl.dispose();
    _identityCtrl.dispose();
    _addressCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _ownerPhoneCtrl.dispose();
    _footerCtrl.dispose();
    _shiftHourCtrl.dispose();
    _currencyCtrl.dispose();
    _invoicePrefixCtrl.dispose();
    _invoiceFormatCtrl.dispose();
    _taxRateCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickLogo() async {
    final path = await ImagePickerHelper.pickAndCropImage(
      context,
      prefix: 'store_logo',
      title: 'Logo Toko (Kamera / Galeri)',
      saveAsPng: true,
    );
    if (path != null && mounted) {
      setState(() => _logoPath = path);
      await Provider.of<SettingsProvider>(context, listen: false).updateLogoPath(path);
    }
  }

  Future<void> _removeLogo() async {
    await ImageMediaService.deleteLocalMedia(_logoPath);
    if (!mounted) return;
    setState(() => _logoPath = '');
    await Provider.of<SettingsProvider>(context, listen: false).updateLogoPath('');
  }

  Future<void> _saveSettings() async {
    final s = Provider.of<SettingsProvider>(context, listen: false);
    final auth = Provider.of<AuthProvider>(context, listen: false);

    await s.updateSettings(
      name: _nameCtrl.text.trim(),
      branchName: _branchCtrl.text.trim(),
      ownerName: _ownerNameCtrl.text.trim(),
      businessIdentity: _identityCtrl.text.trim(),
      address: _addressCtrl.text.trim(),
      phone: _phoneCtrl.text.trim(),
      email: _emailCtrl.text.trim(),
      ownerPhone: _ownerPhoneCtrl.text.trim(),
      logoPath: _logoPath,
      businessType: _businessType,
      currencySymbol: _currencyCtrl.text.trim(),
      invoicePrefix: _invoicePrefixCtrl.text.trim(),
      invoiceFormat: _invoiceFormatCtrl.text.trim(),
      taxEnabled: _taxEnabled,
      taxRate: double.tryParse(_taxRateCtrl.text) ?? 11.0,
      footer: _footerCtrl.text.trim(),
      paperSize: _paperSize,
      startHour: _shiftHourCtrl.text.trim(),
    );

    await auth.logAction('ubah_pengaturan', 'Memperbarui profil toko & konfigurasi jenis usaha (${_businessType.label})');

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Profil toko & konfigurasi Universal POS tersimpan!')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final printerProv = Provider.of<PrinterProvider>(context);
    final logoFile = _logoPath.isNotEmpty ? File(_logoPath) : null;
    final hasLogo = logoFile != null && logoFile.existsSync();

    if (!auth.hasPermission(AppPermissions.manageStoreSettings)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Pengaturan Toko')),
        body: const Center(child: Text('Akses ditolak. Hubungi Owner/Admin.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pengaturan Toko Universal & Backup'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Logo & Business Type
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: AppTheme.cardDecoration(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Logo Toko & Jenis Usaha Universal',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Container(
                            width: 78,
                            height: 78,
                            decoration: BoxDecoration(
                              color: AppTheme.lightGreyBg,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: AppTheme.borderLight),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: hasLogo
                                ? Image.file(logoFile, fit: BoxFit.contain)
                                : const Icon(Icons.storefront_rounded, size: 36, color: AppTheme.textMuted),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                ElevatedButton.icon(
                                  onPressed: _pickLogo,
                                  icon: const Icon(Icons.upload_rounded, size: 18),
                                  label: Text(hasLogo ? 'Ubah / Crop Logo' : 'Upload / Kamera Logo'),
                                ),
                                if (hasLogo)
                                  OutlinedButton.icon(
                                    onPressed: _removeLogo,
                                    icon: const Icon(Icons.delete_outline, size: 18, color: AppTheme.accentRed),
                                    label: const Text('Hapus', style: TextStyle(color: AppTheme.accentRed)),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<BusinessType>(
                        value: _businessType,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Konfigurasi Jenis Usaha (Universal POS)',
                          helperText: 'Mengubah jenis usaha menyesuaikan tampilan modul tanpa menghapus data lama.',
                        ),
                        items: BusinessType.values
                            .map((bt) => DropdownMenuItem(
                                  value: bt,
                                  child: Text(bt.label),
                                ))
                            .toList(),
                        onChanged: (v) {
                          if (v != null) setState(() => _businessType = v);
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Store Profile Details
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: AppTheme.cardDecoration(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Profil & Identitas Usaha',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      const SizedBox(height: 12),
                      TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Nama Toko *')),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _branchCtrl,
                              decoration: const InputDecoration(labelText: 'Nama Cabang'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _ownerNameCtrl,
                              decoration: const InputDecoration(labelText: 'Nama Pemilik'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _identityCtrl,
                        decoration: const InputDecoration(labelText: 'Identitas / Slogan / NPWP'),
                      ),
                      const SizedBox(height: 10),
                      TextField(controller: _addressCtrl, decoration: const InputDecoration(labelText: 'Alamat Lengkap')),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _phoneCtrl,
                              keyboardType: TextInputType.phone,
                              decoration: const InputDecoration(labelText: 'No. Telp Toko'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _emailCtrl,
                              keyboardType: TextInputType.emailAddress,
                              decoration: const InputDecoration(labelText: 'Email Toko'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _ownerPhoneCtrl,
                              keyboardType: TextInputType.phone,
                              decoration: const InputDecoration(
                                labelText: 'WhatsApp Owner (Laporan & Absensi)',
                                prefixIcon: Icon(Icons.phone_android_rounded),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _shiftHourCtrl,
                              decoration: const InputDecoration(labelText: 'Jam Masuk Standar (08:00)'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Format Nomor Nota, Mata Uang & Pajak
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: AppTheme.cardDecoration(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Penomoran Nota, Mata Uang & Pajak',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _currencyCtrl,
                              decoration: const InputDecoration(labelText: 'Simbol Mata Uang (Rp)'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _invoicePrefixCtrl,
                              decoration: const InputDecoration(labelText: 'Prefix Nota (INV)'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _invoiceFormatCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Format Nomor Transaksi',
                          helperText: 'Token tersedia: {PREFIX}, {YYYYMMDD}, {HHMM}, {RAND}',
                        ),
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Aktifkan PPN / Pajak Penjualan Default'),
                        value: _taxEnabled,
                        onChanged: (v) => setState(() => _taxEnabled = v),
                      ),
                      if (_taxEnabled)
                        TextField(
                          controller: _taxRateCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Persentase Pajak (%)', suffixText: '%'),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Shortcuts to Printer, Struk & Karyawan
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: AppTheme.cardDecoration(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Perangkat Keras, Struk & SDM',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      const SizedBox(height: 8),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const CircleAvatar(
                          backgroundColor: AppTheme.primaryGreenSoft,
                          child: Icon(Icons.print_rounded, color: AppTheme.primaryGreen),
                        ),
                        title: const Text('Manajemen Printer (Thermal, Laser, Dot Matrix)'),
                        subtitle: Text('Printer utama: ${printerProv.defaultPrinter?.name ?? "Belum diatur"}'),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const PrinterManagementScreen()),
                        ),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          backgroundColor: Colors.blue.shade50,
                          child: const Icon(Icons.receipt_long_rounded, color: AppTheme.accentBlue),
                        ),
                        title: const Text('Pengaturan Template & Layout Struk'),
                        subtitle: const Text('Minimalis / Profesional / Retail / Konter HP / Servis'),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const ReceiptSettingsScreen()),
                        ),
                      ),
                      if (auth.hasPermission(AppPermissions.manageEmployees)) ...[
                        const Divider(height: 1),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            backgroundColor: Colors.purple.shade50,
                            child: const Icon(Icons.manage_accounts_rounded, color: AppTheme.accentPurple),
                          ),
                          title: const Text('Manajemen Karyawan & Hak Akses'),
                          subtitle: const Text('Tambah karyawan, atur 7 role & 15 izin granular'),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const EmployeeManagementScreen()),
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.point_of_sale_rounded, color: AppTheme.accentOrange),
                          label: const Text('Tes Buka Laci Kasir RJ11 (Hardware ESC/POS)',
                              style: TextStyle(color: AppTheme.accentOrange)),
                          onPressed: () async {
                            final thermalPrinter = printerProv.getPreferredPrinterFor('thermal');
                            final res = await PrinterManager.openCashDrawer(thermalPrinter);
                            await auth.logAction('buka_laci', 'Tes buka laci kasir (${res.message})');
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(res.message),
                                  backgroundColor: res.success ? AppTheme.success : AppTheme.accentOrange,
                                ),
                              );
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Fondasi Multi-Device, Laci Kas & Foreground Service (Tahap 1)
                Consumer<SettingsProvider>(
                  builder: (_, sProv, _) => Container(
                    padding: const EdgeInsets.all(16),
                    decoration: AppTheme.cardDecoration(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Fondasi Multi-Device, Laci Kas & Android Service',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Tentukan mode shift/laci kas (Shared vs Individual) dan kelola penugasan laci kas. Server LAN aktif akan diaktifkan pada Tahap 2.',
                          style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: sProv.drawerMode,
                          decoration: const InputDecoration(
                            labelText: 'Mode Operasional Laci Kas',
                            prefixIcon: Icon(Icons.point_of_sale_rounded),
                          ),
                          items: DrawerMode.all
                              .map((m) => DropdownMenuItem(value: m, child: Text(DrawerMode.label(m))))
                              .toList(),
                          onChanged: (val) async {
                            if (val == null || val == sProv.drawerMode) return;
                            try {
                              await sProv.updateDrawerMode(val, actor: auth.currentUser);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Mode laci kas diubah ke $val'),
                                    backgroundColor: AppTheme.success,
                                  ),
                                );
                              }
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(e.toString().replaceFirst('Bad state: ', '')),
                                    backgroundColor: AppTheme.accentRed,
                                  ),
                                );
                              }
                            }
                          },
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 10,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              icon: const Icon(Icons.wifi_tethering_rounded),
                              label: const Text('Server LAN & Terminal Staff'),
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const MultiDeviceServerScreen(),
                                  ),
                                );
                              },
                            ),
                            OutlinedButton.icon(
                              icon: const Icon(Icons.assignment_ind_rounded),
                              label: Text('Kelola Laci & Assignment (${sProv.cashRegisters.length})'),
                              onPressed: _showCashRegisterManagerDialog,
                            ),
                            OutlinedButton.icon(
                              icon: Icon(
                                _fgsStatus.isRunning ? Icons.check_circle_outline : Icons.layers_outlined,
                                color: _fgsStatus.isRunning ? AppTheme.success : AppTheme.primaryGreen,
                              ),
                              label: Text(
                                _fgsStatus.isRunning
                                    ? 'FGS Shell Aktif (${_fgsStatus.ipSummary})'
                                    : 'Uji FGS specialUse Shell',
                              ),
                              onPressed: () async {
                                final next = _fgsStatus.isRunning
                                    ? await ServerLifecycleBridge.stopForegroundServerShell()
                                    : await ServerLifecycleBridge.startForegroundServerShell(
                                        storeName: sProv.storeName,
                                      );
                                if (mounted) {
                                  setState(() => _fgsStatus = next);
                                }
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Backup & Restore Database
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: AppTheme.cardDecoration(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Pencadangan (Backup) & Pemulihan Database',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      const SizedBox(height: 6),
                      const Text(
                        'Cadangkan seluruh database SQLite ke perangkat lokal, Google Drive, atau bagikan via WhatsApp.',
                        style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.cloud_upload_rounded),
                              label: const Text('Backup Data'),
                              onPressed: () async {
                                final res = await BackupService.createAndShareBackup();
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(res.message),
                                      backgroundColor: res.success ? AppTheme.success : AppTheme.accentRed,
                                    ),
                                  );
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.restore_page_rounded),
                              label: const Text('Restore Data'),
                              onPressed: () async {
                                final settingsProv = Provider.of<SettingsProvider>(context, listen: false);
                                final productProv = Provider.of<ProductProvider>(context, listen: false);
                                final cashFlowProv = Provider.of<CashFlowProvider>(context, listen: false);
                                final debtProv = Provider.of<DebtProvider>(context, listen: false);
                                final serviceProv = Provider.of<ServiceOrderProvider>(context, listen: false);
                                final printerProv = Provider.of<PrinterProvider>(context, listen: false);
                                final authProv = Provider.of<AuthProvider>(context, listen: false);
                                final messenger = ScaffoldMessenger.of(context);

                                final res = await BackupService.restoreDatabase();
                                if (res.success) {
                                  // Re-sync all active providers immediately without crashing!
                                  await settingsProv.loadSettings();
                                  await productProv.loadProducts();
                                  await cashFlowProv.checkOpenShift();
                                  await debtProv.loadDebts();
                                  await serviceProv.loadOrders();
                                  await printerProv.loadPrinters();
                                  await authProv.loadUsers();
                                }
                                if (context.mounted) {
                                  messenger.showSnackBar(
                                    SnackBar(
                                      content: Text(res.message),
                                      backgroundColor: res.success ? AppTheme.success : AppTheme.accentRed,
                                    ),
                                  );
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.save_rounded),
                    label: const Text('SIMPAN SEMUA PENGATURAN TOKO', style: TextStyle(fontSize: 15)),
                    onPressed: _saveSettings,
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
