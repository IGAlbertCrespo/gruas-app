import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import 'attendance_models.dart';
import 'offline_queue.dart';

/// Asistencia. Online -> llama al endpoint; sin red -> encola con offline_uuid.
class AttendanceRepository {
  AttendanceRepository(this.api, this.queue);
  final ApiClient api;
  final OfflineQueue queue;

  Future<List<BreakType>> breakTypes() async {
    final res = await api.getJson('/attendance/config');
    final list = (res['break_types'] ?? []) as List;
    return list.map((e) => BreakType.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<AttendanceState> currentState() async {
    final res = await api.getJson('/attendance/state');
    return AttendanceState.fromJson(res);
  }

  /// Ejecuta una operación; si falla por red, la encola y la devuelve como diferida.
  Future<Map<String, dynamic>> _op(
    String path,
    String type,
    String offlineUuid,
    Map<String, dynamic> data,
  ) async {
    final payload = {
      'offline_uuid': offlineUuid,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      ...data,
    };
    try {
      return await api.postJson(path, data: payload);
    } on ApiException catch (e) {
      // Solo encolamos ante fallo de red, no ante errores de negocio.
      if (e.code == 'network_error') {
        await queue.enqueue(OfflineOp(
          offlineUuid: offlineUuid,
          type: type,
          timestamp: payload['timestamp'] as String,
          data: data,
        ));
        return {'success': true, 'queued': true};
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> checkIn(String uuid, {double? lat, double? lng}) =>
      _op('/attendance/check-in', 'check_in', uuid,
          {if (lat != null) 'latitude': lat, if (lng != null) 'longitude': lng});

  Future<Map<String, dynamic>> checkOut(String uuid, {int? attendanceId, double? lat, double? lng}) =>
      _op('/attendance/check-out', 'check_out', uuid, {
        if (attendanceId != null) 'attendance_id': attendanceId,
        if (lat != null) 'latitude': lat,
        if (lng != null) 'longitude': lng,
      });

  Future<Map<String, dynamic>> breakStart(String uuid, {int? attendanceId, int? breakTypeId}) =>
      _op('/attendance/break/start', 'break_start', uuid, {
        if (attendanceId != null) 'attendance_id': attendanceId,
        if (breakTypeId != null) 'break_type_id': breakTypeId,
      });

  Future<Map<String, dynamic>> breakEnd(String uuid, {int? breakId, int? attendanceId}) =>
      _op('/attendance/break/end', 'break_end', uuid, {
        if (breakId != null) 'break_id': breakId,
        if (attendanceId != null) 'attendance_id': attendanceId,
      });

  /// Sube todas las operaciones pendientes y confirma las aceptadas.
  Future<int> syncPending() async {
    final pending = await queue.pending();
    if (pending.isEmpty) return 0;
    final res = await api.postJson('/attendance/sync', data: {
      'operations': pending.map((o) => o.toJson()).toList(),
    });
    final results = (res['results'] ?? []) as List;
    final okUuids = results
        .where((r) => (r as Map)['success'] == true)
        .map((r) => (r as Map)['offline_uuid'].toString());
    await queue.ack(okUuids);
    return okUuids.length;
  }
}
