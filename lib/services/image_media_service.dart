import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class ImageMediaService {
  static Future<Directory> _mediaDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'media'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Picks an image file from Gallery / Device Files.
  static Future<String?> pickImageFromGallery() async {
    final picked = await FilePicker.pickFile(type: FileType.image);
    if (picked == null || picked.path == null) return null;
    return picked.path;
  }

  /// Crops a normalized rectangle (0.0..1.0) from [sourcePath], resizes to max [maxDimension],
  /// saves to persistent local app media storage, and returns the saved file path.
  static Future<String?> cropAndSaveImage({
    required String sourcePath,
    required String prefix,
    double normLeft = 0.0,
    double normTop = 0.0,
    double normWidth = 1.0,
    double normHeight = 1.0,
    int rotationQuarterTurns = 0,
    int maxDimension = 900,
    bool saveAsPng = false,
  }) async {
    final srcFile = File(sourcePath);
    if (!await srcFile.exists()) return null;

    final bytes = await srcFile.readAsBytes();
    img.Image? decoded = img.decodeImage(bytes);
    if (decoded == null) return null;

    // Apply orientation baked into EXIF first
    decoded = img.bakeOrientation(decoded);

    if (rotationQuarterTurns % 4 != 0) {
      decoded = img.copyRotate(decoded, angle: (rotationQuarterTurns % 4) * 90);
    }

    // Clamp crop bounds safely
    final x = (normLeft.clamp(0.0, 0.95) * decoded.width).round();
    final y = (normTop.clamp(0.0, 0.95) * decoded.height).round();
    final w = (normWidth.clamp(0.05, 1.0 - normLeft) * decoded.width).round().clamp(1, decoded.width - x);
    final h = (normHeight.clamp(0.05, 1.0 - normTop) * decoded.height).round().clamp(1, decoded.height - y);

    var processed = img.copyCrop(decoded, x: x, y: y, width: w, height: h);

    if (processed.width > maxDimension || processed.height > maxDimension) {
      if (processed.width >= processed.height) {
        processed = img.copyResize(processed, width: maxDimension);
      } else {
        processed = img.copyResize(processed, height: maxDimension);
      }
    }

    final dir = await _mediaDir();
    final ext = saveAsPng ? 'png' : 'jpg';
    final fileName = '${prefix}_${DateTime.now().millisecondsSinceEpoch}.$ext';
    final targetPath = p.join(dir.path, fileName);

    final encoded = saveAsPng ? img.encodePng(processed) : img.encodeJpg(processed, quality: 88);
    await File(targetPath).writeAsBytes(encoded);
    return targetPath;
  }

  static Future<void> deleteLocalMedia(String? path) async {
    if (path == null || path.isEmpty) return;
    try {
      final f = File(path);
      if (await f.exists()) {
        await f.delete();
      }
    } catch (_) {}
  }
}
