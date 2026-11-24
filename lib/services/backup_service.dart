import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../database/db_helper.dart';

class BackupResult {
  final bool success;
  final String message;
  final String? backupFilePath;

  BackupResult({
    required this.success,
    required this.message,
    this.backupFilePath,
  });
}

class BackupService {
  // 1. Create a local backup file and trigger share (to WhatsApp, Google Drive, or File Manager)
  static Future<BackupResult> createAndShareBackup() async {
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final dbPath = p.join(docDir.path, 'kasirtoko.db');

      final dbFile = File(dbPath);
      if (!await dbFile.exists()) {
        return BackupResult(success: false, message: 'Database lokal tidak ditemukan.');
      }

      // Create backup copy with timestamp
      final now = DateTime.now();
      final backupFileName =
          'KasirToko_Backup_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}.db';
      final tempDir = await getTemporaryDirectory();
      final backupPath = p.join(tempDir.path, backupFileName);

      await dbFile.copy(backupPath);

      // Trigger Share Sheet (User can choose Google Drive, WhatsApp, Telegram, or Save to Device)
      await Share.shareXFiles(
        [XFile(backupPath)],
        subject: 'Backup Database KasirToko - $backupFileName',
        text: 'File Cadangan Database KasirToko Tanggal: ${now.toLocal()}',
      );

      return BackupResult(
        success: true,
        message: 'File cadangan berhasil dibuat dan siap dibagikan.',
        backupFilePath: backupPath,
      );
    } catch (e) {
      return BackupResult(success: false, message: 'Gagal membuat backup: $e');
    }
  }

  // 2. Restore database from selected file
  static Future<BackupResult> restoreDatabase() async {
    try {
      final pickedFile = await FilePicker.pickFile(
        type: FileType.any,
      );

      if (pickedFile == null || pickedFile.path == null) {
        return BackupResult(success: false, message: 'Pemulihan dibatalkan.');
      }

      final dbFile = File(pickedFile.path!);
      if (!dbFile.path.endsWith('.db')) {
        return BackupResult(
          success: false,
          message: 'Format file tidak sesuai! Harus berformat .db',
        );
      }

      final docDir = await getApplicationDocumentsDirectory();
      final dbPath = p.join(docDir.path, 'kasirtoko.db');

      // Close current db instance before overwrite
      final db = await DatabaseHelper.instance.database;
      await db.close();

      // Overwrite database file
      await dbFile.copy(dbPath);

      return BackupResult(
        success: true,
        message: 'Database berhasil dipulihkan! Silakan restart aplikasi.',
      );
    } catch (e) {
      return BackupResult(success: false, message: 'Gagal memulihkan database: $e');
    }
  }
}
