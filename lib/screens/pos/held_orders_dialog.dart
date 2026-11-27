import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/pos_provider.dart';
import '../../utils/app_theme.dart';
import '../../utils/currency_format.dart';
import '../../utils/date_format.dart';

class HeldOrdersDialog extends StatelessWidget {
  const HeldOrdersDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final pos = Provider.of<PosProvider>(context);

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Expanded(child: Text('Pesanan Ditahan')),
          const SizedBox(width: 8),
          Text(
            '${pos.heldOrders.length} Antrean',
            style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
          ),
        ],
      ),
      content: SizedBox(
        width: AppBreakpoints.boundedDialogWidth(context, maxWidth: 420),
        height: (MediaQuery.sizeOf(context).height * 0.55).clamp(180.0, 350.0),
        child: pos.heldOrders.isEmpty
            ? const Center(
                child: Text('Tidak ada pesanan yang sedang ditahan.'),
              )
            : ListView.separated(
                itemCount: pos.heldOrders.length,
                separatorBuilder: (_, __) => const Divider(),
                itemBuilder: (context, index) {
                  final order = pos.heldOrders[index];
                  final total = order.items.fold(0.0, (sum, i) => sum + i.subtotal) - order.discountTotal;

                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      order.customerName,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    subtitle: Text(
                      '${order.items.length} Barang • ${DateHelper.formatTime(order.timestamp)}\nTotal: ${CurrencyHelper.format(total)}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: AppTheme.accentRed, size: 20),
                          onPressed: () => pos.removeHeldOrder(order.id),
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                          onPressed: () {
                            pos.resumeHeldOrder(order);
                            Navigator.pop(context);
                          },
                          child: const Text('Buka'),
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Tutup'),
        ),
      ],
    );
  }
}
