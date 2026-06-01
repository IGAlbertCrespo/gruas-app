/// Estado actual de asistencia (espejo de get_current_attendance_state).
class AttendanceState {
  final bool hasOpen;
  final int? attendanceId;
  final DateTime? checkIn;
  final bool isOnBreak;
  final int? currentBreakId;
  final String? currentBreakType;
  final double workedHours;
  final double totalBreakTime;
  final double effectiveWorkedHours;

  const AttendanceState({
    required this.hasOpen,
    this.attendanceId,
    this.checkIn,
    this.isOnBreak = false,
    this.currentBreakId,
    this.currentBreakType,
    this.workedHours = 0,
    this.totalBreakTime = 0,
    this.effectiveWorkedHours = 0,
  });

  factory AttendanceState.fromJson(Map<String, dynamic> j) {
    final cb = j['current_break'];
    return AttendanceState(
      hasOpen: j['has_open_attendance'] == true,
      attendanceId: j['attendance_id'] is int ? j['attendance_id'] : null,
      checkIn: DateTime.tryParse(j['check_in']?.toString() ?? ''),
      isOnBreak: j['is_on_break'] == true,
      currentBreakId: cb is Map ? cb['id'] as int? : null,
      currentBreakType: cb is Map ? cb['break_type_name']?.toString() : null,
      workedHours: (j['worked_hours'] ?? 0).toDouble(),
      totalBreakTime: (j['total_break_time'] ?? 0).toDouble(),
      effectiveWorkedHours: (j['effective_worked_hours'] ?? 0).toDouble(),
    );
  }
}

class BreakType {
  final int id;
  final String name;
  final bool isDefault;
  const BreakType(this.id, this.name, this.isDefault);

  factory BreakType.fromJson(Map<String, dynamic> j) =>
      BreakType(j['id'] as int, j['name'].toString(), j['is_default'] == true);
}
