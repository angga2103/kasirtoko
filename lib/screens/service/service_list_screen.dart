import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/service_order.dart';
import '../../models/user.dart';
import '../../providers/auth_provider.dart';
import '../../providers/service_order_provider.dart';
import '../../utils/app_theme.dart';
import '../../utils/currency_format.dart';
import '../../utils/date_format.dart';
import 'service_detail_screen.dart';
import 'service_form_screen.dart';

class ServiceListScreen extends StatefulWidget {
  const ServiceListScreen({super.key});

  @override
  State<ServiceListScreen> createState() => _ServiceListScreenState();
}

class _ServiceListScreenState extends State<ServiceListScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  bool _onlyMyJobs = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      if (auth.isTechnician) {
        setState(() => _onlyMyJobs = true);
      }
      _reload();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _reload({String? status, String? query}) async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final prov = Provider.of<ServiceOrderProvider>(context, listen: false);
    final techId = (_onlyMyJobs && auth.currentUser?.id != null) ? auth.currentUser!.id : null;
    await prov.loadOrders(status: status, technicianId: techId, query: query);
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    if (!auth.hasPermission(AppPermissions.manageService)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Jasa Servis HP & Elektronik')),
        body: const Center(child: Text('Anda tidak memiliki izin mengakses modul Servis.')),
      );
    }

    final prov = Provider.of<ServiceOrderProvider>(context);
    final statusTabs = ['semua', ...ServiceStatus.all];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Servis HP & Elektronik'),
        actions: [
          if (auth.isTechnician || auth.isSupervisor)
            FilterChip(
              label: Text(
                _onlyMyJobs ? 'Tugas Saya' : 'Semua Tiket',
                style: const TextStyle(fontSize: 11, color: Colors.white),
              ),
              selected: _onlyMyJobs,
              backgroundColor: Colors.white12,
              selectedColor: AppTheme.accentOrange,
              checkmarkColor: Colors.white,
              onSelected: (v) {
                setState(() => _onlyMyJobs = v);
                _reload();
              },
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.white,
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Cari no. tiket, pelanggan, model, atau IMEI/SN...',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchCtrl.clear();
                          _reload(query: '');
                        },
                      )
                    : null,
              ),
              onChanged: (v) => _reload(query: v),
            ),
          ),

          Container(
            height: 44,
            color: Colors.white,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              itemCount: statusTabs.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (_, index) {
                final st = statusTabs[index];
                final selected = prov.statusFilter == st;
                return ChoiceChip(
                  label: Text(
                    st == 'semua' ? 'Semua' : ServiceStatus.label(st),
                    style: TextStyle(fontSize: 11.5, color: selected ? Colors.white : AppTheme.textDark),
                  ),
                  selected: selected,
                  selectedColor: AppTheme.primaryGreen,
                  backgroundColor: AppTheme.lightGreyBg,
                  onSelected: (_) => _reload(status: st),
                );
              },
            ),
          ),
          const Divider(height: 1),

          Expanded(
            child: prov.isLoading
                ? const Center(child: CircularProgressIndicator())
                : prov.orders.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.build_circle_outlined, size: 54, color: AppTheme.textMuted),
                            const SizedBox(height: 10),
                            const Text('Belum ada tiket servis pada kategori ini.'),
                            const SizedBox(height: 10),
                            ElevatedButton.icon(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (_) => const ServiceFormScreen()),
                                );
                              },
                              icon: const Icon(Icons.add),
                              label: const Text('Terima Servis Baru'),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: prov.orders.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, index) {
                          final o = prov.orders[index];
                          final stColor = ServiceStatus.color(o.status);
                          final effectiveTotal = o.totalCost > 0 ? o.totalCost : o.estimatedCost;

                          return Card(
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (_) => ServiceDetailScreen(orderId: o.id!)),
                                ).then((_) => _reload());
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(o.ticketNumber,
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: AppTheme.primaryGreen)),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: stColor.withValues(alpha: 0.14),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            ServiceStatus.label(o.status),
                                            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: stColor),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${o.deviceType} ${o.brand} ${o.model} (${o.customerName})',
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                    ),
                                    Text(
                                      'Keluhan: ${o.complaint}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                                    ),
                                    const SizedBox(height: 6),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          'Teknisi: ${o.technicianName} • ${DateHelper.formatShort(o.createdAt)}',
                                          style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                                        ),
                                        Text(
                                          o.remainingPayment > 0
                                              ? 'Sisa: ${CurrencyHelper.format(o.remainingPayment)}'
                                              : 'Total: ${CurrencyHelper.format(effectiveTotal)}',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12.5,
                                            color: o.remainingPayment > 0 ? AppTheme.accentOrange : AppTheme.success,
                                          ),
                                        ),
                                      ],
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
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppTheme.primaryGreen,
        foregroundColor: Colors.white,
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ServiceFormScreen()),
          ).then((_) => _reload());
        },
        icon: const Icon(Icons.build_rounded),
        label: const Text('Terima Servis'),
      ),
    );
  }
}
