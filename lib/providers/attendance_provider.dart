import 'package:flutter/foundation.dart';
import '../models/attendance.dart';
import '../database/db_helper.dart';

class EmployeeDisciplineSummary {
  final int employeeId;
  final String employeeName;
  final int totalPresent;
  final int onTimeCount;
  final int lateCount;
  final int totalLateMinutes;

  EmployeeDisciplineSummary({
    required this.employeeId,
    required this.employeeName,
    required this.totalPresent,
    required this.onTimeCount,
    required this.lateCount,
    required this.totalLateMinutes,
  });

  double get disciplineRate =>
      totalPresent > 0 ? (onTimeCount / totalPresent) * 100 : 100.0;
}

class AttendanceProvider extends ChangeNotifier {
  List<AttendanceModel> _attendances = [];
  bool _isLoading = false;

  List<AttendanceModel> get attendances => _attendances;
  bool get isLoading => _isLoading;

  Future<void> loadAttendances() async {
    _isLoading = true;
    notifyListeners();

    _attendances = await DatabaseHelper.instance.getRecentAttendances();

    _isLoading = false;
    notifyListeners();
  }

  Future<void> recordAttendance(AttendanceModel attendance) async {
    await DatabaseHelper.instance.insertAttendance(attendance);
    await loadAttendances();
  }

  // Calculate Weekly Discipline Report Summary
  List<EmployeeDisciplineSummary> getWeeklyDisciplineSummary() {
    final Map<int, List<AttendanceModel>> grouped = {};
    for (final att in _attendances) {
      grouped.putIfAbsent(att.employeeId, () => []).add(att);
    }

    List<EmployeeDisciplineSummary> summaries = [];
    grouped.forEach((empId, list) {
      final name = list.first.employeeName;
      final total = list.where((a) => a.type == 'masuk').length;
      final onTime = list.where((a) => a.type == 'masuk' && !a.isLate).length;
      final lateList = list.where((a) => a.type == 'masuk' && a.isLate);
      final lateCount = lateList.length;
      final totalLateMins = lateList.fold(0, (sum, a) => sum + a.lateMinutes);

      summaries.add(
        EmployeeDisciplineSummary(
          employeeId: empId,
          employeeName: name,
          totalPresent: total,
          onTimeCount: onTime,
          lateCount: lateCount,
          totalLateMinutes: totalLateMins,
        ),
      );
    });

    return summaries;
  }
}
