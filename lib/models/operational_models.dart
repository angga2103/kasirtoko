import '../models/user.dart';

enum AdminNetworkState {
  routerOnline,
  hotspotBackup,
  offline,
  serverUnavailable,
}

extension AdminNetworkStateLabel on AdminNetworkState {
  String get displayLabel {
    switch (this) {
      case AdminNetworkState.routerOnline:
        return 'Router Online';
      case AdminNetworkState.hotspotBackup:
        return 'Hotspot Cadangan';
      case AdminNetworkState.offline:
        return 'Offline';
      case AdminNetworkState.serverUnavailable:
        return 'Server Tidak Tersedia';
    }
  }
}

class SessionPolicyModel {
  final String role;
  final int maxActiveSessions;
  final String updatedAt;
  final String updatedBy;

  const SessionPolicyModel({
    required this.role,
    required this.maxActiveSessions,
    required this.updatedAt,
    this.updatedBy = 'Sistem',
  });

  String get roleLabel => AppRoles.displayName(role);

  Map<String, dynamic> toMap() => {
        'role': role,
        'max_active_sessions': maxActiveSessions,
        'updated_at': updatedAt,
        'updated_by': updatedBy,
      };

  factory SessionPolicyModel.fromMap(Map<String, dynamic> map) => SessionPolicyModel(
        role: (map['role'] ?? AppRoles.cashier).toString(),
        maxActiveSessions: (map['max_active_sessions'] as num?)?.toInt() ?? 1,
        updatedAt: (map['updated_at'] ?? '').toString(),
        updatedBy: (map['updated_by'] ?? 'Sistem').toString(),
      );
}

class ServerNetworkEndpointModel {
  final int? id;
  final String profileType; // 'primary_router' | 'backup_hotspot'
  final String label;
  final String baseUrl;
  final String host;
  final int port;
  final String expectedSsid;
  final int priority;
  final bool isActive;
  final String notes;
  final String updatedAt;

  const ServerNetworkEndpointModel({
    this.id,
    required this.profileType,
    required this.label,
    required this.baseUrl,
    required this.host,
    this.port = 8443,
    this.expectedSsid = '',
    this.priority = 1,
    this.isActive = true,
    this.notes = '',
    required this.updatedAt,
  });

  String get effectiveUrl {
    if (baseUrl.trim().isNotEmpty) return baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (host.trim().isEmpty) return '';
    return 'https://${host.trim()}:$port';
  }

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'profile_type': profileType,
        'label': label,
        'base_url': effectiveUrl,
        'host': host.trim(),
        'port': port,
        'expected_ssid': expectedSsid.trim(),
        'priority': priority,
        'is_active': isActive ? 1 : 0,
        'notes': notes.trim(),
        'updated_at': updatedAt,
      };

  Map<String, dynamic> toApiJson() => {
        'profile_type': profileType,
        'label': label,
        'base_url': effectiveUrl,
        'host': host.trim(),
        'port': port,
        'expected_ssid': expectedSsid.trim(),
        'priority': priority,
        'is_active': isActive,
      };

  factory ServerNetworkEndpointModel.fromMap(Map<String, dynamic> map) =>
      ServerNetworkEndpointModel(
        id: (map['id'] as num?)?.toInt(),
        profileType: (map['profile_type'] ?? 'primary_router').toString(),
        label: (map['label'] ?? '').toString(),
        baseUrl: (map['base_url'] ?? '').toString(),
        host: (map['host'] ?? '').toString(),
        port: (map['port'] as num?)?.toInt() ?? 8443,
        expectedSsid: (map['expected_ssid'] ?? '').toString(),
        priority: (map['priority'] as num?)?.toInt() ?? 1,
        isActive: (map['is_active'] ?? 1) == 1,
        notes: (map['notes'] ?? '').toString(),
        updatedAt: (map['updated_at'] ?? '').toString(),
      );
}

class BackupJobModel {
  final int? id;
  final String jobType; // 'hourly_snapshot' | 'nightly_full'
  final String label;
  final String scheduleMode;
  final int intervalMinutes;
  final int nightlyHour;
  final int nightlyMinute;
  final String targetLocationType; // 'local_separate' | 'external' | 'saf'
  final String targetUri;
  final String secondaryUri;
  final int retentionCount;
  final bool isEnabled;
  final String? lastRunAt;
  final String lastStatus; // 'idle' | 'running' | 'verified' | 'failed'
  final String lastError;
  final String? nextRunAt;
  final String updatedAt;

