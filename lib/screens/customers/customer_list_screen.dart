import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/customer.dart';
import '../../providers/customer_provider.dart';
import '../../utils/app_theme.dart';

class CustomerListScreen extends StatefulWidget {
  const CustomerListScreen({super.key});

  @override
  State<CustomerListScreen> createState() => _CustomerListScreenState();
}

class _CustomerListScreenState extends State<CustomerListScreen> {
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<CustomerProvider>(context, listen: false).loadCustomers();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
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
                          prov.loadCustomers(query: '');
                        },
                      )
                    : null,
              ),
              onChanged: (v) => prov.loadCustomers(query: v),
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
                              subtitle: Text(
                                '${c.phone.isEmpty ? "Tanpa No. HP" : c.phone}${c.address.isNotEmpty && c.address != "-" ? " • ${c.address}" : ""}',
                                style: const TextStyle(fontSize: 12),
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.edit_outlined, size: 20),
                                onPressed: () => _openCustomerDialog(customer: c),
                              ),
                              onTap: () => _openCustomerDialog(customer: c),
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
