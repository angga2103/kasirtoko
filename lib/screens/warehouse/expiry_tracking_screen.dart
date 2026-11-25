import 'package:flutter/material.dart';
import '../../database/db_helper.dart';
import '../../utils/app_theme.dart';
import '../../utils/date_format.dart';

class ExpiryTrackingScreen extends StatefulWidget {
  const ExpiryTrackingScreen({super.key});

  @override
  State<ExpiryTrackingScreen> createState() => _ExpiryTrackingScreenState();
}

class _ExpiryTrackingScreenState extends State<ExpiryTrackingScreen> {
  List<Map<String, dynamic>> _batches = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadBatches();
  }

  Future<void> _loadBatches() async {
    final list = await DatabaseHelper.instance.getExpiringBatches();
    setState(() {
      _batches = list;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pengingat Kadaluarsa Produk'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _batches.isEmpty
              ? const Center(
                  child: Text('Semua produk aman! Tidak ada batch mendekati kadaluarsa.'),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: _batches.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final b = _batches[index];
                    final expiryDate = DateTime.parse(b['expiry_date']);
                    final daysLeft = DateHelper.daysDifference(expiryDate);

                    Color statusColor;
                    String statusLabel;
                    if (daysLeft < 0) {
                      statusColor = AppTheme.accentRed;
                      statusLabel = 'KADALUARSA (${-daysLeft} hari lalu)';
                    } else if (daysLeft <= 7) {
                      statusColor = AppTheme.accentOrange;
                      statusLabel = 'KRITIS ($daysLeft hari lagi)';
                    } else if (daysLeft <= 30) {
                      statusColor = Colors.amber.shade800;
                      statusLabel = 'PERINGATAN ($daysLeft hari lagi)';
                    } else {
                      statusColor = AppTheme.primaryGreen;
                      statusLabel = 'AMAN ($daysLeft hari lagi)';
                    }

                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: statusColor.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(Icons.event_busy_rounded, color: statusColor, size: 26),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    b['product_name'] ?? '',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                  Text(
                                    'Batch: ${b['batch_number']} • Sisa: ${b['stock_qty'].toInt()} ${b['base_unit']}',
                                    style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                                  ),
                                  Text(
                                    'Kadaluarsa: ${DateHelper.formatShort(expiryDate)}',
                                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: statusColor.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: statusColor.withOpacity(0.4)),
                              ),
                              child: Text(
                                statusLabel,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: statusColor,
                                ),
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
