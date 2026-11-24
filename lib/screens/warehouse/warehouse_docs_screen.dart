import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/warehouse_doc.dart';
import '../../providers/settings_provider.dart';
import '../../database/db_helper.dart';
import '../../services/document_service.dart';
import '../../utils/app_theme.dart';
import '../../utils/date_format.dart';

class WarehouseDocsScreen extends StatefulWidget {
  const WarehouseDocsScreen({super.key});

  @override
  State<WarehouseDocsScreen> createState() => _WarehouseDocsScreenState();
}

class _WarehouseDocsScreenState extends State<WarehouseDocsScreen> {
  List<WarehouseDocModel> _docs = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDocs();
  }

  Future<void> _loadDocs() async {
    final list = await DatabaseHelper.instance.getWarehouseDocs();
    setState(() {
      _docs = list;
      _isLoading = false;
    });
  }

  void _showCreateDocDialog() {
    String docType = 'surat_jalan';
    final noCtrl = TextEditingController(
      text: 'SJ-${DateTime.now().year}${DateTime.now().month.toString().padLeft(2, '0')}-${Random().nextInt(9000) + 1000}',
    );
    final recipientCtrl = TextEditingController();
    final addressCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final driverCtrl = TextEditingController();
    final vehicleCtrl = TextEditingController();
    final noteCtrl = TextEditingController();

    // Items list for document
    List<Map<String, dynamic>> items = [
      {'name': 'Minyak Goreng Sania 2L', 'qty': 10, 'unit': 'Dus', 'note': 'Kemasan karton'},
    ];

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Buat Dokumen Gudang / Jalan'),
              content: SizedBox(
                width: 480,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Doc Type Selector
                      Row(
                        children: [
                          Expanded(
                            child: ChoiceChip(
                              label: const Text('Surat Jalan (Kirim)'),
                              selected: docType == 'surat_jalan',
                              selectedColor: AppTheme.primaryGreenLight,
                              onSelected: (val) {
                                if (val) {
                                  setDialogState(() {
                                    docType = 'surat_jalan';
                                    noCtrl.text = 'SJ-${DateTime.now().year}${DateTime.now().month.toString().padLeft(2, '0')}-${Random().nextInt(9000) + 1000}';
                                  });
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ChoiceChip(
                              label: const Text('Surat Ambil Gudang'),
                              selected: docType == 'surat_ambil_barang',
                              selectedColor: AppTheme.primaryGreenLight,
                              onSelected: (val) {
                                if (val) {
                                  setDialogState(() {
                                    docType = 'surat_ambil_barang';
                                    noCtrl.text = 'SAB-${DateTime.now().year}${DateTime.now().month.toString().padLeft(2, '0')}-${Random().nextInt(9000) + 1000}';
                                  });
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      TextField(
                        controller: noCtrl,
                        decoration: const InputDecoration(labelText: 'Nomor Dokumen'),
                      ),
                      const SizedBox(height: 8),

                      TextField(
                        controller: recipientCtrl,
                        decoration: InputDecoration(
                          labelText: docType == 'surat_jalan' ? 'Nama Penerima / Toko Tujuan *' : 'Nama Pengambil Barang *',
                        ),
                      ),
                      const SizedBox(height: 8),

                      if (docType == 'surat_jalan') ...[
                        TextField(
                          controller: addressCtrl,
                          decoration: const InputDecoration(labelText: 'Alamat Tujuan Pengiriman'),
                        ),
                        const SizedBox(height: 8),
                      ],

                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: driverCtrl,
                              decoration: const InputDecoration(labelText: 'Nama Supir / Pengambil'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: vehicleCtrl,
                              decoration: const InputDecoration(labelText: 'No. Polisi Kendaraan'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Items list in dialog
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Daftar Barang:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          TextButton.icon(
                            icon: const Icon(Icons.add, size: 16),
                            label: const Text('Tambah Baris'),
                            onPressed: () {
                              setDialogState(() {
                                items.add({'name': '', 'qty': 1, 'unit': 'Pcs', 'note': ''});
                              });
                            },
                          ),
                        ],
                      ),

                      ...items.asMap().entries.map((entry) {
                        final idx = entry.key;
                        final item = entry.value;

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: TextFormField(
                                  initialValue: item['name'],
                                  decoration: const InputDecoration(hintText: 'Nama Barang', isDense: true),
                                  onChanged: (val) => item['name'] = val,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                flex: 1,
                                child: TextFormField(
                                  initialValue: item['qty'].toString(),
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(hintText: 'Qty', isDense: true),
                                  onChanged: (val) => item['qty'] = double.tryParse(val) ?? 1,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                flex: 2,
                                child: TextFormField(
                                  initialValue: item['unit'],
                                  decoration: const InputDecoration(hintText: 'Satuan', isDense: true),
                                  onChanged: (val) => item['unit'] = val,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.remove_circle_outline, color: Colors.red, size: 20),
                                onPressed: () {
                                  if (items.length > 1) {
                                    setDialogState(() => items.removeAt(idx));
                                  }
                                },
                              ),
                            ],
                          ),
                        );
                      }),

                      const SizedBox(height: 8),
                      TextField(
                        controller: noteCtrl,
                        decoration: const InputDecoration(labelText: 'Catatan Dokumen (Opsional)'),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
                ElevatedButton(
                  onPressed: () async {
                    if (recipientCtrl.text.isEmpty) return;

                    final doc = WarehouseDocModel(
                      docNumber: noCtrl.text.trim(),
                      docType: docType,
                      date: DateTime.now(),
                      recipientName: recipientCtrl.text.trim(),
                      recipientAddress: addressCtrl.text.trim(),
                      recipientPhone: phoneCtrl.text.trim(),
                      driverOrPickerName: driverCtrl.text.trim(),
                      vehicleNumber: vehicleCtrl.text.trim(),
                      note: noteCtrl.text.trim(),
                      status: 'selesai',
                      itemsJson: jsonEncode(items),
                    );

                    await DatabaseHelper.instance.insertWarehouseDoc(doc);
                    await _loadDocs();

                    if (!mounted) return;
                    Navigator.pop(ctx);

                    // Prompt to print immediately
                    final settings = Provider.of<SettingsProvider>(context, listen: false);
                    await DocumentService.printWarehouseDoc(
                      docModel: doc,
                      storeName: settings.storeName,
                      storeAddress: settings.storeAddress,
                      storePhone: settings.storePhone,
                    );
                  },
                  child: const Text('Simpan & Cetak PDF'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Surat Jalan & Pengambilan Gudang'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _docs.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.local_shipping_outlined, size: 54, color: AppTheme.textMuted),
                      const SizedBox(height: 12),
                      const Text('Belum ada dokumen surat jalan / ambil gudang.'),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.add),
                        label: const Text('Buat Surat Baru'),
                        onPressed: _showCreateDocDialog,
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: _docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final d = _docs[index];
                    final isSuratJalan = d.docType == 'surat_jalan';

                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isSuratJalan ? Colors.deepPurple.shade100 : Colors.teal.shade100,
                          child: Icon(
                            isSuratJalan ? Icons.local_shipping_rounded : Icons.warehouse_rounded,
                            color: isSuratJalan ? Colors.deepPurple : Colors.teal,
                          ),
                        ),
                        title: Text(
                          '${d.docTitle} - ${d.docNumber}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        subtitle: Text(
                          'Tujuan: ${d.recipientName} • Tgl: ${DateHelper.formatShort(d.date)}\nSupir: ${d.driverOrPickerName.isNotEmpty ? d.driverOrPickerName : "-"} (${d.vehicleNumber.isNotEmpty ? d.vehicleNumber : "-"})',
                          style: const TextStyle(fontSize: 11),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.print_rounded, color: AppTheme.primaryGreen),
                          tooltip: 'Cetak Dokumen PDF',
                          onPressed: () async {
                            await DocumentService.printWarehouseDoc(
                              docModel: d,
                              storeName: settings.storeName,
                              storeAddress: settings.storeAddress,
                              storePhone: settings.storePhone,
                            );
                          },
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppTheme.primaryGreen,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Buat Dokumen', style: TextStyle(color: Colors.white)),
        onPressed: _showCreateDocDialog,
      ),
    );
  }
}
