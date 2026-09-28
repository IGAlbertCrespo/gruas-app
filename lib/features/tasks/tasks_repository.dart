import '../../core/network/api_client.dart';
import 'task_models.dart';

String _two(int n) => n.toString().padLeft(2, '0');

/// Formatea una fecha/hora a UTC 'YYYY-MM-DD HH:MM:SS' (lo que espera Odoo).
String _fmtUtc(DateTime d) {
  final u = d.toUtc();
  return '${u.year.toString().padLeft(4, '0')}-${_two(u.month)}-${_two(u.day)} '
      '${_two(u.hour)}:${_two(u.minute)}:${_two(u.second)}';
}

class TasksRepository {
  TasksRepository(this.api);
  final ApiClient api;

  Future<({int count, String scope, List<TaskSummary> tasks})> list({
    String scope = 'mine',
    int limit = 80,
    int offset = 0,
  }) async {
    final res = await api.getJson('/tasks', query: {'scope': scope, 'limit': limit, 'offset': offset});
    final list = (res['tasks'] ?? []) as List;
    return (
      count: (res['count'] ?? 0) as int,
      scope: res['scope']?.toString() ?? scope,
      tasks: list.map((e) => TaskSummary.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }

  Future<TaskDetail> detail(int id) async {
    final res = await api.getJson('/tasks/$id');
    return TaskDetail.fromJson(res);
  }

  /// Inicia o reanuda. `informada` solo en modo informada (en planificada no se envía).
  Future<({TaskDetail task, JornadaStart? jornada})> start(
    int id, {
    double? lat,
    double? lng,
    DateTime? informada,
  }) async {
    final res = await api.postJson('/tasks/$id/start', data: {
      if (lat != null) 'lat': lat,
      if (lng != null) 'lng': lng,
      if (informada != null) 'informada': _fmtUtc(informada),
    });
    return (
      task: TaskDetail.fromJson(res),
      jornada: res['jornada'] is Map
          ? JornadaStart.fromJson(res['jornada'] as Map<String, dynamic>)
          : null,
    );
  }
  /// Cierra UN recurso: cierre informado + pausa + modo. El backend deriva el
  /// facturable (ceil30 − pausa). NO mueve etapa.
  Future<TaskDetail> close(int id, {
    DateTime? cierreInformada,
    double? pausa,
    String modo = 'normal',           // 'normal' | 'minimo' | 'incidencia'
    double? lat,
    double? lng,
  }) async {
    final res = await api.postJson('/tasks/$id/close', data: {
      if (cierreInformada != null) 'cierre_informada': _fmtUtc(cierreInformada),
      if (pausa != null) 'pausa': pausa,
      'modo': modo,
      if (lat != null) 'lat': lat,
      if (lng != null) 'lng': lng,
    });
    return TaskDetail.fromJson(res);
  }

  /// Finaliza el servicio: mueve la madre a Finalizada (arrastra hijas).
  Future<TaskDetail> finalize(int id, {double? lat, double? lng}) async {
    final res = await api.postJson('/tasks/$id/finalize', data: {
      if (lat != null) 'lat': lat,
      if (lng != null) 'lng': lng,
    });
    return TaskDetail.fromJson(res);
  }

  /// Pausa la tarea: cierra el tramo abierto (no cambia de etapa).
  Future<TaskDetail> pause(int id, {double? lat, double? lng}) async {
    final res = await api.postJson('/tasks/$id/pause', data: {
      if (lat != null) 'lat': lat,
      if (lng != null) 'lng': lng,
    });
    return TaskDetail.fromJson(res);
  }

  Future<TaskDetail> addNote(int id, String text) async {
    await api.postJson('/tasks/$id/note', data: {'text': text});
    return detail(id);
  }

  Future<void> reopen(int id) async {
    await api.postJson('/tasks/$id/stage', data: {'target': 'informado'});
  }

  /// Firma del cliente: imagen + nombre + observaciones del cliente + GPS.
  Future<void> saveSignature(int id, String signatureBase64,
      {String? signerName, String? dni, String? obsCliente, double? lat, double? lng}) async {
    await api.postJson('/tasks/$id/signature', data: {
      'signature': signatureBase64,
      if (signerName != null) 'signer_name': signerName,
      if (dni != null) 'dni': dni,
      if (obsCliente != null) 'obs_cliente': obsCliente,
      if (lat != null) 'lat': lat,
      if (lng != null) 'lng': lng,
    });
  }
}

/// Respaldo de jornada que el servidor puede abrir al iniciar/reanudar una tarea.
class JornadaStart {
  final bool abiertaAutomaticamente;
  final String? checkIn;
  final String? error;

  const JornadaStart({
    required this.abiertaAutomaticamente,
    this.checkIn,
    this.error,
  });

  factory JornadaStart.fromJson(Map<String, dynamic> j) => JornadaStart(
        abiertaAutomaticamente: j['abierta_automaticamente'] == true,
        checkIn: j['check_in']?.toString(),
        error: j['error']?.toString(),
      );
}
