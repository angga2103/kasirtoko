import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../database/db_helper.dart';
import '../../models/operational_models.dart';
import '../../models/user.dart';
import '../../providers/attendance_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/backup_provider.dart';
import '../../providers/cash_flow_provider.dart';
import '../../providers/customer_provider.dart';
import '../../providers/debt_provider.dart';
import '../../providers/printer_provider.dart';
import '../../providers/product_provider.dart';
import '../../providers/purchase_provider.dart';
import '../../providers/service_order_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/backup_service.dart';
import '../../utils/app_theme.dart';
import '../../utils/date_format.dart';

class BackupManagementScreen extends StatefulWidget {
  const BackupManagementScreen({super.key});

  @override
  State<BackupManagementScreen> createState() => _BackupManagementScreenState();
}

class _BackupManagementScreenState extends State<BackupManagementScreen> {
  String _serverId = '-';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final bProv = Provider.of<BackupProvider>(context, listen: false);
      await bProv.refreshStatus();
      final id = await DatabaseHelper.instance.getOrCreateServerId();
      if (mounted) setState(() => _serverId = id);
    });
  }

  String _formatBytes(int bytes) {
    if (bytes < 0) return 'Tidak tersedia';
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }

  Future<void> _showPassphraseDialog(BackupProvider bProv, AuthProvider auth) async {
    final passCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        title: const Text('Kunci Pemulihan Backup Lintas HP'),
        content: AppBreakpoints.scrollableDialogContent(
          ctx,
          maxWidth: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Jika HP Admin rusak dan diganti baru, passphrase ini membungkus DEK AES-256-GCM sehingga file .ktbak dapat dipulihkan di HP pengganti.',
                style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passCtrl,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Passphrase Pemulihan (min. 6 karakter)'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: confirmCtrl,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Ulangi Passphrase'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          ElevatedButton(
            onPressed: () {
              if (passCtrl.text.trim().length < 6 || passCtrl.text.trim() != confirmCtrl.text.trim()) {
                return;
              }
              Navigator.pop(ctx, true);
            },
            child: const Text('Simpan Kunci'),
          ),
        ],
      ),
    );
    final pass = passCtrl.text.trim();
    passCtrl.dispose();
    confirmCtrl.dispose();
    if (ok != true || !mounted) return;

    await BackupService.configureRecoveryPassphrase(
      pass,
      actorName: auth.currentUser?.name ?? 'Admin',
    );
    await bProv.refreshStatus();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Passphrase pemulihan backup tersimpan di Android Keystore vault.'),
        backgroundColor: AppTheme.success,
      ),
    );
  }

  Future<void> _showSecondaryFolderDialog(BackupProvider bProv) async {
    final job = bProv.hourlyJob;
    final ctrl = TextEditingController(text: job?.secondaryUri ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        title: const Text('Salinan Lokasi Kedua & SAF'),
        content: AppBreakpoints.scrollableDialogContent(
          ctx,
          maxWidth: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Masukkan path folder lokal terpisah untuk salinan otomatis berkala, atau pilih folder Android melalui Storage Access Framework (SAF).',
                style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: ctrl,
                decoration: const InputDecoration(
                  labelText: 'Path Folder Salinan Kedua (Opsional)',
                  hintText: '/storage/emulated/0/Download/KasirTokoBackups',
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                icon: const Icon(Icons.folder_open_rounded),
                label: const Text('Pilih Folder SAF Android'),
                onPressed: () async {
                  final uri = await BackupService.pickSafFolderTreeUri();
                  if (uri != null && uri.isNotEmpty) {
                    await bProv.configureJob(
                      jobType: 'hourly_snapshot',
                      targetLocationType: 'saf',
                      targetUri: uri,
                    );
                    await bProv.configureJob(
                      jobType: 'nightly_full',
                      targetLocationType: 'saf',
                      targetUri: uri,
                    );
                    if (ctx.mounted) Navigator.pop(ctx, true);
                  }
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Simpan Path')),
        ],
      ),
    );
    final sec = ctrl.text.trim();
    ctrl.dispose();
    if (ok != true || !mounted) return;
    await bProv.configureJob(jobType: 'hourly_snapshot', secondaryUri: sec);
    await bProv.configureJob(jobType: 'nightly_full', secondaryUri: sec);
  }

  Future<void> _confirmAndRestore({
    BackupArtifactModel? artifact,
  }) async {
    final passCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        title: const Text('Konfirmasi Restore Database'),
        content: AppBreakpoints.scrollableDialogContent(
          ctx,
          maxWidth: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                artifact != null
                    ? 'Database aktif akan digantikan oleh "${artifact.fileName}". Sebelum ditimpa, sistem otomatis membuat backup keselamatan pre-restore terlebih dahulu.'
                    : 'Pilih file backup (.ktbak / .db). Sistem otomatis memverifikasi SHA-256 + integritas SQLite serta membuat backup keselamatan sebelum restore.',
                style: const TextStyle(fontSize: 12.5),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Passphrase Pemulihan (isi jika dari HP lain)',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accentOrange),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ya, Pulihkan Database'),
          ),
        ],
      ),
    );
    final pass = passCtrl.text.trim();
    passCtrl.dispose();
    if (confirmed != true || !mounted) return;

    final bProv = Provider.of<BackupProvider>(context, listen: false);
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final res = artifact != null
        ? await bProv.restoreFromArtifact(
            artifact,
            recoveryPassphrase: pass.isEmpty ? null : pass,
            actorName: auth.currentUser?.name ?? 'Admin',
          )
        : await BackupService.restoreDatabase(
            recoveryPassphrase: pass.isEmpty ? null : pass,
          );

    if (res.success && mounted) {
      await Provider.of<SettingsProvider>(context, listen: false).loadSettings();
      if (!mounted) return;
      await Provider.of<ProductProvider>(context, listen: false).loadProducts();
      if (!mounted) return;
      await Provider.of<CashFlowProvider>(context, listen: false).checkOpenShift();
      if (!mounted) return;
      await Provider.of<CustomerProvider>(context, listen: false).loadCustomers();
      if (!mounted) return;
      await Provider.of<DebtProvider>(context, listen: false).loadDebts();
      if (!mounted) return;
      await Provider.of<PurchaseProvider>(context, listen: false).loadPurchases();
      if (!mounted) return;
      await Provider.of<AttendanceProvider>(context, listen: false).loadAttendances();
      if (!mounted) return;
      await Provider.of<ServiceOrderProvider>(context, listen: false).loadOrders();
      if (!mounted) return;
      await Provider.of<PrinterProvider>(context, listen: false).loadPrinters();
      if (!mounted) return;
      await auth.loadUsers();
      await bProv.refreshStatus();
    }

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
    if (!auth.hasPermission(AppPermissions.manageStoreSettings)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Backup Otomatis Database')),
        body: const Center(child: Text('Akses ditolak. Hubungi Owner/Admin.')),
      );
    }

    final bProv = Provider.of<BackupProvider>(context);
    final latest = bProv.latestArtifact;
    final hourly = bProv.hourlyJob;
    final nightly = bProv.nightlyJob;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manajemen Backup Otomatis'),
        actions: [
          IconButton(
            tooltip: 'Muat Ulang',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: bProv.isBusy ? null : () => bProv.refreshStatus(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => bProv.refreshStatus(),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              padding: const EdgeInsets.all(14),
              children: [
                if (bProv.hasWarning) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.accentRedSoft,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.accentRed),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded, color: AppTheme.accentRed),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            bProv.isLowStorage
                                ? 'Peringatan: Ruang penyimpanan hampir penuh (${_formatBytes(bProv.availableStorageBytes)} tersisa).'
                                : (bProv.lastError ?? 'Terdapat job backup gagal atau belum terverifikasi.'),
                            style: const TextStyle(color: AppTheme.accentRed, fontWeight: FontWeight.w600, fontSize: 12.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                _buildSummaryCard(bProv, auth, latest),
                const SizedBox(height: 12),
                _buildScheduleCard(bProv, hourly, nightly),
                const SizedBox(height: 12),
                _buildArtifactsCard(bProv),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryCard(BackupProvider bProv, AuthProvider auth, BackupArtifactModel? latest) {
    final lastTime = latest != null ? DateHelper.formatFull(DateTime.tryParse(latest.createdAt) ?? DateTime.now()) : 'Belum pernah';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppBreakpoints.spaceBetweenRow(
            const Text('Status Backup Terenkripsi (.ktbak)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: (latest?.verifiedRestoreOk ?? false) ? Colors.green.shade50 : Colors.orange.shade50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                (latest?.verifiedRestoreOk ?? false) ? 'TERVERIFIKASI' : 'SIAGA',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.bold,
                  color: (latest?.verifiedRestoreOk ?? false) ? AppTheme.success : AppTheme.accentOrange,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text('Server ID        : $_serverId', style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
          Text('Backup Terakhir  : $lastTime', style: const TextStyle(fontSize: 12)),
          Text('Ruang Tersisa    : ${_formatBytes(bProv.availableStorageBytes)}', style: const TextStyle(fontSize: 12)),
          Text(
            'Kunci Pemulihan  : ${bProv.hasRecoveryPassphrase ? "Terkonfigurasi (Multi-HP Siap)" : "Hanya Keystore HP Ini"}',
            style: const TextStyle(fontSize: 12),
          ),
          Text(
            'Konektor Cloud   : ${BackupService.cloudConnector.providerLabel}',
            style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ElevatedButton.icon(
                onPressed: bProv.isBusy
                    ? null
                    : () async {
                        final res = await bProv.runBackupNow(
                          backupType: 'manual',
                          actorName: auth.currentUser?.name ?? 'Admin',
                        );
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(res.message),
                            backgroundColor: res.success ? AppTheme.success : AppTheme.accentRed,
                          ),
                        );
                      },
                icon: const Icon(Icons.backup_rounded, size: 18),
                label: Text(bProv.isBusy ? 'Memproses...' : 'Backup Sekarang'),
              ),
              OutlinedButton.icon(
                onPressed: bProv.isBusy ? null : () => _showPassphraseDialog(bProv, auth),
                icon: const Icon(Icons.vpn_key_rounded, size: 18),
                label: const Text('Kunci Pemulihan'),
              ),
              OutlinedButton.icon(
                onPressed: bProv.isBusy ? null : () => _confirmAndRestore(),
                icon: const Icon(Icons.restore_page_rounded, size: 18),
                label: const Text('Restore File...'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildScheduleCard(BackupProvider bProv, BackupJobModel? hourly, BackupJobModel? nightly) {
    final locSummary = (hourly?.targetLocationType == 'saf' && (hourly?.targetUri.isNotEmpty ?? false))
        ? 'SAF URI: ${hourly!.targetUri}'
        : 'Folder Terpisah Aplikasi (Non-DB Dir)';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Jadwal Otomatis & Lokasi Terpisah', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 6),
          Material(
            color: Colors.white,
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Backup Periodik Tiap 1 Jam', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
              subtitle: const Text('Snapshot WAL-konsisten (VACUUM INTO) + AES-256-GCM + tes restore', style: TextStyle(fontSize: 11.5)),
              value: hourly?.isEnabled ?? true,
              onChanged: (v) => bProv.configureJob(jobType: 'hourly_snapshot', isEnabled: v),
            ),
          ),
          Material(
            color: Colors.white,
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Backup Penuh Harian (Malam 23:30)', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
              subtitle: const Text('Cadangan penuh harian + verifikasi integritas & checksum SHA-256', style: TextStyle(fontSize: 11.5)),
              value: nightly?.isEnabled ?? true,
              onChanged: (v) => bProv.configureJob(jobType: 'nightly_full', isEnabled: v),
            ),
          ),
          const Divider(),
          Text('Lokasi Utama : $locSummary', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
          if ((hourly?.secondaryUri ?? '').isNotEmpty)
            Text('Salinan Kedua: ${hourly!.secondaryUri}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _showSecondaryFolderDialog(bProv),
            icon: const Icon(Icons.drive_folder_upload_rounded, size: 18),
            label: const Text('Atur Lokasi SAF / Salinan Kedua'),
          ),
        ],
      ),
    );
  }

  Widget _buildArtifactsCard(BackupProvider bProv) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Riwayat Backup & Verifikasi (${bProv.artifacts.length})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 8),
          if (bProv.artifacts.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('Belum ada riwayat backup terenkripsi. Tekan "Backup Sekarang" untuk memulai.', style: TextStyle(color: AppTheme.textMuted)),
            )
          else
            ...bProv.artifacts.map((art) {
              final dt = DateTime.tryParse(art.createdAt);
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.lightGreyBg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: art.verifiedRestoreOk ? Colors.green.shade200 : AppTheme.borderLight,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppBreakpoints.spaceBetweenRow(
                      Text(art.fileName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                      Text(
                        art.verifiedRestoreOk ? 'VERIFIED' : art.status.toUpperCase(),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: art.verifiedRestoreOk ? AppTheme.success : AppTheme.accentRed,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${dt != null ? DateHelper.formatFull(dt) : art.createdAt} • ${art.backupType} • ${_formatBytes(art.encryptedSizeBytes)}',
                      style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                    ),
                    if (art.encryptedSha256.isNotEmpty)
                      Text(
                        'SHA-256: ${art.encryptedSha256.substring(0, 16)}...',
                        style: const TextStyle(fontSize: 10.5, fontFamily: 'monospace', color: AppTheme.textSecondary),
                      ),
                    if (art.verificationSummary.isNotEmpty)
                      Text(art.verificationSummary, style: const TextStyle(fontSize: 10.5, color: AppTheme.primaryGreen)),
                    if (art.errorMessage.isNotEmpty)
                      Text(art.errorMessage, style: const TextStyle(fontSize: 10.5, color: AppTheme.accentRed)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        TextButton.icon(
                          onPressed: bProv.isBusy
                              ? null
                              : () async {
                                  final v = await bProv.verifyArtifact(art);
                                  if (!mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(v.message),
                                      backgroundColor: v.valid ? AppTheme.success : AppTheme.accentRed,
                                    ),
                                  );
                                },
                          icon: const Icon(Icons.verified_rounded, size: 16),
                          label: const Text('Tes Restore', style: TextStyle(fontSize: 12)),
                        ),
                        TextButton.icon(
                          onPressed: bProv.isBusy ? null : () => _confirmAndRestore(artifact: art),
                          icon: const Icon(Icons.settings_backup_restore_rounded, size: 16, color: AppTheme.accentOrange),
                          label: const Text('Pulihkan', style: TextStyle(fontSize: 12, color: AppTheme.accentOrange)),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}
