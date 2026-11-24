import 'package:intl/intl.dart';

class DateHelper {
  static String formatShort(DateTime date) {
    return DateFormat('dd/MM/yyyy').format(date);
  }

  static String formatFull(DateTime date) {
    return DateFormat('dd MMM yyyy, HH:mm:ss').format(date);
  }

  static String formatReadable(DateTime date) {
    return DateFormat('EEEE, dd MMMM yyyy', 'id_ID').format(date);
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
}
