import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../database/db_helper.dart';
import '../../models/audit_log.dart';
import '../../providers/auth_provider.dart';
import '../../utils/app_theme.dart';
import '../../utils/date_format.dart';

class AuditLogScreen extends StatefulWidget {
  const AuditLogScreen({super.key});

  @override
  State<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends State<AuditLogScreen> {
  static const int _pageSize = 30;

  final TextEditingController _searchCtrl = TextEditingController();
  List<AuditLogModel> _logs = [];
  bool _isLoading = true;
  bool _loadingMore = false;
  bool _hasMore = true;

  String _rangePreset = 'today'; // 'today' | 'yesterday' | '7d' | 'all' | 'custom'
  late DateTime _startDate;
  late DateTime _endDate;
  int? _selectedUserId;
  String _selectedAction = 'semua';

  static const List<Map<String, String>> _actionOptions = [
    {'value': 'semua', 'label': 'Semua Aktivitas'},
    {'value': 'login', 'label': 'Login Berhasil'},
    {'value': 'login_gagal', 'label': 'Login Gagal'},
    {'value': 'transaksi_selesai', 'label': 'Transaksi Penjualan'},
    {'value': 'void_transaksi', 'label': 'Void / Batal Transaksi'},
    {'value': 'retur_transaksi', 'label': 'Retur Barang'},
    {'value': 'pembelian_stok', 'label': 'Pembelian Supplier'},
    {'value': 'pembelian_void', 'label': 'Void Pembelian'},
    {'value': 'bayar_kasbon', 'label': 'Pelunasan Kasbon'},
    {'value': 'bayar_utang_supplier', 'label': 'Bayar Utang Supplier'},
    {'value': 'buka_shift', 'label': 'Buka Shift'},
    {'value': 'tutup_shift', 'label': 'Tutup Shift'},
    {'value': 'koreksi_shift', 'label': 'Koreksi Audit Shift'},
    {'value': 'kas_masuk', 'label': 'Kas Masuk'},
    {'value': 'kas_keluar', 'label': 'Kas Keluar'},
    {'value': 'stok_opname', 'label': 'Stok Opname'},
    {'value': 'absensi_selfie', 'label': 'Absensi Selfie'},
    {'value': 'koreksi_absensi', 'label': 'Koreksi Absensi'},
    {'value': 'karyawan_tambah', 'label': 'Tambah Karyawan'},
    {'value': 'karyawan_ubah', 'label': 'Ubah Hak/Data Karyawan'},
    {'value': 'karyawan_aktif', 'label': 'Aktifkan Karyawan'},
    {'value': 'karyawan_nonaktif', 'label': 'Nonaktifkan Karyawan'},
    {'value': 'login_staff_terminal', 'label': 'Login Staff Terminal'},
    {'value': 'login_staff_ditolak_batas_sesi', 'label': 'Login Staff Ditolak (Batas Sesi)'},
    {'value': 'logout_staff_terminal', 'label': 'Logout Staff Terminal'},
    {'value': 'cabut_sesi_staff', 'label': 'Cabut Sesi Perangkat'},
    {'value': 'cabut_semua_sesi_akun', 'label': 'Cabut Semua Sesi Akun'},
    {'value': 'cabut_terminal', 'label': 'Cabut Akses Terminal'},
    {'value': 'rotasi_kredensial_terminal', 'label': 'Rotasi Token Terminal'},
    {'value': 'ubah_kebijakan_sesi', 'label': 'Ubah Kebijakan Batas Sesi'},
    {'value': 'backup_otomatis', 'label': 'Backup Otomatis (.ktbak)'},
    {'value': 'backup_manual', 'label': 'Backup Manual (.ktbak)'},
    {'value': 'backup_gagal', 'label': 'Backup Gagal / Peringatan'},
    {'value': 'restore_database', 'label': 'Restore Database'},
    {'value': 'failover_jaringan', 'label': 'Profil Jaringan / Failover'},
  ];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _startDate = DateTime(now.year, now.month, now.day);
    _endDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<AuthProvider>(context, listen: false).loadUsers(includeInactive: true);
      _loadLogs(reset: true);
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadLogs({bool reset = false}) async {
    if (reset) {
      setState(() {
        _isLoading = true;
        _hasMore = true;
      });
    } else {
      if (_loadingMore || !_hasMore) return;
      setState(() => _loadingMore = true);
    }

    final offset = reset ? 0 : _logs.length;
    final list = await DatabaseHelper.instance.getAuditLogsFiltered(
      start: _rangePreset == 'all' ? null : _startDate,
      end: _rangePreset == 'all' ? null : _endDate,
      userId: _selectedUserId,
      actionType: _selectedAction,
      searchQuery: _searchCtrl.text.trim(),
      limit: _pageSize,
      offset: offset,
    );

    if (!mounted) return;
    setState(() {
      if (reset) {
        _logs = list;
      } else {
        _logs = [..._logs, ...list];
      }
      _hasMore = list.length >= _pageSize;
      _isLoading = false;
      _loadingMore = false;
    });
  }

  Future<void> _applyPreset(String preset) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (preset == 'custom') {
      final range = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2020),
        lastDate: DateTime(now.year + 1),
        initialDateRange: DateTimeRange(start: _startDate, end: _endDate.isAfter(today) ? today : _endDate),
      );
      if (range == null) return;
      _rangePreset = 'custom';
      _startDate = DateTime(range.start.year, range.start.month, range.start.day);
      _endDate = DateTime(range.end.year, range.end.month, range.end.day, 23, 59, 59);
    } else {
      _rangePreset = preset;
      switch (preset) {
        case 'today':
          _startDate = today;
          _endDate = DateTime(today.year, today.month, today.day, 23, 59, 59);
          break;
        case 'yesterday':
          final y = today.subtract(const Duration(days: 1));
          _startDate = y;
          _endDate = DateTime(y.year, y.month, y.day, 23, 59, 59);
          break;
        case '7d':
          _startDate = today.subtract(const Duration(days: 6));
          _endDate = DateTime(today.year, today.month, today.day, 23, 59, 59);
          break;
      }
    }
    await _loadLogs(reset: true);
  }

  Color _getActionColor(String actionType) {
    if (actionType.contains('void') || actionType.contains('gagal') || actionType.contains('hapus')) {
      return Colors.red;
    }
    if (actionType.contains('koreksi') || actionType.contains('ubah') || actionType.contains('laci')) {
      return Colors.orange;
    }
    if (actionType.contains('retur')) return Colors.indigo;
    if (actionType.contains('opname')) return Colors.blue;
    if (actionType.contains('absensi')) return Colors.purple;
    return AppTheme.primaryGreen;
  }

  void _showImmutableDetailDialog(AuditLogModel log) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.verified_user_rounded, color: AppTheme.primaryGreen, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(log.actionDisplay, style: const TextStyle(fontSize: 16))),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Waktu: ${DateHelper.formatFull(log.timestamp)}', style: const TextStyle(fontSize: 12)),
                Text('Pelaku: ${log.userName} (ID #${log.userId})', style: const TextStyle(fontSize: 12)),
                Text('Modul: ${log.module.toUpperCase()}${log.objectId.isNotEmpty ? " • Objek: ${log.objectId}" : ""}', style: const TextStyle(fontSize: 12)),
                const Divider(height: 16),
                const Text('Deskripsi Aktivitas:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                const SizedBox(height: 4),
                Text(log.details, style: const TextStyle(fontSize: 12.5)),
                if (log.beforeValue.isNotEmpty || log.afterValue.isNotEmpty) ...[
                  const Divider(height: 16),
                  const Text('Perubahan Nilai (Before → After):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                  const SizedBox(height: 4),
                  if (log.beforeValue.isNotEmpty)
                    Text('Sebelum: ${log.beforeValue}', style: const TextStyle(fontSize: 11.5, color: AppTheme.accentRed)),
                  if (log.afterValue.isNotEmpty)
                    Text('Sesudah: ${log.afterValue}', style: const TextStyle(fontSize: 11.5, color: AppTheme.primaryGreen)),
                ],
                const SizedBox(height: 10),
                const Text(
                  'Catatan: Log audit bersifat permanen (read-only) dan tidak dapat diubah atau dihapus.',
                  style: TextStyle(fontSize: 10.5, fontStyle: FontStyle.italic, color: AppTheme.textMuted),
                ),
              ],
            ),
          ),
        ),
        actions: [ElevatedButton(onPressed: () => Navigator.pop(ctx), child: const Text('Tutup'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final users = Provider.of<AuthProvider>(context).users;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Log Audit Keamanan (Read-Only)'),
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _presetChip('today', 'Hari Ini'),
                      const SizedBox(width: 6),
                      _presetChip('yesterday', 'Kemarin'),
                      const SizedBox(width: 6),
                      _presetChip('7d', '7 Hari'),
                      const SizedBox(width: 6),
                      _presetChip('all', 'Semua Waktu'),
                      const SizedBox(width: 6),
                      _presetChip(
                        'custom',
                        _rangePreset == 'custom'
                            ? '${DateHelper.formatShort(_startDate)} - ${DateHelper.formatShort(_endDate)}'
                            : 'Kustom',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int?>(
                        value: users.any((u) => u.id == _selectedUserId) ? _selectedUserId : null,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Pengguna / Karyawan', isDense: true),
                        items: [
                          const DropdownMenuItem<int?>(value: null, child: Text('Semua User')),
                          ...users.map((u) => DropdownMenuItem<int?>(
                                value: u.id,
                                child: Text('${u.name} (${u.roleDisplay})', overflow: TextOverflow.ellipsis),
                              )),
                        ],
                        onChanged: (v) {
                          setState(() => _selectedUserId = v);
                          _loadLogs(reset: true);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _selectedAction,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Aktivitas', isDense: true),
                        items: _actionOptions
                            .map((opt) => DropdownMenuItem(
                                  value: opt['value'],
                                  child: Text(opt['label']!, overflow: TextOverflow.ellipsis),
                                ))
                            .toList(),
                        onChanged: (v) {
                          setState(() => _selectedAction = v ?? 'semua');
                          _loadLogs(reset: true);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: 'Cari modul, nomor nota/objek, atau keterangan...',
                    isDense: true,
                    prefixIcon: const Icon(Icons.search_rounded, size: 19),
                    suffixIcon: _searchCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 17),
                            onPressed: () {
                              _searchCtrl.clear();
                              _loadLogs(reset: true);
                            },
                          )
                        : null,
                  ),
                  onChanged: (_) => _loadLogs(reset: true),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _logs.isEmpty
                    ? const Center(child: Text('Tidak ada log audit yang cocok dengan filter ini.'))
                    : ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: _logs.length + (_hasMore ? 1 : 0),
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          if (index >= _logs.length) {
                            return Center(
                              child: OutlinedButton.icon(
                                onPressed: _loadingMore ? null : () => _loadLogs(reset: false),
                                icon: _loadingMore
                                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                                    : const Icon(Icons.expand_more_rounded),
                                label: Text(_loadingMore ? 'Memuat...' : 'Muat Lebih Banyak Log'),
                              ),
                            );
                          }

                          final log = _logs[index];
                          final color = _getActionColor(log.actionType);

                          return Card(
                            child: InkWell(
                              onTap: () => _showImmutableDetailDialog(log),
                              borderRadius: BorderRadius.circular(12),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: color.withValues(alpha: 0.12),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(Icons.security_rounded, color: color, size: 19),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  log.actionDisplay,
                                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: color),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                              Text(
                                                DateHelper.formatFull(log.timestamp),
                                                style: const TextStyle(fontSize: 10, color: AppTheme.textMuted),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 2),
                                          Text(log.details, style: const TextStyle(fontSize: 12)),
                                          const SizedBox(height: 4),
                                          Wrap(
                                            spacing: 8,
                                            children: [
                                              Text(
                                                'Oleh: ${log.userName}',
                                                style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: AppTheme.textSecondary),
                                              ),
                                              Text(
                                                'Modul: ${log.module.toUpperCase()}',
                                                style: const TextStyle(fontSize: 10.5, color: AppTheme.textMuted),
                                              ),
                                              if (log.beforeValue.isNotEmpty || log.afterValue.isNotEmpty)
                                                const Text(
                                                  '• Lihat Perubahan (Diff)',
                                                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: AppTheme.accentBlue),
                                                ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _presetChip(String key, String label) {
    final selected = _rangePreset == key;
    return ChoiceChip(
      label: Text(label, style: TextStyle(fontSize: 11.5, color: selected ? Colors.white : AppTheme.textDark)),
      selected: selected,
      selectedColor: AppTheme.primaryGreen,
      onSelected: (_) => _applyPreset(key),
    );
  }
}
