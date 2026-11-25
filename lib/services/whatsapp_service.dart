import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/attendance.dart';
import '../models/customer_debt.dart';
import '../models/service_order.dart';
import '../models/shift.dart';
import '../utils/currency_format.dart';
import '../utils/date_format.dart';

class WhatsAppService {
  static String normalizePhone(String phone) {
    String cleaned = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleaned.startsWith('0')) {
      cleaned = '62${cleaned.substring(1)}';
    } else if (cleaned.startsWith('+62')) {
      cleaned = cleaned.substring(1);
    }
    return cleaned;
  }

  static Future<bool> sendDebtReminder({
    required CustomerDebtModel debt,
    required String storeName,
    required String storePhone,
  }) async {
    final phone = normalizePhone(debt.customerPhone);
    if (phone.isEmpty) return false;

    final dueDateStr = DateHelper.formatShort(debt.dueDate);
    final remainingStr = CurrencyHelper.format(debt.remainingDebt);
    final totalStr = CurrencyHelper.format(debt.totalDebt);

    final message = '''
Halo Yth. *${debt.customerName}*,

Pemberitahuan dari *$storeName*:
Catatan kasbon belanja Anda dengan No. Nota *${debt.invoiceNumber}*:
- Total Belanja: $totalStr
- Sisa Tagihan : *$remainingStr*
- Jatuh Tempo  : *$dueDateStr*

Mohon untuk melakukan pelunasan sebelum atau pada tanggal jatuh tempo. Terima kasih banyak atas kepercayaan Anda berbelanja di *$storeName*.

Hubungi kami: $storePhone
''';

    final uri = Uri.parse('https://wa.me/$phone?text=${Uri.encodeComponent(message)}');
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  static Future<bool> sendServiceUpdateToCustomer({
    required ServiceOrderModel order,
    required String storeName,
    required String storePhone,
  }) async {
    final phone = normalizePhone(order.customerPhone);
    if (phone.isEmpty) return false;

    final message = '''
Halo *${order.customerName}*, update status servis dari *$storeName*:

No. Tiket : *${order.ticketNumber}*
Perangkat : ${order.deviceType} ${order.brand} ${order.model}
Status    : *${ServiceStatus.label(order.status)}*
Total Biaya : ${CurrencyHelper.format(order.totalCost > 0 ? order.totalCost : order.estimatedCost)}
Sudah Bayar : ${CurrencyHelper.format(order.paidAmount)}
Sisa Bayar  : *${CurrencyHelper.format(order.remainingPayment)}*

Silakan hubungi kami di $storePhone jika ada pertanyaan. Terima kasih!
''';

    final uri = Uri.parse('https://wa.me/$phone?text=${Uri.encodeComponent(message)}');
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  static Future<bool> sendShiftReportToAdmin({
    required ShiftModel shift,
    required String ownerPhone,
    required String storeName,
    required int totalTransactions,
    required double totalGrossProfit,
  }) async {
    final phone = normalizePhone(ownerPhone);
    final shiftStart = DateHelper.formatReceipt(shift.startTime);
    final shiftEnd = shift.endTime != null ? DateHelper.formatReceipt(shift.endTime!) : '-';

    final diffStr = (shift.difference ?? 0.0) == 0.0
        ? 'SESUAI (Rp 0)'
        : (shift.difference! > 0
            ? 'LEBIH (+${CurrencyHelper.format(shift.difference!)})'
            : 'KURANG (${CurrencyHelper.format(shift.difference!)})');

    final message = '''
*LAPORAN TUTUP SHIFT KASIR*
Toko: *$storeName*
Kasir: *${shift.cashierName}*
Waktu: $shiftStart s/d $shiftEnd
----------------------------------
- Total Transaksi : $totalTransactions Nota
- Modal Awal      : ${CurrencyHelper.format(shift.startingCash)}
- Penjualan Tunai : ${CurrencyHelper.format(shift.totalSalesCash)}
- Penjualan QRIS  : ${CurrencyHelper.format(shift.totalSalesQris)}
- Penj. Transfer  : ${CurrencyHelper.format(shift.totalSalesTransfer)}
- Penj. Kasbon    : ${CurrencyHelper.format(shift.totalSalesKasbon)}
- Kas Masuk Lain  : ${CurrencyHelper.format(shift.totalCashIn)}
- Pengeluaran Kas : ${CurrencyHelper.format(shift.totalCashOut)}
- Retur Tunai     : ${CurrencyHelper.format(shift.totalReturnCash)}
----------------------------------
*TOTAL KAS LACI*  : *${CurrencyHelper.format(shift.expectedCash)}*
*UANG FISIK LACI* : *${CurrencyHelper.format(shift.actualCash ?? 0.0)}*
*STATUS SELISIH*  : *$diffStr*
*ESTIMASI LABA*   : ${CurrencyHelper.format(totalGrossProfit)}
----------------------------------
Catatan Kasir: ${shift.note.isNotEmpty ? shift.note : '-'}
''';

    if (phone.isNotEmpty) {
      final uri = Uri.parse('https://wa.me/$phone?text=${Uri.encodeComponent(message)}');
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      await SharePlus.instance.share(
        ShareParams(text: message, subject: 'Laporan Tutup Shift $storeName'),
      );
      return true;
    }
  }

  static Future<bool> sendDailySummaryReport({
    required String ownerPhone,
    required String storeName,
    required String reportedBy,
    required int totalTransactions,
    required double totalSales,
    double? totalGrossProfit,
  }) async {
    final phone = normalizePhone(ownerPhone);
    final nowStr = DateHelper.formatFull(DateTime.now());
    final profitLine = totalGrossProfit != null
        ? '\n*ESTIMASI LABA*   : ${CurrencyHelper.format(totalGrossProfit)}'
        : '';

    final message = '''
*RINGKASAN LAPORAN PENJUALAN*
Toko: *$storeName*
Pelapor: *$reportedBy*
Waktu: $nowStr
----------------------------------
- Total Transaksi : $totalTransactions Nota
- Total Omzet     : *${CurrencyHelper.format(totalSales)}*$profitLine
----------------------------------
Dikirim dari Aplikasi KasirToko Universal POS.
''';

    if (phone.isNotEmpty) {
      final uri = Uri.parse('https://wa.me/$phone?text=${Uri.encodeComponent(message)}');
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      await SharePlus.instance.share(
        ShareParams(text: message, subject: 'Laporan Penjualan $storeName'),
      );
      return true;
    }
  }

  static Future<void> sendAttendanceToAdmin({
    required AttendanceModel attendance,
    required String ownerPhone,
    required String storeName,
  }) async {
    final phone = normalizePhone(ownerPhone);
    final timeStr = DateHelper.formatFull(attendance.timestamp);
    final typeStr = attendance.type == 'masuk' ? 'MASUK KERJA' : 'PULANG KERJA';
    final statusStr = attendance.isLate
        ? 'TERLAMBAT (${attendance.lateMinutes} Menit)'
        : 'TEPAT WAKTU';

    final caption = '''
*ABSENSI SELFIE KARYAWAN ($typeStr)*
Toko: *$storeName*
Nama: *${attendance.employeeName}*
Waktu: $timeStr WIB
Status: *$statusStr*
----------------------------------
*TOKEN TANTANGAN* : *${attendance.challengeCode}*
*KODE VERIFIKASI* : *${attendance.validationHash}*
Liveness Check : ${attendance.isLivenessPassed ? 'Lolos (Manusia Hidup Asli)' : 'Peringatan'}
----------------------------------
Foto selfie ber-watermark asli tersimpan di sistem kasir.
''';

    if (attendance.photoPath.isNotEmpty) {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(attendance.photoPath)],
          text: caption,
          subject: 'Absensi ${attendance.employeeName}',
        ),
      );
    } else {
      if (phone.isNotEmpty) {
        final uri = Uri.parse('https://wa.me/$phone?text=${Uri.encodeComponent(caption)}');
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        await SharePlus.instance.share(ShareParams(text: caption));
      }
    }
  }
}
