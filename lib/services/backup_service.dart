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
  /// Create a timestamped backup file in Documents/backups and optionally trigger OS share sheet.
  static Future<BackupResult> createAndShareBackup({bool shareNow = true}) async {
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final dbPath = p.join(docDir.path, 'kasirtoko.db');

      // Flush WAL/checkpoint cleanly before copying
      final db = await DatabaseHelper.instance.database;
      try {
        await db.rawQuery('PRAGMA wal_checkpoint(FULL)');
      } catch (_) {}

      final dbFile = File(dbPath);
      if (!await dbFile.exists()) {
        return BackupResult(success: false, message: 'Database lokal tidak ditemukan.');
      }

      final now = DateTime.now();
      final backupFileName =
          'KasirToko_Backup_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}.db';

      final backupDir = Directory(p.join(docDir.path, 'backups'));
      if (!await backupDir.exists()) {
        await backupDir.create(recursive: true);
      }
      final persistentBackupPath = p.join(backupDir.path, backupFileName);
      await dbFile.copy(persistentBackupPath);

      if (shareNow) {
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(persistentBackupPath)],
            subject: 'Backup Database KasirToko - $backupFileName',
            text: 'File Cadangan Database KasirToko Tanggal: ${now.toLocal()}',
          ),
        );
      }

      return BackupResult(
        success: true,
        message: shareNow
            ? 'File cadangan berhasil dibuat dan siap dibagikan.'
            : 'Backup otomatis lokal tersimpan: $backupFileName',
        backupFilePath: persistentBackupPath,
      );
    } catch (e) {
      return BackupResult(success: false, message: 'Gagal membuat backup: $e');
    }
  }

  /// Restore database from a picked .db file and safely reset SQLite singleton connection.
  static Future<BackupResult> restoreDatabase() async {
    try {
      final pickedFile = await FilePicker.pickFile(
        type: FileType.any,
      );

      if (pickedFile == null || pickedFile.path == null) {
        return BackupResult(success: false, message: 'Pemulihan dibatalkan.');
      }

      final dbFile = File(pickedFile.path!);
      if (!dbFile.path.toLowerCase().endsWith('.db')) {
        return BackupResult(
          success: false,
          message: 'Format file tidak sesuai! Harus berformat .db',
        );
      }

      final docDir = await getApplicationDocumentsDirectory();
      final dbPath = p.join(docDir.path, 'kasirtoko.db');
      final existingDb = File(dbPath);

      // Save safety rollback copy before overwriting
      if (await existingDb.exists()) {
        await existingDb.copy(p.join(docDir.path, 'kasirtoko_before_restore.db'));
      }

      // Safely close and nullify cached DB singleton so next access re-opens cleanly
      await DatabaseHelper.instance.resetConnection();

      // Remove stale WAL/SHM files if present
      for (final suffix in ['-wal', '-shm']) {
        final sideFile = File('$dbPath$suffix');
        if (await sideFile.exists()) {
          await sideFile.delete();
        }
      }

      await dbFile.copy(dbPath);

      // Re-open database right away (runs onUpgrade automatically if backup was v1!)
      await DatabaseHelper.instance.database;

      return BackupResult(
        success: true,
        message: 'Database berhasil dipulihkan dan disinkronkan!',
      );
    } catch (e) {
      return BackupResult(success: false, message: 'Gagal memulihkan database: $e');
    }
  }
}
