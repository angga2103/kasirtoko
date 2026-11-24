import 'package:flutter_test/flutter_test.dart';
import 'package:kasirtoko/utils/currency_format.dart';
import 'package:kasirtoko/utils/date_format.dart';
import 'package:kasirtoko/services/image_watermark_service.dart';

void main() {
  test('CurrencyHelper formats Indonesian Rupiah correctly', () {
    expect(CurrencyHelper.format(15000), 'Rp 15.000');
    expect(CurrencyHelper.format(1500000), 'Rp 1.500.000');
    expect(CurrencyHelper.formatCompact(1500000), 'Rp 1.5 jt');
  });

  test('ImageWatermarkService generates valid verification hash', () {
    final now = DateTime(2026, 11, 24, 8, 30, 0);
    final hash = ImageWatermarkService.generateValidationHash(1, now, '742');
    expect(hash.startsWith('#AUTH-'), isTrue);
    expect(hash.endsWith('-742'), isTrue);
  });

  test('DateHelper calculates days difference accurately', () {
    final now = DateTime.now();
    final future = now.add(const Duration(days: 10));
    expect(DateHelper.daysDifference(future), 10);
  });
}
