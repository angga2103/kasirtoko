import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../utils/date_format.dart';

class WatermarkResult {
  final String savedPath;
  final String validationHash;
  final bool isLate;
  final int lateMinutes;

  WatermarkResult({
    required this.savedPath,
    required this.validationHash,
    required this.isLate,
    required this.lateMinutes,
  });
}

class ImageWatermarkService {
  // Generate cryptographic short hash for attendance anti-tamper
  static String generateValidationHash(int employeeId, DateTime time, String token) {
    final raw = 'KASIRTOKO|$employeeId|${time.millisecondsSinceEpoch}|$token';
    final digest = sha256.convert(utf8.encode(raw));
    final shortHash = digest.toString().substring(0, 4).toUpperCase();
    return '#AUTH-$shortHash-$token';
  }

  // Calculate late minutes compared to standard shift start (e.g. 08:00)
  static Map<String, dynamic> checkLateness(DateTime now, String shiftStartStr) {
    try {
      final parts = shiftStartStr.split(':');
      final startHour = int.parse(parts[0]);
      final startMin = int.parse(parts[1]);

      final scheduledTime = DateTime(now.year, now.month, now.day, startHour, startMin);
      if (now.isAfter(scheduledTime)) {
        final diff = now.difference(scheduledTime).inMinutes;
        return {'isLate': true, 'lateMinutes': diff};
      }
    } catch (_) {}
    return {'isLate': false, 'lateMinutes': 0};
  }

  // Stamp watermark onto image file
  static Future<WatermarkResult> stampWatermark({
    required String sourceImagePath,
    required int employeeId,
    required String employeeName,
    required String attendanceType,
    required String challengeToken,
    required String shiftStartHour,
  }) async {
    final now = DateTime.now();
    final lateness = checkLateness(now, shiftStartHour);
    final bool isLate = lateness['isLate'] && attendanceType == 'masuk';
    final int lateMinutes = lateness['lateMinutes'];

    final validationHash = generateValidationHash(employeeId, now, challengeToken);

    // Read image bytes
    final bytes = await File(sourceImagePath).readAsBytes();
    img.Image? originalImage = img.decodeImage(bytes);

    if (originalImage == null) {
      // Fallback if decode fails
      return WatermarkResult(
        savedPath: sourceImagePath,
        validationHash: validationHash,
        isLate: isLate,
        lateMinutes: lateMinutes,
      );
    }

    // Resize if too huge to keep app lightweight
    if (originalImage.width > 1200) {
      originalImage = img.copyResize(originalImage, width: 1200);
    }

    final width = originalImage.width;
    final height = originalImage.height;

    // Draw dark semi-transparent banner at the bottom for watermark text
    final bannerHeight = (height * 0.22).toInt();
    final bannerY = height - bannerHeight;

    img.fillRect(
      originalImage,
      x1: 0,
      y1: bannerY,
      x2: width,
      y2: height,
      color: img.ColorRgba8(15, 23, 42, 220), // Dark Navy #0F172A
    );

    // Prepare text lines
    final timeStr = '${DateHelper.formatFull(now)} WIB';
    final statusStr = isLate
        ? 'TERLAMBAT ($lateMinutes Menit)'
        : 'TEPAT WAKTU';
    final typeStr = attendanceType == 'masuk' ? 'ABSENSI MASUK' : 'ABSENSI PULANG';

    // Draw text lines
    final textColor = img.ColorRgba8(255, 255, 255, 255);
    final highlightColor = isLate
        ? img.ColorRgba8(239, 68, 68, 255) // Red
        : img.ColorRgba8(16, 185, 129, 255); // Emerald Green
    final hashColor = img.ColorRgba8(245, 158, 11, 255); // Amber

    final startX = (width * 0.05).toInt();
    var currentY = bannerY + 20;

    img.drawString(
      originalImage,
      '[$typeStr] $employeeName',
      font: img.arial24,
      x: startX,
      y: currentY,
      color: textColor,
    );

    currentY += 35;
    img.drawString(
      originalImage,
      'WAKTU: $timeStr',
      font: img.arial14,
      x: startX,
      y: currentY,
      color: textColor,
    );

    currentY += 25;
    img.drawString(
      originalImage,
      'STATUS: $statusStr',
      font: img.arial24,
      x: startX,
      y: currentY,
      color: highlightColor,
    );

    currentY += 35;
    img.drawString(
      originalImage,
      'KODE VERIFIKASI: $validationHash',
      font: img.arial14,
      x: startX,
      y: currentY,
      color: hashColor,
    );

    // Save watermarked image to app storage
    final appDir = await getApplicationDocumentsDirectory();
    final fileName = 'att_${employeeId}_${now.millisecondsSinceEpoch}.jpg';
    final targetPath = p.join(appDir.path, fileName);

    final encodedJpg = img.encodeJpg(originalImage, quality: 85);
    await File(targetPath).writeAsBytes(encodedJpg);

    return WatermarkResult(
      savedPath: targetPath,
      validationHash: validationHash,
      isLate: isLate,
      lateMinutes: lateMinutes,
    );
  }
}
