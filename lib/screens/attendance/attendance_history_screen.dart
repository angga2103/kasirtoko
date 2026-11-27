import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../database/db_helper.dart';
import '../../models/attendance.dart';
import '../../providers/attendance_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/whatsapp_service.dart';
import '../../utils/app_theme.dart';
import '../../utils/date_format.dart';

class AttendanceHistoryScreen extends StatefulWidget {
  const AttendanceHistoryScreen({super.key});

  @override
  State<AttendanceHistoryScreen> createState() => _AttendanceHistoryScreenState();
}

class _AttendanceHistoryScreenState extends State<AttendanceHistoryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<AttendanceProvider>(context, listen: false).loadAttendances();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _showAdminCorrectDialog(AttendanceModel att) async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final attProv = Provider.of<AttendanceProvider>(context, listen: false);
    final admin = auth.currentUser;
    if (admin == null || !admin.isOwnerOrAdmin) return;

    String status = att.status == 'terlambat' ? 'terlambat' : 'tepat_waktu';
    final lateCtrl = TextEditingController(text: att.lateMinutes.toString());
    final noteCtrl = TextEditingController(text: att.correctionNote);
    String? errMsg;
    bool saving = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDState) => AlertDialog(
          title: Text('Koreksi Admin • ${att.employeeName}', style: const TextStyle(fontSize: 16)),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Absen ${att.type.toUpperCase()} • ${DateHelper.formatFull(att.timestamp)}',
                    style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: status,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Status Kedisiplinan Terkoreksi'),
                    items: const [
                      DropdownMenuItem(value: 'tepat_waktu', child: Text('TEPAT WAKTU', maxLines: 1, overflow: TextOverflow.ellipsis)),
                      DropdownMenuItem(value: 'terlambat', child: Text('TERLAMBAT', maxLines: 1, overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (v) {
                      setDState(() {
                        status = v ?? 'tepat_waktu';
                        if (status == 'tepat_waktu') lateCtrl.text = '0';
                      });
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: lateCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Menit Keterlambatan'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: noteCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Alasan Koreksi Owner/Admin *',
                      hintText: 'Misal: Izin dinas / kendala teknis',
                    ),
                  ),
                  if (errMsg != null) ...[
                    const SizedBox(height: 8),
                    Text(errMsg!, style: const TextStyle(color: AppTheme.accentRed, fontSize: 12)),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: saving ? null : () => Navigator.pop(ctx), child: const Text('Batal')),
            ElevatedButton(
              onPressed: saving
                  ? null
                  : () async {
                      final lateMin = int.tryParse(lateCtrl.text.trim()) ?? 0;
                      if (noteCtrl.text.trim().isEmpty) {
                        setDState(() => errMsg = 'Alasan koreksi wajib diisi.');
                        return;
                      }
                      setDState(() {
                        saving = true;
                        errMsg = null;
                      });
                      try {
                        await DatabaseHelper.instance.correctAttendanceByAdmin(
                          attendanceId: att.id!,
                          newStatus: status,
                          newLateMinutes: status == 'tepat_waktu' ? 0 : lateMin,
                          correctionNote: noteCtrl.text.trim(),
                          admin: admin,
                        );
                        await attProv.loadAttendances();
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) {
                          ScaffoldMessenger.of(this.context).showSnackBar(
                            const SnackBar(
                              content: Text('Koreksi absensi berhasil disimpan & dicatat di Log Audit.'),
                              backgroundColor: AppTheme.success,
                            ),
                          );
                        }
                      } catch (e) {
                        setDState(() {
                          saving = false;
                          errMsg = e.toString().replaceFirst('Bad state: ', '');
                        });
                      }
                    },
              child: Text(saving ? 'Menyimpan...' : 'Simpan Koreksi'),
            ),
          ],
        ),
      ),
    ).then((_) {
      lateCtrl.dispose();
      noteCtrl.dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    final attProv = Provider.of<AttendanceProvider>(context);
    final settings = Provider.of<SettingsProvider>(context);
    final auth = Provider.of<AuthProvider>(context);
    final isOwnerOrAdmin = auth.currentUser?.isOwnerOrAdmin == true;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Laporan Kedisiplinan Karyawan'),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: AppTheme.accentOrange,
          tabs: const [
            Tab(text: 'Rekap Kedisiplinan'),
            Tab(text: 'Galeri Foto & Hash'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildDisciplineSummaryTab(attProv),
          _buildPhotoLogsTab(attProv, settings, isOwnerOrAdmin),
        ],
      ),
    );
  }

  Widget _buildDisciplineSummaryTab(AttendanceProvider attProv) {
    final summaries = attProv.getWeeklyDisciplineSummary();

    if (summaries.isEmpty) {
      return const Center(child: Text('Belum ada data absensi untuk direkap.'));
    }

    return ListView.separated(
      padding: const EdgeInsets.all(14),
      itemCount: summaries.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final s = summaries[index];
        final rate = s.disciplineRate;

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      s.employeeName,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: rate >= 80 ? Colors.green.shade100 : Colors.red.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'Kedisiplinan: ${rate.toStringAsFixed(0)}%',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: rate >= 80 ? Colors.green.shade800 : Colors.red.shade800,
                        ),
                      ),
                    ),
                  ],
                ),
                const Divider(height: 20),

                Row(
                  children: [
                    Expanded(
                      child: _buildSummaryItem('Total Masuk', '${s.totalPresent} Hari', Colors.blue),
                    ),
                    Expanded(
                      child: _buildSummaryItem('Tepat Waktu', '${s.onTimeCount} Hari', Colors.green),
                    ),
                    Expanded(
                      child: _buildSummaryItem('Terlambat', '${s.lateCount} Kali', Colors.red),
                    ),
                  ],
                ),
                if (s.totalLateMinutes > 0) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Akumulasi Keterlambatan: ${s.totalLateMinutes} Menit',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.accentRed),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSummaryItem(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: color)),
      ],
    );
  }

  Widget _buildPhotoLogsTab(AttendanceProvider attProv, SettingsProvider settings, bool isOwnerOrAdmin) {
    if (attProv.attendances.isEmpty) {
      return const Center(child: Text('Belum ada foto absensi yang tersimpan.'));
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: attProv.attendances.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final a = attProv.attendances[index];
        final photoFile = File(a.photoPath);

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: 72,
                    height: 96,
                    color: Colors.grey.shade200,
                    child: photoFile.existsSync()
                        ? Image.file(photoFile, fit: BoxFit.cover)
                        : const Icon(Icons.person, size: 36, color: Colors.grey),
                  ),
                ),
                const SizedBox(width: 12),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              a.employeeName,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: a.isLate ? Colors.red.shade100 : Colors.green.shade100,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              a.isLate ? 'TERLAMBAT' : 'TEPAT WAKTU',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.bold,
                                color: a.isLate ? Colors.red.shade800 : Colors.green.shade800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${a.type.toUpperCase()} • ${DateHelper.formatFull(a.timestamp)}',
                        style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Token: ${a.challengeCode} • Hash: ${a.validationHash}',
                        style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.amber),
                      ),
                      Text(
                        'Liveness: ${a.isLivenessPassed ? "Lolos (Manusia Hidup Asli)" : "Manual"}${a.deviceInfo.isNotEmpty ? " • ${a.deviceInfo}" : ""}',
                        style: const TextStyle(fontSize: 10, color: AppTheme.textMuted),
                      ),
                      if (a.isCorrected)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'Dikoreksi Admin: ${a.correctionNote}',
                            style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: AppTheme.accentOrange),
                          ),
                        ),
                    ],
                  ),
                ),

                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.share_rounded, color: Colors.green),
                      tooltip: 'Kirim Ulang ke WA Owner',
                      onPressed: () async {
                        await WhatsAppService.sendAttendanceToAdmin(
                          attendance: a,
                          ownerPhone: settings.ownerPhone,
                          storeName: settings.storeName,
                        );
                      },
                    ),
                    if (isOwnerOrAdmin && a.id != null)
                      IconButton(
                        icon: const Icon(Icons.edit_note_rounded, color: AppTheme.accentOrange),
                        tooltip: 'Koreksi Audit Admin',
                        onPressed: () => _showAdminCorrectDialog(a),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
