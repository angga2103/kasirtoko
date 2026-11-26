import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../models/paired_terminal.dart';
import '../../models/print_job.dart';
import '../../models/user.dart';
import '../../providers/auth_provider.dart';
import '../../providers/printer_provider.dart';
import '../../providers/server_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/server_lifecycle_bridge.dart';
import '../../utils/app_theme.dart';

class MultiDeviceServerScreen extends StatefulWidget {
  const MultiDeviceServerScreen({super.key});

  @override
  State<MultiDeviceServerScreen> createState() => _MultiDeviceServerScreenState();
}

class _MultiDeviceServerScreenState extends State<MultiDeviceServerScreen> {
  final TextEditingController _portCtrl = TextEditingController(text: '8443');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<PosServerProvider>(context, listen: false).refreshStatus();
      Provider.of<SettingsProvider>(context, listen: false).refreshRegistersAndAssignments();
      Provider.of<PrinterProvider>(context, listen: false).loadPrinters();
    });
  }

  @override
  void dispose() {
    _portCtrl.dispose();
    super.dispose();
  }

  Future<void> _showCreatePairingDialog(
    PosServerProvider srvProv,
    SettingsProvider setProv,
    AuthProvider authProv,
  ) async {
    final nameCtrl = TextEditingController(text: 'Kasir Staff ${srvProv.terminals.length + 1}');
    int? selectedRegisterId =
        setProv.cashRegisters.isNotEmpty ? setProv.cashRegisters.first.id : null;
    bool allowAutoDrawer = false;
    bool allowManualDrawer = false;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: const Text('Tambah Terminal Staff Baru'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nama Terminal / Meja Kasir',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int?>(
                  value: selectedRegisterId,
                  decoration: const InputDecoration(
                    labelText: 'Laci Kas yang Ditugaskan',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<int?>(
                      value: null,
                      child: Text('Otomatis / Default Toko'),
                    ),
                    ...setProv.cashRegisters
                        .where((r) => r.isActive)
                        .map((r) => DropdownMenuItem<int?>(
                              value: r.id,
                              child: Text('${r.registerCode} — ${r.name}'),
                            )),
                  ],
                  onChanged: (v) => setDlgState(() => selectedRegisterId = v),
                ),
                const SizedBox(height: 10),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Izinkan Buka Laci Otomatis (Pembayaran Tunai)',
                      style: TextStyle(fontSize: 13)),
                  value: allowAutoDrawer,
                  onChanged: (v) => setDlgState(() => allowAutoDrawer = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Izinkan Buka Laci Manual (Butuh Permission Kasir)',
                      style: TextStyle(fontSize: 13)),
                  value: allowManualDrawer,
                  onChanged: (v) => setDlgState(() => allowManualDrawer = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal'),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.qr_code_2_rounded),
              label: const Text('Buat QR Pairing'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) return;
    await srvProv.createPairingBanner(
      suggestedName: nameCtrl.text.trim(),
      assignedRegisterId: selectedRegisterId,
      allowAutoOpenDrawer: allowAutoDrawer,
      allowManualOpenDrawer: allowManualDrawer,
      actorName: authProv.currentUser?.name ?? 'Admin',
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    if (!auth.hasPermission(AppPermissions.manageStoreSettings)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Server Multi-Perangkat')),
        body: const Center(
          child: Text('Hanya Admin / Owner berwenang yang dapat mengelola server multi-perangkat.'),
        ),
      );
    }

    final srvProv = Provider.of<PosServerProvider>(context);
    final setProv = Provider.of<SettingsProvider>(context);
    final prnProv = Provider.of<PrinterProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Server POS LAN & Terminal Staff'),
        actions: [
          IconButton(
            tooltip: 'Muat Ulang Status',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => srvProv.refreshStatus(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => srvProv.refreshStatus(),
        child: ListView(
          padding: const EdgeInsets.all(14),
          children: [
            _buildServerStatusCard(srvProv, setProv),
            if (srvProv.activePairing != null) ...[
              const SizedBox(height: 14),
              _buildActivePairingCard(srvProv, srvProv.activePairing!),
            ],
            const SizedBox(height: 14),
            _buildTerminalsSection(srvProv, setProv, prnProv, auth),
            const SizedBox(height: 14),
            _buildPrintJobsSection(srvProv),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildServerStatusCard(PosServerProvider srvProv, SettingsProvider setProv) {
    final running = srvProv.isRunning;
    final identity = srvProv.identity;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: running
                      ? AppTheme.success.withValues(alpha: 0.12)
                      : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  running ? Icons.wifi_tethering_rounded : Icons.wifi_tethering_off_rounded,
                  color: running ? AppTheme.success : AppTheme.textMuted,
                  size: 26,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      running
                          ? 'Server HTTPS/WSS Aktif (Port ${srvProv.port})'
                          : 'Server LAN Nonaktif',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Mode Laci: ${setProv.drawerMode} • Socket Terhubung: ${srvProv.connectedSockets.length}',
                      style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                    ),
                  ],
                ),
              ),
              Switch(
                value: running,
                onChanged: srvProv.isBusy
                    ? null
                    : (val) async {
                        if (val) {
                          final parsedPort = int.tryParse(_portCtrl.text.trim()) ?? 8443;
                          await srvProv.startServer(port: parsedPort);
                        } else {
                          await srvProv.stopServer();
                        }
                      },
              ),
            ],
          ),
          if (!running) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                SizedBox(
                  width: 120,
                  child: TextField(
                    controller: _portCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Port HTTPS',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Aktifkan Wi-Fi atau Hotspot Android sebelum menyalakan server agar terminal Staff dapat tersambung.',
                    style: TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
                  ),
                ),
              ],
            ),
          ],
          if (srvProv.lastError != null) ...[
            const SizedBox(height: 8),
            Text(srvProv.lastError!,
                style: const TextStyle(color: AppTheme.accentRed, fontSize: 12)),
          ],
          const Divider(height: 22),
          Text(
            'Alamat IP Lokal Admin: ${srvProv.localIps.join(", ")}',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5),
          ),
          if (identity != null) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.blueGrey.shade50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.verified_user_outlined, size: 16, color: AppTheme.primaryGreen),
                      const SizedBox(width: 6),
                      Text(
                        'PIN Checksum TLS Sertifikat: ${identity.shortPin}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  SelectableText(
                    'SHA-256: ${identity.sha256Hex}',
                    style: const TextStyle(fontSize: 10.5, fontFamily: 'monospace'),
                  ),
                  if (identity.nextSha256Hex != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Rotasi Sertifikat Disiapkan -> Next: ${identity.nextSha256Hex!.substring(0, 12).toUpperCase()}',
                      style: const TextStyle(fontSize: 11, color: Colors.deepOrange),
                    ),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ElevatedButton.icon(
                onPressed: () => _showCreatePairingDialog(
                  srvProv,
                  setProv,
                  Provider.of<AuthProvider>(context, listen: false),
                ),
                icon: const Icon(Icons.qr_code_2_rounded, size: 18),
                label: const Text('Pairing Terminal Baru'),
              ),
              if (!srvProv.fgsStatus.ignoringBatteryOptimizations)
                OutlinedButton.icon(
                  onPressed: () => ServerLifecycleBridge.requestIgnoreBatteryOptimizations(),
                  icon: const Icon(Icons.battery_saver_rounded, size: 18, color: Colors.orange),
                  label: const Text('Nonaktifkan Batasi Baterai'),
                ),
              if (running)
                OutlinedButton.icon(
                  onPressed: () async {
                    await srvProv.stageCertificateRotation();
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Sertifikat TLS berikutnya disiapkan untuk rotasi bertahap.'),
                      ),
                    );
                  },
                  icon: const Icon(Icons.autorenew_rounded, size: 18),
                  label: const Text('Siapkan Rotasi TLS'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Catatan: Foreground service Android (`specialUse`) menjaga server tetap prioritas tinggi, namun OS/OEM masih dapat menghentikan proses pada kondisi ekstrem. Transaksi Staff selalu dilindungi idempotency.',
            style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildActivePairingCard(PosServerProvider srvProv, ActivePairingBanner banner) {
    final primaryIp = banner.serverIps.isNotEmpty ? banner.serverIps.first : '127.0.0.1';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.primaryGreenSoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.primaryGreen),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.qr_code_scanner_rounded, color: AppTheme.primaryGreen),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'QR Pairing Aktif (Sekali Pakai • 5 Menit)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: srvProv.clearActivePairing,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Center(
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: QrImageView(
                data: banner.qrPayloadJson,
                version: QrVersions.auto,
                size: 190,
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text('Atau Masukkan Secara Manual di POS Staff:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
          const SizedBox(height: 4),
          SelectableText('Alamat Server : https://$primaryIp:${banner.port}'),
          SelectableText('Kode Pairing  : ${banner.ticket.pairingCode}'),
          SelectableText('Checksum Cert : ${banner.shortPin}'),
          const SizedBox(height: 6),
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(
                text: '$primaryIp:${banner.port} | Code: ${banner.ticket.pairingCode} | Pin: ${banner.shortPin}',
              ));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Info pairing disalin ke clipboard.')),
              );
            },
            icon: const Icon(Icons.copy_rounded, size: 16),
            label: const Text('Salin Info Pairing'),
          ),
        ],
      ),
    );
  }

  Widget _buildTerminalsSection(
    PosServerProvider srvProv,
    SettingsProvider setProv,
    PrinterProvider prnProv,
    AuthProvider authProv,
  ) {
    final terminals = srvProv.terminals;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Terminal Terdaftar (${terminals.length})',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 4),
          const Text(
            'Tidak ada batasan tetap jumlah terminal. Performa praktis bergantung kapasitas Wi-Fi/Hotspot.',
            style: TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
          ),
          const SizedBox(height: 10),
          if (terminals.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text('Belum ada terminal Staff yang dipasangkan.'),
              ),
            )
          else
            ...terminals.map((t) => _buildTerminalRow(t, srvProv, setProv, prnProv, authProv)),
        ],
      ),
    );
  }

  Widget _buildTerminalRow(
    PairedTerminalModel t,
    PosServerProvider srvProv,
    SettingsProvider setProv,
    PrinterProvider prnProv,
    AuthProvider authProv,
  ) {
    final online = srvProv.isTerminalOnline(t.terminalId);
    final actor = authProv.currentUser?.name ?? 'Admin';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.isRevoked ? Colors.red.shade50 : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: t.isRevoked
              ? Colors.red.shade200
              : (online ? AppTheme.success : Colors.grey.shade300),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.point_of_sale_rounded,
                color: t.isRevoked
                    ? AppTheme.accentRed
                    : (online ? AppTheme.success : AppTheme.textMuted),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${t.terminalName} (${t.terminalId})',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                    ),
                    Text(
                      'Model: ${t.deviceModel.isEmpty ? "-" : t.deviceModel} • Laci #${t.assignedRegisterId ?? "-"}',
                      style: const TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: t.isRevoked
                      ? AppTheme.accentRed
                      : (online ? AppTheme.success : Colors.grey.shade400),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  t.isRevoked ? 'DICABUT' : (online ? 'ONLINE' : 'OFFLINE'),
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          if (!t.isRevoked) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int?>(
                    value: setProv.cashRegisters.any((r) => r.id == t.assignedRegisterId)
                        ? t.assignedRegisterId
                        : null,
                    isDense: true,
                    decoration: const InputDecoration(
                      labelText: 'Laci Kasir',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<int?>(value: null, child: Text('Default / Ikut Kasir')),
                      ...setProv.cashRegisters
                          .where((r) => r.isActive)
                          .map((r) => DropdownMenuItem<int?>(
                                value: r.id,
                                child: Text(r.registerCode),
                              )),
                    ],
                    onChanged: (v) => srvProv.updateTerminalPolicy(
                      terminalId: t.terminalId,
                      assignedRegisterId: v,
                      clearAssignedRegister: v == null,
                      actorName: actor,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<int?>(
                    value: prnProv.printers.any((p) => p.id == t.defaultPrinterId)
                        ? t.defaultPrinterId
                        : null,
                    isDense: true,
                    decoration: const InputDecoration(
                      labelText: 'Printer Default',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<int?>(value: null, child: Text('Ikut Default Admin')),
                      ...prnProv.printers.map((p) => DropdownMenuItem<int?>(
                            value: p.id,
                            child: Text(p.name, overflow: TextOverflow.ellipsis),
                          )),
                    ],
                    onChanged: (v) => srvProv.updateTerminalPolicy(
                      terminalId: t.terminalId,
                      defaultPrinterId: v,
                      clearDefaultPrinter: v == null,
                      actorName: actor,
                    ),
                  ),
                ),
              ],
            ),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('Buka Laci Otomatis (Transaksi Tunai)', style: TextStyle(fontSize: 12)),
              value: t.allowAutoOpenDrawer,
              onChanged: (v) => srvProv.updateTerminalPolicy(
                terminalId: t.terminalId,
                allowAutoOpenDrawer: v,
                actorName: actor,
              ),
            ),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('Buka Laci Manual (Perlu Izin Kasir)', style: TextStyle(fontSize: 12)),
              value: t.allowManualOpenDrawer,
              onChanged: (v) => srvProv.updateTerminalPolicy(
                terminalId: t.terminalId,
                allowManualOpenDrawer: v,
                actorName: actor,
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () async {
                  await srvProv.revokeTerminal(t.terminalId, actorName: actor);
                },
                icon: const Icon(Icons.block_rounded, color: AppTheme.accentRed, size: 18),
                label: const Text(
                  'Cabut Akses Terminal',
                  style: TextStyle(color: AppTheme.accentRed),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPrintJobsSection(PosServerProvider srvProv) {
    final jobs = srvProv.printJobs;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Antrean Printer Terpusat (${jobs.length})',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 8),
          if (jobs.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('Belum ada riwayat antrean cetak.', style: TextStyle(color: AppTheme.textMuted)),
            )
          else
            ...jobs.take(15).map((job) {
              final canRetry = job.status == PrintJobStatus.failed;
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  '${job.invoiceNumber.isNotEmpty ? job.invoiceNumber : job.jobType} • ${job.terminalId}',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5),
                ),
                subtitle: Text(
                  'Status: ${job.status} • Percobaan: ${job.attempts}'
                  '${job.drawerPulseSent ? ' • Pulse Laci 1x' : ''}'
                  '${job.errorMessage.isNotEmpty ? '\n${job.errorMessage}' : ''}',
                  style: const TextStyle(fontSize: 11),
                ),
                trailing: canRetry
                    ? TextButton(
                        onPressed: () => srvProv.retryPrintJob(job.jobUuid),
                        child: const Text('Cetak Ulang'),
                      )
                    : null,
              );
            }),
        ],
      ),
    );
  }
}
