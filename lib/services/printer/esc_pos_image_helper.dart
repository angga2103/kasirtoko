import 'dart:io';
import 'dart:typed_data';
import 'package:image/image.dart' as img;

/// Converts store logo files cleanly for both ESC/POS monochrome thermal raster printing (GS v 0)
/// and normalized PDF embedding with white-matte alpha flattening.
class EscPosImageHelper {
  /// Loads an image file, composites transparent pixels over pure white, resizes
  /// proportionally to [maxWidth], and returns clean PNG bytes for PDF/print rendering.
  static Uint8List? loadNormalizedPngBytes(String? path, {int maxWidth = 320}) {
    if (path == null || path.isEmpty) return null;
    try {
      final file = File(path);
      if (!file.existsSync()) return null;
      final rawBytes = file.readAsBytesSync();
      final decoded = img.decodeImage(rawBytes);
      if (decoded == null) return null;

      img.Image working = decoded;
      if (working.width > maxWidth) {
        working = img.copyResize(
          working,
          width: maxWidth,
          interpolation: img.Interpolation.average,
        );
      }

      // Composite onto opaque white canvas so transparent PNG logos never turn solid black
      final flattened = img.Image(width: working.width, height: working.height);
      img.fill(flattened, color: img.ColorRgb8(255, 255, 255));
      img.compositeImage(flattened, working);

      return Uint8List.fromList(img.encodePng(flattened));
    } catch (_) {
      return null;
    }
  }

  /// Generates ESC/POS `GS v 0` monochrome raster bitmap bytes for 58mm (<=240px logo)
  /// or 80mm (<=340px logo) thermal printers. Returns empty list if file cannot be decoded.
  static List<int> encodeEscPosRasterLogo(
    String? path, {
    int maxWidthDots = 220,
    int maxHeightDots = 120,
  }) {
    if (path == null || path.isEmpty) return [];
    try {
      final file = File(path);
      if (!file.existsSync()) return [];
      final decoded = img.decodeImage(file.readAsBytesSync());
      if (decoded == null) return [];

      // Keep aspect ratio and bound height & width cleanly
      double scale = maxWidthDots / decoded.width;
      if (decoded.width <= maxWidthDots) scale = 1.0;
      int targetW = (decoded.width * scale).round();
      int targetH = (decoded.height * scale).round();
      if (targetH > maxHeightDots) {
        final hScale = maxHeightDots / decoded.height;
        targetW = (decoded.width * hScale).round();
        targetH = maxHeightDots;
      }
      targetW = targetW.clamp(16, maxWidthDots);
      targetH = targetH.clamp(16, maxHeightDots);

      final resized = img.copyResize(
        decoded,
        width: targetW,
        height: targetH,
        interpolation: img.Interpolation.average,
      );

      final flattened = img.Image(width: resized.width, height: resized.height);
      img.fill(flattened, color: img.ColorRgb8(255, 255, 255));
      img.compositeImage(flattened, resized);

      final width = flattened.width;
      final height = flattened.height;
      final byteWidth = (width + 7) ~/ 8;

      final raster = <int>[
        0x1D, 0x76, 0x30, 0x00, // GS v 0 m=0 (normal)
        byteWidth & 0xFF,
        (byteWidth >> 8) & 0xFF,
        height & 0xFF,
        (height >> 8) & 0xFF,
      ];

      for (int y = 0; y < height; y++) {
        for (int xByte = 0; xByte < byteWidth; xByte++) {
          int slice = 0;
          for (int bit = 0; bit < 8; bit++) {
            final x = xByte * 8 + bit;
            if (x < width) {
              final pixel = flattened.getPixel(x, y);
              final luma = (0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b);
              if (luma < 145) {
                slice |= (1 << (7 - bit));
              }
            }
          }
          raster.add(slice);
        }
      }

      return raster;
    } catch (_) {
      return [];
    }
  }
}
