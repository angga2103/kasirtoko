import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../database/db_helper.dart';
import '../../models/product.dart';
import '../../models/stock_opname.dart';
import '../../providers/auth_provider.dart';
import '../../providers/product_provider.dart';
import '../../utils/app_theme.dart';
import '../../utils/date_format.dart';
import '../../widgets/quantity_stepper.dart';
import '../scanner/barcode_scanner_screen.dart';

class _OpnameQueueEntry {
  final ProductModel product;
  double physicalQty;

  _OpnameQueueEntry({
    required this.product,
    required this.physicalQty,
  });
}

class StockOpnameScreen extends StatefulWidget {
  const StockOpnameScreen({super.key});

  @override
  State<StockOpnameScreen> createState() => _StockOpnameScreenState();
}

class _StockOpnameScreenState extends State<StockOpnameScreen> {
  final TextEditingController _barcodeSearchCtrl = TextEditingController();
  final TextEditingController _batchNoteCtrl = TextEditingController();
  final List<_OpnameQueueEntry> _queue = [];
  List<StockOpnameModel> _opnameHistory = [];
  bool _isLoading = true;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<ProductProvider>(context, listen: false).loadProducts();
      _loadHistory();
    });
  }

  @override
  void dispose() {
    _barcodeSearchCtrl.dispose();
    _batchNoteCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final list = await DatabaseHelper.instance.getStockOpnames();
    if (!mounted) return;
    setState(() {
      _opnameHistory = list;
      _isLoading = false;
    });
  }

  Future<ContinuousScanEventResult> _handleBarcodeScanned(String code, {bool fromScanner = true}) async {
    final clean = code.trim();
    if (clean.isEmpty) {
      return ContinuousScanEventResult(found: false, title: 'Kode kosong');
    }

    final prodProv = Provider.of<ProductProvider>(context, listen: false);
    final match = await prodProv.findProductByBarcode(clean);
    if (match == null) {
      if (!fromScanner && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Produk dengan barcode "$clean" tidak ditemukan.'), backgroundColor: AppTheme.accentRed),
        );
      }
      return ContinuousScanEventResult(
        found: false,
        title: 'Tidak Ditemukan',
        subtitle: 'Barcode $clean tidak terdaftar',
      );
    }

    final p = match.product;
    if (p.isService) {
      if (!fromScanner && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Produk Jasa tidak memerlukan stok opname fisik.')),
        );
      }
      return ContinuousScanEventResult(
        found: false,
        title: p.name,
        subtitle: 'Produk Jasa (non-fisik)',
      );
    }

    final factor = match.matchedUnit?.conversionFactor ?? 1.0;
    final idx = _queue.indexWhere((e) => e.product.id == p.id);

    if (mounted) {
      setState(() {
        if (idx != -1) {
          _queue[idx].physicalQty += factor;
        } else {
          _queue.insert(0, _OpnameQueueEntry(product: p, physicalQty: factor));
        }
      });
    }

    final newQty = idx != -1 ? _queue[0 == idx ? 0 : idx].physicalQty : factor;
    final subMsg = idx != -1
        ? 'Duplikat dicegah -> Fisik diperbarui: ${_fmtQty(newQty)} ${p.baseUnit}'
        : 'Stok Sistem: ${_fmtQty(p.stock)} ${p.baseUnit} • Fisik: ${_fmtQty(newQty)}';

    if (!fromScanner && mounted && idx != -1) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${p.name} sudah ada di antrean (stok fisik +${_fmtQty(factor)}).'),
          duration: const Duration(milliseconds: 1400),
        ),
      );
    }

    return ContinuousScanEventResult(found: true, title: p.name, subtitle: subMsg);
  }

  void _addProductManually(ProductModel p) {
    final existingIdx = _queue.indexWhere((e) => e.product.id == p.id);
    if (existingIdx != -1) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${p.name} sudah ada di daftar opname (silakan edit jumlah pada daftar).')),
      );
      return;
    }
    setState(() {
      _queue.insert(0, _OpnameQueueEntry(product: p, physicalQty: p.stock));
    });
  }

  Future<void> _openContinuousScanner() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BarcodeScannerScreen(
          title: 'Scan Stok Opname Berkelanjutan',
          helperText: 'Scan beberapa produk berurutan. Setiap produk otomatis antre tanpa duplikasi.',
          continuousMode: true,
          onBarcodeScanned: (code) => _handleBarcodeScanned(code, fromScanner: true),
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _submitAllOpname() async {
    if (_queue.isEmpty || _submitting) return;
    setState(() => _submitting = true);

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final prodProv = Provider.of<ProductProvider>(context, listen: false);
    final auditor = auth.currentUser?.name ?? 'Petugas Gudang';
    final now = DateTime.now();
    final batchNote = _batchNoteCtrl.text.trim();

    final list = _queue
        .map((e) => StockOpnameModel(
              date: now,
              productId: e.product.id!,
              productCode: e.product.code,
              productName: e.product.name,
              systemStock: e.product.stock,
              physicalStock: e.physicalQty,
              difference: e.physicalQty - e.product.stock,
              note: batchNote,
              auditedBy: auditor,
            ))
        .toList();

    try {
      await DatabaseHelper.instance.insertStockOpnamesBatch(list);
      await auth.logAction(
        'stok_opname',
        'Batch Stok Opname ${list.length} produk oleh $auditor (${list.map((o) => "${o.productName}: ${o.systemStock.toInt()}->${o.physicalStock.toInt()}").take(3).join(", ")})',
        module: 'stok_opname',
      );
      await prodProv.loadProducts();
      await _loadHistory();

      if (!mounted) return;
      final savedCount = list.length;
      setState(() {
        _submitting = false;
        _queue.clear();
        _batchNoteCtrl.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$savedCount produk berhasil disesuaikan stoknya.'),
          backgroundColor: AppTheme.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Bad state: ', '')),
          backgroundColor: AppTheme.accentRed,
        ),
      );
    }
  }

  String _fmtQty(double q) => q == q.truncateToDouble() ? q.toInt().toString() : q.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final productProv = Provider.of<ProductProvider>(context);
    final physicalProducts = productProv.allProducts.where((p) => !p.isService).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Stok Opname (Scan & Audit)'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 920),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Scanner & Manual Input Card
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: AppTheme.cardDecoration(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Tambah Produk ke Daftar Audit Opname',
                        style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 10),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final searchInput = TextField(
                            controller: _barcodeSearchCtrl,
                            decoration: const InputDecoration(
                              hintText: 'Ketik / scan barcode alat USB...',
                              hintStyle: TextStyle(fontSize: 12),
                              prefixIcon: Icon(Icons.qr_code_rounded, size: 20),
                            ),
                            onSubmitted: (v) async {
                              await _handleBarcodeScanned(v, fromScanner: false);
                              _barcodeSearchCtrl.clear();
                            },
                          );
                          final scanButton = ElevatedButton.icon(
                            onPressed: _openContinuousScanner,
                            icon: const Icon(Icons.qr_code_scanner_rounded, size: 19),
                            label: const Text('Scan Kamera'),
                          );
                          if (constraints.maxWidth < 430) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                searchInput,
                                const SizedBox(height: 8),
                                scanButton,
                              ],
                            );
                          }
                          return Row(
                            children: [
                              Expanded(child: searchInput),
                              const SizedBox(width: 8),
                              scanButton,
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<int?>(
                        isExpanded: true,
                        value: null,
                        decoration: const InputDecoration(
                          labelText: 'Atau Pilih Produk Secara Manual',
                          prefixIcon: Icon(Icons.inventory_2_outlined, size: 20),
                        ),
                        hint: const Text('Pilih produk untuk ditambahkan ke antrean...'),
                        items: physicalProducts
                            .map((p) => DropdownMenuItem<int?>(
                                  value: p.id,
                                  child: Text(
                                    '${p.name} (${p.code}) • Stok: ${_fmtQty(p.stock)} ${p.baseUnit}',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ))
                            .toList(),
                        onChanged: (prodId) {
                          if (prodId == null) return;
                          final picked = physicalProducts.firstWhere((p) => p.id == prodId);
                          _addProductManually(picked);
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Active Queue Section
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        'Antrean Audit Opname (${_queue.length} Produk)',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (_queue.isNotEmpty)
                      TextButton(
                        onPressed: () => setState(() => _queue.clear()),
                        child: const Text('Kosongkan', style: TextStyle(color: AppTheme.accentRed, fontSize: 12)),
                      ),
                  ],
                ),
                const SizedBox(height: 6),

                if (_queue.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: AppTheme.cardDecoration(),
                    child: const Text(
                      'Belum ada produk dalam antrean opname. Gunakan tombol "Scan Kamera" atau pilih produk dari daftar.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppTheme.textMuted, fontSize: 12.5),
                    ),
                  )
                else ...[
                  ..._queue.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final row = entry.value;
                    final diff = row.physicalQty - row.product.stock;
                    final diffColor = diff == 0
                        ? Colors.grey
                        : (diff > 0 ? AppTheme.primaryGreen : AppTheme.accentRed);

                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(row.product.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                                      Text(
                                        'SKU: ${row.product.code}${row.product.barcode.isNotEmpty ? " • Barcode: ${row.product.barcode}" : ""} • Sistem: ${_fmtQty(row.product.stock)} ${row.product.baseUnit}',
                                        style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.close_rounded, size: 18, color: AppTheme.accentRed),
                                  onPressed: () => setState(() => _queue.removeAt(idx)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              alignment: WrapAlignment.spaceBetween,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text('Fisik: ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                    QuantityStepper(
                                      value: row.physicalQty,
                                      minValue: 0,
                                      allowDecimal: true,
                                      compact: true,
                                      unitLabel: row.product.baseUnit,
                                      onChanged: (v) => setState(() => row.physicalQty = v),
                                    ),
                                  ],
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: diffColor.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    'Selisih: ${diff >= 0 ? "+" : ""}${_fmtQty(diff)} ${row.product.baseUnit}',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: diffColor),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _batchNoteCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Catatan Penyesuaian Opname (cth: Barang Rusak / Selisih Hitung Rak)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _submitting ? null : _submitAllOpname,
                      icon: const Icon(Icons.check_circle_rounded),
                      label: Text(_submitting ? 'MENYIMPAN...' : 'SIMPAN SEMUA (${_queue.length} PRODUK) KE STOK AKTIF'),
                    ),
                  ),
                ],

                const SizedBox(height: 24),
                const Text(
                  'Riwayat Penyesuaian Opname Terbaru',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                const SizedBox(height: 8),

                if (_isLoading)
                  const Center(child: CircularProgressIndicator())
                else if (_opnameHistory.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(child: Text('Belum ada catatan opname.', style: TextStyle(color: AppTheme.textMuted))),
                  )
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _opnameHistory.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final op = _opnameHistory[index];
                      final color = op.difference > 0
                          ? AppTheme.primaryGreen
                          : (op.difference < 0 ? AppTheme.accentRed : Colors.grey);

                      return Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: color.withValues(alpha: 0.12),
                            child: Text(
                              '${op.difference >= 0 ? "+" : ""}${_fmtQty(op.difference)}',
                              style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 11.5),
                            ),
                          ),
                          title: Text(op.productName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          subtitle: Text(
                            'Sistem: ${_fmtQty(op.systemStock)} -> Fisik: ${_fmtQty(op.physicalStock)}\n'
                            '${DateHelper.formatFull(op.date)} • ${op.auditedBy}${op.note.isNotEmpty ? " • ${op.note}" : ""}',
                            style: const TextStyle(fontSize: 11),
                          ),
                          isThreeLine: true,
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
