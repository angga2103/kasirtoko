import 'package:intl/intl.dart';

class CurrencyHelper {
  static String _currencySymbol = 'Rp ';

  static String get currencySymbol => _currencySymbol;

  static void setCurrencySymbol(String symbol) {
    _currencySymbol = symbol.isEmpty ? 'Rp ' : (symbol.endsWith(' ') ? symbol : '$symbol ');
  }

  static String format(num amount, {String? symbol}) {
    final s = symbol ?? _currencySymbol;
    final formatter = NumberFormat.currency(
      locale: 'id_ID',
      symbol: s,
      decimalDigits: 0,
    );
    return formatter.format(amount);
  }

  static String formatCompact(num amount, {String? symbol}) {
    final s = symbol ?? _currencySymbol;
    final abs = amount.abs();
    final sign = amount < 0 ? '-' : '';
    if (abs >= 1000000000) {
      return '$sign$s${(abs / 1000000000).toStringAsFixed(1)} M';
    } else if (abs >= 1000000) {
      return '$sign$s${(abs / 1000000).toStringAsFixed(1)} jt';
    } else if (abs >= 1000) {
      return '$sign$s${(abs / 1000).toStringAsFixed(0)} rb';
    }
    return format(amount, symbol: s);
  }

  static double parse(String text) {
    final cleaned = text.replaceAll(RegExp(r'[^0-9]'), '');
    return double.tryParse(cleaned) ?? 0.0;
  }
}
