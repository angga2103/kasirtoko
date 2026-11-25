import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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
import '../../utils/app_theme.dart';
import '../../widgets/image_picker_cropper.dart';
import '../employees/employee_management_screen.dart';
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