  const BackupJobModel({
    this.id,
    required this.jobType,
    this.label = '',
    this.scheduleMode = 'hourly',
    this.intervalMinutes = 60,
    this.nightlyHour = 23,
    this.nightlyMinute = 30,
    this.targetLocationType = 'local_separate',
    this.targetUri = '',
    this.secondaryUri = '',
    this.retentionCount = 24,
    this.isEnabled = true,
    this.lastRunAt,
    this.lastStatus = 'idle',
    this.lastError = '',
    this.nextRunAt,
    required this.updatedAt,
  });

  factory BackupJobModel.fromMap(Map<String, dynamic> map) => BackupJobModel(
        id: (map['id'] as num?)?.toInt(),
        jobType: (map['job_type'] ?? 'hourly_snapshot').toString(),
        label: (map['label'] ?? '').toString(),
        scheduleMode: (map['schedule_mode'] ?? 'hourly').toString(),
        intervalMinutes: (map['interval_minutes'] as num?)?.toInt() ?? 60,
        nightlyHour: (map['nightly_hour'] as num?)?.toInt() ?? 23,
        nightlyMinute: (map['nightly_minute'] as num?)?.toInt() ?? 30,
        targetLocationType: (map['target_location_type'] ?? 'local_separate').toString(),
        targetUri: (map['target_uri'] ?? '').toString(),
        secondaryUri: (map['secondary_uri'] ?? '').toString(),
        retentionCount: (map['retention_count'] as num?)?.toInt() ?? 24,
        isEnabled: (map['is_enabled'] ?? 1) == 1,
        lastRunAt: map['last_run_at']?.toString(),
        lastStatus: (map['last_status'] ?? 'idle').toString(),
        lastError: (map['last_error'] ?? '').toString(),
        nextRunAt: map['next_run_at']?.toString(),
        updatedAt: (map['updated_at'] ?? '').toString(),
      );
}

class BackupArtifactModel {
  final int? id;
  final int? jobId;
  final String artifactUuid;
  final String backupType; // 'hourly' | 'nightly' | 'manual' | 'pre_migration' | 'pre_restore'
  final String fileName;
  final String primaryPath;
  final String secondaryPath;
  final String locationType;
  final int plainSizeBytes;
  final int encryptedSizeBytes;
  final String plainSha256;
  final String encryptedSha256;
  final String encryptionVersion;
  final String status; // 'verified' | 'created' | 'failed'
  final bool verifiedRestoreOk;
  final String verificationSummary;
  final String errorMessage;
  final String createdAt;

  const BackupArtifactModel({
    this.id,
    this.jobId,
    required this.artifactUuid,
    required this.backupType,
    required this.fileName,
    required this.primaryPath,
    this.secondaryPath = '',
    this.locationType = 'local_separate',
    this.plainSizeBytes = 0,
    this.encryptedSizeBytes = 0,
    this.plainSha256 = '',
    this.encryptedSha256 = '',
    this.encryptionVersion = 'aes256gcm_v1',
    this.status = 'created',
    this.verifiedRestoreOk = false,
    this.verificationSummary = '',
    this.errorMessage = '',
    required this.createdAt,
  });

  factory BackupArtifactModel.fromMap(Map<String, dynamic> map) => BackupArtifactModel(
        id: (map['id'] as num?)?.toInt(),
        jobId: (map['job_id'] as num?)?.toInt(),
        artifactUuid: (map['artifact_uuid'] ?? '').toString(),
        backupType: (map['backup_type'] ?? 'manual').toString(),
        fileName: (map['file_name'] ?? '').toString(),
        primaryPath: (map['primary_path'] ?? '').toString(),
        secondaryPath: (map['secondary_path'] ?? '').toString(),
        locationType: (map['location_type'] ?? 'local_separate').toString(),
        plainSizeBytes: (map['plain_size_bytes'] as num?)?.toInt() ?? 0,
        encryptedSizeBytes: (map['encrypted_size_bytes'] as num?)?.toInt() ?? 0,
        plainSha256: (map['plain_sha256'] ?? '').toString(),
        encryptedSha256: (map['encrypted_sha256'] ?? '').toString(),
        encryptionVersion: (map['encryption_version'] ?? 'aes256gcm_v1').toString(),
        status: (map['status'] ?? 'created').toString(),
        verifiedRestoreOk: (map['verified_restore_ok'] ?? 0) == 1,
        verificationSummary: (map['verification_summary'] ?? '').toString(),
        errorMessage: (map['error_message'] ?? '').toString(),
        createdAt: (map['created_at'] ?? '').toString(),
      );
}
