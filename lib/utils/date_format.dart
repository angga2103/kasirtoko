import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

class DateHelper {
  static bool _initialized = false;

  static Future<void> ensureInitialized() async {
    if (_initialized) return;
    try {
      await initializeDateFormatting('id_ID', null);
    } catch (_) {}
    _initialized = true;
  }

  static String formatShort(DateTime date) {
    return DateFormat('dd/MM/yyyy').format(date);
  }

  static String formatFull(DateTime date) {
    return DateFormat('dd MMM yyyy, HH:mm:ss').format(date);
  }

  static String formatReadable(DateTime date) {
    try {
      return DateFormat('EEEE, dd MMMM yyyy', 'id_ID').format(date);
    } catch (_) {
      return DateFormat('dd MMM yyyy').format(date);
    }
  }

  static String formatTime(DateTime date) {
    return DateFormat('HH:mm').format(date);
  }

  static String formatReceipt(DateTime date) {
    return DateFormat('dd-MM-yyyy HH:mm').format(date);
  }

  static int daysDifference(DateTime target) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final targetDate = DateTime(target.year, target.month, target.day);
    return targetDate.difference(today).inDays;
  }

  static String greetingByTime([DateTime? now]) {
    final hour = (now ?? DateTime.now()).hour;
    if (hour < 11) return 'Selamat Pagi';
    if (hour < 15) return 'Selamat Siang';
    if (hour < 18) return 'Selamat Sore';
    return 'Selamat Malam';
  }
}
