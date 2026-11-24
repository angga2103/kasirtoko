import 'package:flutter/material.dart';
import '../../models/audit_log.dart';
import '../../database/db_helper.dart';
import '../../utils/app_theme.dart';
import '../../utils/date_format.dart';

class AuditLogScreen extends StatefulWidget {
  const AuditLogScreen({super.key});

  @override
  State<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends State<AuditLogScreen> {
  List<AuditLogModel> _logs = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    final list = await DatabaseHelper.instance.getAuditLogs(limit: 100);
    setState(() {
      _logs = list;
      _isLoading = false;
    });
  }

  Color _getActionColor(String actionType) {
    switch (actionType) {
      case 'void_transaksi':
      case 'hapus_item':
        return Colors.red;
      case 'ubah_harga':
      case 'buka_laci':
        return Colors.orange;
      case 'retur_transaksi':
        return Colors.indigo;
      case 'stok_opname':
        return Colors.blue;
      case 'absensi_selfie':
        return Colors.purple;
      default:
        return AppTheme.primaryGreen;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Log Audit Keamanan Karyawan'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _logs.isEmpty
              ? const Center(child: Text('Belum ada log aktivitas tercatat.'))
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: _logs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final log = _logs[index];
                    final color = _getActionColor(log.actionType);

                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: color.withOpacity(0.12),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(Icons.security_rounded, color: color, size: 20),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        log.actionDisplay,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                          color: color,
                                        ),
                                      ),
                                      Text(
                                        DateHelper.formatTime(log.timestamp),
                                        style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    log.details,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Pelaku: ${log.userName} (${log.userRole.toUpperCase()}) • ${DateHelper.formatShort(log.timestamp)}',
                                    style: const TextStyle(fontSize: 10, color: AppTheme.textMuted),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
