import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../database/db_helper.dart';
import '../../models/customer.dart';
import '../../providers/customer_provider.dart';
import '../../utils/app_theme.dart';
import '../../utils/currency_format.dart';
import '../../utils/date_format.dart';

class CustomerListScreen extends StatefulWidget {
  const CustomerListScreen({super.key});

  @override
  State<CustomerListScreen> createState() => _CustomerListScreenState();
}

class _CustomerListScreenState extends State<CustomerListScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  final Map<int, double> _debtCache = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshCustomers();
    });
  }

  Future<void> _refreshCustomers({String? query}) async {
    final prov = Provider.of<CustomerProvider>(context, listen: false);
    await prov.loadCustomers(query: query);
    final debtMap = <int, double>{};
    for (final c in prov.customers) {
      if (c.id != null) {
        debtMap[c.id!] = await DatabaseHelper.instance.getCustomerOutstandingDebt(c.id!, c.name);
      }
    }
    if (mounted) {
      setState(() {
        _debtCache
          ..clear()
          ..addAll(debtMap);
      });
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _openCustomerHistory(CustomerModel c) async {
    final outstanding = c.id != null
        ? await DatabaseHelper.instance.getCustomerOutstandingDebt(c.id!, c.name)
        : 0.0;
    final history = c.id != null
        ? await DatabaseHelper.instance.getCustomerPurchaseHistory(c.id!, c.name)
        : [];
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: DraggableScrollableSheet(
          initialChildSize: 0.65,
          maxChildSize: 0.9,
          minChildSize: 0.4,
          expand: false,
          builder: (_, scrollCtrl) => Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: AppTheme.primaryGreenSoft,
                      child: Text(
                        c.name.isNotEmpty ? c.name[0].toUpperCase() : 'P',
                        style: const TextStyle(color: AppTheme.primaryGreen, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(c.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          Text(c.phone.isEmpty ? 'Tanpa No. HP' : c.phone, style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                        ],
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _openCustomerDialog(customer: c);
                      },
                      icon: const Icon(Icons.edit_outlined, size: 16),
                      label: const Text('Edit'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: outstanding > 0 ? AppTheme.accentRedSoft : AppTheme.primaryGreenSoft,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total Sisa Kasbon Aktif:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      Text(
                        CurrencyHelper.format(outstanding),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: outstanding > 0 ? AppTheme.accentRed : AppTheme.primaryGreen,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text('Riwayat Transaksi (${history.length}):', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                const SizedBox(height: 6),
                Expanded(
                  child: history.isEmpty
                      ? const Center(child: Text('Belum ada riwayat belanja pelanggan ini.', style: TextStyle(color: AppTheme.textMuted)))
                      : ListView.separated(
                          controller: scrollCtrl,
                          itemCount: history.length,
                          separatorBuilder: (_, __) => const Divider(height: 10),
                          itemBuilder: (_, i) {
                            final t = history[i];
                            return ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: Text('#${t.invoiceNumber}', style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text(
                                '${DateHelper.formatFull(t.date)} • ${t.paymentMethod.toUpperCase()} • ${t.items.length} item',
                                style: const TextStyle(fontSize: 11),
                              ),
                              trailing: Text(
                                CurrencyHelper.format(t.grandTotal),
                                style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryGreen),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openCustomerDialog({CustomerModel? customer}) {
    final nameCtrl = TextEditingController(text: customer?.name ?? '');
    final phoneCtrl = TextEditingController(text: customer?.phone ?? '');
    final addressCtrl = TextEditingController(text: customer?.address ?? '');
    final emailCtrl = TextEditingController(text: customer?.email ?? '');
    final notesCtrl = TextEditingController(text: customer?.notes ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(customer == null ? 'Tambah Pelanggan Baru' : 'Edit Pelanggan'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Nama Pelanggan *'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'No. HP / WhatsApp'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: addressCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Alamat'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email (Opsional)'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: notesCtrl,
                  decoration: const InputDecoration(labelText: 'Catatan'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          ElevatedButton(
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty) return;
              final model = CustomerModel(
                id: customer?.id,
                name: nameCtrl.text.trim(),
                phone: phoneCtrl.text.trim(),
                address: addressCtrl.text.trim(),
                email: emailCtrl.text.trim(),
                notes: notesCtrl.text.trim(),
                points: customer?.points ?? 0,
                createdAt: customer?.createdAt,
              );
              await Provider.of<CustomerProvider>(context, listen: false).saveCustomer(model);
              await _refreshCustomers(query: _searchCtrl.text);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    ).then((_) {
      nameCtrl.dispose();
      phoneCtrl.dispose();
      addressCtrl.dispose();
      emailCtrl.dispose();
      notesCtrl.dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    final prov = Provider.of<CustomerProvider>(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Daftar Pelanggan')),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.white,
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Cari nama atau nomor HP pelanggan...',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchCtrl.clear();
                          _refreshCustomers(query: '');
                        },
                      )
                    : null,
              ),
              onChanged: (v) => _refreshCustomers(query: v),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: prov.isLoading
                ? const Center(child: CircularProgressIndicator())
                : prov.customers.isEmpty
                    ? const Center(child: Text('Belum ada data pelanggan.'))
                    : ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: prov.customers.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, index) {
                          final c = prov.customers[index];
                          final debtBal = c.id != null ? (_debtCache[c.id!] ?? 0.0) : 0.0;
                          return Card(
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: AppTheme.primaryGreenSoft,
                                child: Text(
                                  c.name.isNotEmpty ? c.name[0].toUpperCase() : 'P',
                                  style: const TextStyle(color: AppTheme.primaryGreen, fontWeight: FontWeight.bold),
                                ),
                              ),
                              title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${c.phone.isEmpty ? "Tanpa No. HP" : c.phone}${c.address.isNotEmpty && c.address != "-" ? " • ${c.address}" : ""}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  if (debtBal > 0)
                                    Text(
                                      'Kasbon Aktif: ${CurrencyHelper.format(debtBal)}',
                                      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppTheme.accentRed),
                                    ),
                                ],
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.edit_outlined, size: 20),
                                onPressed: () => _openCustomerDialog(customer: c),
                              ),
                              onTap: () => _openCustomerHistory(c),
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
        onPressed: () => _openCustomerDialog(),
        icon: const Icon(Icons.person_add_rounded),
        label: const Text('Tambah Pelanggan'),
      ),
    );
  }
}
