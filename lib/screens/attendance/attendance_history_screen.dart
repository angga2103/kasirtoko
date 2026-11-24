import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/attendance_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/whatsapp_service.dart';
import '../../utils/app_theme.dart';
import '../../utils/date_format.dart';

class AttendanceHistoryScreen extends StatefulWidget {
  const AttendanceHistoryScreen({super.key});

  @override
  State<AttendanceHistoryScreen> createState() => _AttendanceHistoryScreenState();
}

class _AttendanceHistoryScreenState extends State<AttendanceHistoryScreen> with SingleTickerProviderStateMixin {
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
  Widget build(BuildContext context) {
    final attProv = Provider.of<AttendanceProvider>(context);
    final settings = Provider.of<SettingsProvider>(context);

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
          _buildPhotoLogsTab(attProv, settings),
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

  Widget _buildPhotoLogsTab(AttendanceProvider attProv, SettingsProvider settings) {
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
                // Photo thumbnail
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

                // Attendance Meta Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            a.employeeName,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
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
                        'Kode: ${a.validationHash}',
                        style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.amber),
                      ),
                      Text(
                        'Liveness: ${a.isLivenessPassed ? "Lolos (Manusia Hidup Asli)" : "Manual"}',
                        style: const TextStyle(fontSize: 10, color: AppTheme.textMuted),
                      ),
                    ],
                  ),
                ),

                // Resend to WhatsApp
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
              ],
            ),
          ),
        );
      },
    );
  }
}
