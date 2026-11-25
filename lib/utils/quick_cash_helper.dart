/// Generates practical Indonesian Rupiah quick-cash payment suggestions based on cart total.
class QuickCashHelper {
  static double _roundUpToStep(double amount, double step) {
    if (amount <= 0) return step;
    final rem = amount % step;
    if (rem < 0.0001) return amount;
    return amount - rem + step;
  }

  /// Returns ascending recommended quick-cash amounts (e.g.:
  /// 25,000 -> [25,000, 50,000, 100,000]
  /// 49,000 -> [50,000, 100,000, 150,000]
  /// 199,000 -> [200,000, 250,000, 300,000]
  /// 375,000 -> [400,000, 500,000, 600,000])
  static List<double> suggestNominals(double grandTotal) {
    if (grandTotal <= 0) {
      return [10000, 20000, 50000];
    }

    final total = grandTotal.ceilToDouble();

    // Determine sensible first rounded-up nominal
    double first;
    if (total <= 25000) {
      first = _roundUpToStep(total, 5000);
    } else if (total <= 250000) {
      first = _roundUpToStep(total, 10000);
    } else if (total <= 1000000) {
      first = _roundUpToStep(total, 50000);
    } else {
      first = _roundUpToStep(total, 100000);
    }

    final results = <double>[first];

    if (first <= 10000) {
      results.addAll([20000, 50000]);
    } else if (first <= 20000) {
      results.addAll([50000, 100000]);
    } else if (first == 25000) {
      results.addAll([50000, 100000]);
    } else if (first <= 200000) {
      final second = (first % 50000 == 0)
          ? first + 50000
          : _roundUpToStep(first, 50000);
      final third = second + 50000;
      results.addAll([second, third]);
    } else if (first <= 1000000) {
      final second = (first % 100000 == 0)
          ? first + 100000
          : _roundUpToStep(first, 100000);
      final third = second + 100000;
      results.addAll([second, third]);
    } else {
      final second = (first % 500000 == 0)
          ? first + 500000
          : _roundUpToStep(first, 200000);
      final third = second + 200000;
      results.addAll([second, third]);
    }

    return results.toSet().toList()..sort();
  }
}
