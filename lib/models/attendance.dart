class AttendanceModel {
  final int? id;
  final int employeeId;
  final String employeeName;
  final DateTime timestamp;
  final String type; // 'masuk', 'pulang'
  final String status; // 'tepat_waktu', 'terlambat', 'pulang', 'koreksi_admin'
  final int lateMinutes;
  final String challengeCode;
  final String validationHash;
  final String photoPath;
  final bool isLivenessPassed;
  final String deviceInfo;
  final bool isCorrected;
  final String correctionNote;

  AttendanceModel({
    this.id,
    required this.employeeId,
    required this.employeeName,
    required this.timestamp,
    required this.type,
    required this.status,
    this.lateMinutes = 0,
    required this.challengeCode,
    required this.validationHash,
    required this.photoPath,
    this.isLivenessPassed = true,
    this.deviceInfo = '',
    this.isCorrected = false,
    this.correctionNote = '',
  });

  bool get isLate => status == 'terlambat';

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'employee_id': employeeId,
      'employee_name': employeeName,
      'timestamp': timestamp.toIso8601String(),
      'type': type,
      'status': status,
      'late_minutes': lateMinutes,
      'challenge_code': challengeCode,
      'validation_hash': validationHash,
      'photo_path': photoPath,
      'is_liveness_passed': isLivenessPassed ? 1 : 0,
      'device_info': deviceInfo,
      'is_corrected': isCorrected ? 1 : 0,
      'correction_note': correctionNote,
    };
  }

  factory AttendanceModel.fromMap(Map<String, dynamic> map) {
    return AttendanceModel(
      id: map['id'] as int?,
      employeeId: map['employee_id'] as int,
      employeeName: map['employee_name'] ?? 'Karyawan',
      timestamp: DateTime.parse(map['timestamp']),
      type: map['type'],
      status: map['status'] ?? 'tepat_waktu',
      lateMinutes: map['late_minutes'] ?? 0,
      challengeCode: map['challenge_code'] ?? '',
      validationHash: map['validation_hash'] ?? '',
      photoPath: map['photo_path'] ?? '',
      isLivenessPassed: (map['is_liveness_passed'] ?? 1) == 1,
      deviceInfo: (map['device_info'] ?? '').toString(),
      isCorrected: (map['is_corrected'] ?? 0) == 1,
      correctionNote: (map['correction_note'] ?? '').toString(),
    );
  }
}
