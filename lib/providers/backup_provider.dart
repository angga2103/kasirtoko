import 'dart:async';
import 'package:flutter/foundation.dart';

import '../database/db_helper.dart';
import '../models/operational_models.dart';
import '../services/backup_service.dart';

class BackupProvider extends ChangeNotifier {
  final DatabaseHelper _dbHelper;

  List<BackupJobModel> _jobs = [];
  List<BackupArtifactModel> _artifacts = [];
  int _availableStorageBytes = -1;
  bool _hasRecoveryPassphrase = false;
  bool _isBusy = false;
  String? _lastError;
  String? _lastMessage;
  Timer? _schedulerTimer;

  BackupProvider({DatabaseHelper? dbHelper}) : _dbHelper = dbHelper ?? DatabaseHelper.instance;

  List<BackupJobModel> get jobs => _jobs;
  List<BackupArtifactModel> get artifacts => _artifacts;
  int get availableStorageBytes => _availableStorageBytes;
  bool get hasRecoveryPassphrase => _hasRecoveryPassphrase;
  bool get isBusy => _isBusy;
  String? get lastError => _lastError;
  String? get lastMessage => _lastMessage;

  bool get isLowStorage =>
      _availableStorageBytes >= 0 &&
      _availableStorageBytes < BackupService.minRequiredFreeSpaceBytes;

  BackupJobModel? get hourlyJob =>
      _jobs.where((j) => j.jobType == 'hourly_snapshot').firstOrNull;
  BackupJobModel? get nightlyJob =>
      _jobs.where((j) => j.jobType == 'nightly_full').firstOrNull;
  BackupArtifactModel? get latestArtifact => _artifacts.isNotEmpty ? _artifacts.first : null;

  bool get hasWarning =>
      isLowStorage ||
      _jobs.any((j) => j.lastStatus == 'failed') ||
      (latestArtifact != null && !latestArtifact!.verifiedRestoreOk);

  Future<void> initialize() async {
    await refreshStatus();
    _startSchedulerTimer();
  }

  Future<void> refreshStatus() async {
    try {
      _jobs = await _dbHelper.getBackupJobs();
      _artifacts = await _dbHelper.listBackupArtifacts(limit: 40);
      _hasRecoveryPassphrase = await BackupService.hasRecoveryPassphraseConfigured();
      final primaryDir = hourlyJob?.targetUri;
      _availableStorageBytes = await BackupService.getAvailableStorageBytes(
        (primaryDir != null && primaryDir.isNotEmpty) ? primaryDir : null,
      );
      notifyListeners();
    } catch (_) {}
  }

