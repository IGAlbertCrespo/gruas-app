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
    /// Cierra UN recurso (CONTRATO v3.1 §4.1). No mueve etapa. El servidor
  /// calcula el facturable y decide el mínimo. `apertura_informada` no se envía
  /// (el servidor usa la guardada).
  Future<TaskDetail> close(int id, {
    required String modoCierre,      // 'hora' | 'duracion'
    DateTime? aperturaInformada,     // solo si el conductor corrigió el inicio
    DateTime? cierreInformada,
    double? horasTotales,
    DateTime? comidaInicio,
    DateTime? comidaFin,
    double? comidaDuracion,
    bool incidencia = false,
    String? obsAlbaran,
    bool confirmar = false,
    double? lat,
    double? lng,
  }) async {
    Map<String, dynamic>? comida;
    if (modoCierre == 'hora' && comidaInicio != null && comidaFin != null) {
      comida = {'inicio': _fmtUtc(comidaInicio), 'fin': _fmtUtc(comidaFin)};
    } else if (modoCierre == 'duracion' && (comidaDuracion ?? 0) > 0) {
      comida = {'duracion': comidaDuracion};
    }
    final res = await api.postJson('/tasks/$id/close', data: {
      'modo_cierre': modoCierre,
      if (aperturaInformada != null) 'apertura_informada': _fmtUtc(aperturaInformada),
      if (cierreInformada != null) 'cierre_informada': _fmtUtc(cierreInformada),
      if (horasTotales != null) 'horas_totales': horasTotales,
      'comida': comida,
      'incidencia': incidencia,
      if (obsAlbaran != null) 'obs_albaran': obsAlbaran,
      if (confirmar) 'confirmar': true,
      if (lat != null) 'lat': lat,
      if (lng != null) 'lng': lng,
    });
    return TaskDetail.fromJson(res);
  }
  /// v3.1 §5.1 — sobre la MADRE. El servidor recalcula el % y lo propaga a los cargos.
  Future<TaskDetail> setRecargo(int id, String tipo) async {
    final res = await api.postJson('/tasks/$id/recargo', data: {'tipo': tipo});
    return TaskDetail.fromJson(res);
  }

  /// v3.1 §5.2 — sobre la MADRE. El servidor recalcula el importe de salida.
  Future<TaskDetail> setSalida(int id, String tipo) async {
    final res = await api.postJson('/tasks/$id/salida', data: {'tipo': tipo});
    return TaskDetail.fromJson(res);
  }

  /// Completa una NO FACTURABLE con inicio/fin informados. Repetible en el día.
  /// El servidor aplica la regla de medianoche y el umbral de 16 h, y puede
  /// abrir la jornada con el inicio si ese día no hay ningún fichaje.
  Future<({TaskDetail task, JornadaStart? jornada})> complete(
    int id, {
    required DateTime inicio,
    required DateTime fin,
    bool confirmar = false,
    double? lat,
    double? lng,
  }) async {
    final res = await api.postJson('/tasks/$id/complete', data: {
      'inicio': _fmtUtc(inicio),
      'fin': _fmtUtc(fin),
      if (confirmar) 'confirmar': true,
      if (lat != null) 'lat': lat,
      if (lng != null) 'lng': lng,
    });
    return (
      task: TaskDetail.fromJson(res),
      jornada: res['jornada'] is Map
          ? JornadaStart.fromJson(res['jornada'] as Map<String, dynamic>)
          : null,
    );
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
