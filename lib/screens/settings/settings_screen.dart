import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/backup_service.dart';
import '../../services/thermal_printer_service.dart';
import '../../utils/app_theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _nameCtrl;
  late TextEditingController _addressCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _ownerPhoneCtrl;
  late TextEditingController _footerCtrl;
  late TextEditingController _shiftHourCtrl;
  String _paperSize = '58mm';

  @override
  void initState() {
    super.initState();
    final s = Provider.of<SettingsProvider>(context, listen: false);
    _nameCtrl = TextEditingController(text: s.storeName);
    _addressCtrl = TextEditingController(text: s.storeAddress);
    _phoneCtrl = TextEditingController(text: s.storePhone);
    _ownerPhoneCtrl = TextEditingController(text: s.ownerPhone);
    _footerCtrl = TextEditingController(text: s.receiptFooter);
    _shiftHourCtrl = TextEditingController(text: s.shiftStartHour);
    _paperSize = s.printerPaperSize;
  }

  Future<void> _saveSettings() async {
    final s = Provider.of<SettingsProvider>(context, listen: false);
    await s.updateSettings(
      name: _nameCtrl.text.trim(),
      address: _addressCtrl.text.trim(),
      phone: _phoneCtrl.text.trim(),
      ownerPhone: _ownerPhoneCtrl.text.trim(),
      footer: _footerCtrl.text.trim(),
      paperSize: _paperSize,
      startHour: _shiftHourCtrl.text.trim(),
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Pengaturan toko berhasil diperbarui!')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context, listen: false);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pengaturan & Backup Data'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Store Profile Section
            const Text('Profil Toko:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Column(
                children: [
                  TextField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(labelText: 'Nama Toko'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _addressCtrl,
                    decoration: const InputDecoration(labelText: 'Alamat Toko'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'No. Telp Toko'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _ownerPhoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'No. WhatsApp Owner (Penerima Laporan & Absensi) *',
                      hintText: '08xxxxxxxxxx',
                      prefixIcon: Icon(Icons.phone_android_rounded),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _shiftHourCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Jam Masuk Standar (Acuan Keterlambatan Absensi)',
                      hintText: '08:00',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Printer Thermal & Laci Kasir Section
            const Text('Printer Thermal & Laci Kasir (RJ11):',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Ukuran Kertas Printer Thermal:', style: TextStyle(fontSize: 12)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: ChoiceChip(
                          label: const Center(child: Text('58 mm (Standard Mobile)')),
                          selected: _paperSize == '58mm',
                          selectedColor: AppTheme.primaryGreenLight,
                          onSelected: (val) {
                            if (val) setState(() => _paperSize = '58mm');
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ChoiceChip(
                          label: const Center(child: Text('80 mm (Desktop / POS)')),
                          selected: _paperSize == '80mm',
                          selectedColor: AppTheme.primaryGreenLight,
                          onSelected: (val) {
                            if (val) setState(() => _paperSize = '80mm');
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _footerCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Catatan Footer Struk',
                      hintText: 'Terima kasih atas kunjungan Anda!',
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Cash drawer test button
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.point_of_sale_rounded, color: AppTheme.accentOrange),
                          label: const Text('Tes Buka Laci Kasir', style: TextStyle(color: AppTheme.accentOrange)),
                          onPressed: () {
                            auth.logAction('buka_laci', 'Tes sinyal buka laci kasir manual');
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Sinyal pulse RJ11 buka laci kasir terkirim!')),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Backup & Restore Database Section
            const Text('Pencadangan (Backup) & Pemulihan Database:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Cadangkan seluruh database toko (produk, riwayat transaksi, kasbon, absensi) ke file lokal, Google Drive, atau kirim langsung via WhatsApp.',
                    style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                  ),
                  const SizedBox(height: 14),

                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryGreen),
                          icon: const Icon(Icons.cloud_upload_rounded),
                          label: const Text('Cadangkan Data (Backup)'),
                          onPressed: () async {
                            final res = await BackupService.createAndShareBackup();
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(res.message),
                                  backgroundColor: res.success ? AppTheme.primaryGreen : AppTheme.accentRed,
                                ),
                              );
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.restore_page_rounded),
                          label: const Text('Pulihkan Data (Restore)'),
                          onPressed: () async {
                            final res = await BackupService.restoreDatabase();
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(res.message),
                                  backgroundColor: res.success ? AppTheme.primaryGreen : AppTheme.accentRed,
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
            const SizedBox(height: 24),

            // Save Settings Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saveSettings,
                child: const Text('SIMPAN SEMUA PENGATURAN', style: TextStyle(fontSize: 15)),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