  void _startSchedulerTimer() {
    _schedulerTimer?.cancel();
    _schedulerTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      unawaited(evaluateScheduledBackups());
    });
  }

  /// Checks whether hourly (every 60m) or nightly full backup is due and runs without blocking UI.
  Future<void> evaluateScheduledBackups({DateTime? nowOverride}) async {
    if (_isBusy) return;
    final now = nowOverride ?? DateTime.now();
    await refreshStatus();

    final hourly = hourlyJob;
    if (hourly != null && hourly.isEnabled) {
      final lastRun = hourly.lastRunAt != null ? DateTime.tryParse(hourly.lastRunAt!) : null;
      final due = lastRun == null ||
          now.difference(lastRun) >= Duration(minutes: hourly.intervalMinutes);
      if (due) {
        await runBackupNow(
          backupType: 'hourly',
          job: hourly,
          actorName: 'Scheduler Backup 1 Jam',
        );
      }
    }

    final nightly = nightlyJob;
    if (nightly != null && nightly.isEnabled) {
      final lastRun = nightly.lastRunAt != null ? DateTime.tryParse(nightly.lastRunAt!) : null;
      final scheduledToday = DateTime(
        now.year,
        now.month,
        now.day,
        nightly.nightlyHour,
        nightly.nightlyMinute,
      );
      final ranToday = lastRun != null &&
          lastRun.year == now.year &&
          lastRun.month == now.month &&
          lastRun.day == now.day;
      if (!ranToday && !now.isBefore(scheduledToday)) {
        await runBackupNow(
          backupType: 'nightly',
          job: nightly,
          actorName: 'Scheduler Backup Malam',
        );
      }
    }
  }

  Future<BackupResult> runBackupNow({
    String backupType = 'manual',
    BackupJobModel? job,
    String actorName = 'Admin',
    String? recoveryPassphrase,
  }) async {
    if (_isBusy) {
      return BackupResult(success: false, message: 'Proses backup lain sedang berjalan.');
    }
    _isBusy = true;
    _lastError = null;
    notifyListeners();

    final targetJob = job ?? hourlyJob;
    try {
      final res = await BackupService.createEncryptedBackup(
        backupType: backupType,
        jobId: targetJob?.id,
        customPrimaryDir: (targetJob?.targetLocationType == 'local_custom' &&
                (targetJob?.targetUri.isNotEmpty ?? false))
            ? targetJob!.targetUri
            : null,
        secondaryDir: targetJob?.secondaryUri,
        safTreeUri: targetJob?.targetLocationType == 'saf' ? targetJob?.targetUri : null,
        recoveryPassphrase: recoveryPassphrase,
        verifyImmediately: true,
        actorName: actorName,
      );

      if (targetJob != null) {
        final nextRun = DateTime.now()
            .add(Duration(minutes: targetJob.intervalMinutes))
            .toIso8601String();
        await _dbHelper.recordBackupJobRun(
          targetJob.jobType,
          status: res.success ? 'verified' : 'failed',
          errorMessage: res.success ? '' : res.message,
          nextRunAt: nextRun,
        );
      }

      if (!res.success) {
        _lastError = res.message;
      } else {
        _lastMessage = res.message;
      }
      await refreshStatus();
      return res;
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  Future<BackupVerificationResult> verifyArtifact(
    BackupArtifactModel artifact, {
    String? recoveryPassphrase,
  }) async {
    _isBusy = true;
    notifyListeners();
    try {
      final res = await BackupService.verifyBackupArtifact(
        artifact.primaryPath,
        expectedEncryptedSha256: artifact.encryptedSha256,
        artifactUuid: artifact.artifactUuid,
        recoveryPassphrase: recoveryPassphrase,
      );
      if (!res.valid) {
        _lastError = res.message;
      } else {
        _lastMessage = res.message;
      }
      await refreshStatus();
      return res;
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  Future<BackupResult> restoreFromArtifact(
    BackupArtifactModel artifact, {
    String? recoveryPassphrase,
    String actorName = 'Admin',
  }) async {
    _isBusy = true;
    _lastError = null;
    notifyListeners();
    try {
      final res = await BackupService.restoreFromFilePath(
        artifact.primaryPath,
        recoveryPassphrase: recoveryPassphrase,
        actorName: actorName,
      );
      if (!res.success) {
        _lastError = res.message;
      } else {
        _lastMessage = res.message;
      }
      await refreshStatus();
      return res;
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  Future<void> configureJob({
    required String jobType,
    bool? isEnabled,
    int? intervalMinutes,
    int? nightlyHour,
    int? nightlyMinute,
    String? targetLocationType,
    String? targetUri,
    String? secondaryUri,
  }) async {
    await _dbHelper.updateBackupJobConfig(
      jobType,
      isEnabled: isEnabled,
      intervalMinutes: intervalMinutes,
      nightlyHour: nightlyHour,
      nightlyMinute: nightlyMinute,
      targetLocationType: targetLocationType,
      targetUri: targetUri,
      secondaryUri: secondaryUri,
    );
    await refreshStatus();
  }

  @override
  void dispose() {
    _schedulerTimer?.cancel();
    super.dispose();
  }
}
