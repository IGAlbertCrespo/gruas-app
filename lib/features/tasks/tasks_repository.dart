import '../../core/network/api_client.dart';
import 'task_models.dart';
import 'actividad_models.dart';
import '../../shared/formulario_tiempo.dart' show TiempoDeclarado;

String _two(int n) => n.toString().padLeft(2, '0');

/// Formatea una fecha/hora a UTC 'YYYY-MM-DD HH:MM:SS' (lo que espera Odoo).
String _fmtUtc(DateTime d) {
  final u = d.toUtc();
  return '${u.year.toString().padLeft(4, '0')}-${_two(u.month)}-${_two(u.day)} '
      '${_two(u.hour)}:${_two(u.minute)}:${_two(u.second)}';
}

/// v3.10 §4.1 — tiempo declarado → body. `apertura_informada` solo si
/// [enviarInicio] (solo horas, o inicio corregido de una tarea iniciada).
Map<String, dynamic> _tiempoBody(TiempoDeclarado t, {required bool enviarInicio}) {
  final ini = t.inicio, fin = t.fin, ci = t.comidaInicio;
  return {
    'formato': t.formato.wire,
    if (enviarInicio && ini != null) 'apertura_informada': _fmtUtc(ini),
    if (fin != null) 'cierre_informada': _fmtUtc(fin),
    if (t.horas != null) 'horas_totales': t.horas,
    'comida': t.comidaMin > 0
        ? {'minutos': t.comidaMin, if (ci != null) 'inicio': _fmtUtc(ci)}
        : null,
  };
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
  /// v3.10 §4.1 — cierre de UN recurso con el tiempo declarado. El servidor
  /// calcula el facturable (redondeo de la compañía) y decide el mínimo.
  Future<({TaskDetail task, JornadaStart? jornada})> close(
    int id, {
    required TiempoDeclarado tiempo,
    required bool enviarInicio,
    bool incidencia = false,
    String? obsAlbaran,
    bool confirmar = false,
    double? lat,
    double? lng,
  }) async {
    final res = await api.postJson('/tasks/$id/close', data: {
      ..._tiempoBody(tiempo, enviarInicio: enviarInicio),
      'incidencia': incidencia,
      if (obsAlbaran != null) 'obs_albaran': obsAlbaran,
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
    /// v3.3 §5.3 — candidatos a servicio principal (madre).
  Future<List<CandidatoServicio>> servicios(int id) async {
    final res = await api.getJson('/tasks/$id/servicios');
    return CandidatoServicio.listFromJson(res['data']);
  }

  /// v3.3 §5.3 — la APP envía siempre confirmar: true (sin avisos de mínimo).
  Future<TaskDetail> cambiarServicio(int id, int lineId, {bool confirmar = true}) async {
    final res = await api.postJson('/tasks/$id/servicio',
        data: {'line_id': lineId, 'confirmar': confirmar});
    return TaskDetail.fromJson(res);
  }

  /// v3.3 §5.4 — complementos disponibles (sin los ya activos).
  Future<List<Complemento>> complementos(int id) async {
    final res = await api.getJson('/tasks/$id/complementos');
    return Complemento.listFromJson(res['data']);
  }

  Future<TaskDetail> anadirCargo(int id, int productId) async {
    final res = await api.postJson('/tasks/$id/cargos', data: {'product_id': productId});
    return TaskDetail.fromJson(res);
  }

  Future<TaskDetail> anularCargo(int id, int cargoId) async {
    final res = await api.postJson('/tasks/$id/cargos/$cargoId/anular');
    return TaskDetail.fromJson(res);
  }

  /// Completa una NO FACTURABLE con inicio/fin informados. Repetible en el día.
  /// El servidor aplica la regla de medianoche y el umbral de 16 h, y puede
  /// abrir la jornada con el inicio si ese día no hay ningún fichaje.
    Future<({TaskDetail task, JornadaStart? jornada})> complete(
    int id, {
    required DateTime inicio,
    required DateTime fin,
    String? obsAlbaran,
    bool confirmar = false,
    double? lat,
    double? lng,
  }) async {
    final obs = obsAlbaran?.trim();
    final res = await api.postJson('/tasks/$id/complete', data: {
      'inicio': _fmtUtc(inicio),
      'fin': _fmtUtc(fin),
      if (obs != null && obs.isNotEmpty) 'obs_albaran': obs, // v3.12
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
   /// v3.10 §4.5.3 — no facturable con solo horas: día de ejecución + tiempo
  /// declarado con los formatos de la compañía. Tiempo real, sin redondeo.
  Future<({TaskDetail task, JornadaStart? jornada})> completeTiempo(
    int id, {
    required DateTime fecha,
    required TiempoDeclarado tiempo,
    bool confirmar = false,
    double? lat,
    double? lng,
  }) async {
    final dia = '${fecha.year.toString().padLeft(4, '0')}-${_two(fecha.month)}-${_two(fecha.day)}';
        final obs = tiempo.obs?.trim();
    final res = await api.postJson('/tasks/$id/complete', data: {
      'fecha': dia,
      ..._tiempoBody(tiempo, enviarInicio: true),
      if (obs != null && obs.isNotEmpty) 'obs_albaran': obs, // v3.12
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
    // ---------------------------------------------------------------------------
  // v3.11 §4.8 — tareas creadas por el conductor
  // ---------------------------------------------------------------------------

  /// Catálogo de actividades (líneas del pedido interno).
  Future<List<Actividad>> actividades() async {
    final res = await api.getJson('/actividades');
    return Actividad.listFromJson(res['data']);
  }

  /// Vehículos "Disponible en APP" (habituales primero).
  Future<List<VehiculoApp>> vehiculos() async {
    final res = await api.getJson('/vehiculos');
    return VehiculoApp.listFromJson(res['data']);
  }

  /// [ONLINE] Crea la tarea ya completada. Tiempo real, sin redondeo.
  Future<({TaskDetail task, JornadaStart? jornada})> crearTarea({
    required int lineId,
    required int vehicleId,
    required DateTime fecha,
    required TiempoDeclarado tiempo,
    String? obs,
    bool confirmar = false,
    double? lat,
    double? lng,
  }) async {
    final dia = '${fecha.year.toString().padLeft(4, '0')}-${_two(fecha.month)}-${_two(fecha.day)}';
    final texto = obs?.trim();
    final res = await api.postJson('/tasks', data: {
      'line_id': lineId,
      'vehicle_id': vehicleId,
      'fecha': dia,
      ..._tiempoBody(tiempo, enviarInicio: true),
      if (texto != null && texto.isNotEmpty) 'obs': texto,
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
  /// Finaliza la madre. Con `firmaDiferida` (§6.3) finaliza sin firma y el
  /// servidor genera la solicitud de firma.
  Future<TaskDetail> finalize(int id, {bool firmaDiferida = false, double? lat, double? lng}) async {
    final res = await api.postJson('/tasks/$id/finalize', data: {
      if (firmaDiferida) 'firma_diferida': true,
      if (lat != null) 'lat': lat,
      if (lng != null) 'lng': lng,
    });
    return TaskDetail.fromJson(res);
  }

  /// v3.3 §6.4 — madres propias de la misma obra, finalizadas sin firmar.
  Future<List<PendienteFirma>> pendientesFirma(int id) async {
    final res = await api.getJson('/tasks/$id/pendientes-firma');
    return PendienteFirma.listFromJson(res['data']);
  }

  /// v3.3 §6.5 [ONLINE] — firma en lote. Devuelve el código del lote.
  Future<String> firmarLote(List<int> taskIds, String? signatureBase64,
      {int? firmanteId, String? signerName, String? dni, String? obsCliente,
       double? lat, double? lng}) async {
    final res = await api.postJson('/firma/lote', data: {
      'task_ids': taskIds,
      if (signatureBase64 != null) 'signature': signatureBase64,
      if (firmanteId != null) 'firmante_id': firmanteId,
      if (signerName != null) 'signer_name': signerName,
      if (dni != null && dni.isNotEmpty) 'dni': dni,
      if (obsCliente != null) 'obs_cliente': obsCliente,
      if (lat != null) 'lat': lat,
      if (lng != null) 'lng': lng,
    });
    return res['lote']?.toString() ?? '';
  }

  /// v3.3 §6.6 [ONLINE] — crea el enlace de firma (anula los vivos previos).
  Future<SolicitudCreada> crearSolicitudFirma(List<int> taskIds,
      {int? firmanteId, required String movil}) async {
    final res = await api.postJson('/firma/solicitudes', data: {
      'task_ids': taskIds,
      if (firmanteId != null) 'firmante_id': firmanteId,
      'movil': movil,
    });
    final s = SolicitudCreada.fromJson(res);
    if (s == null) throw Exception('Respuesta de solicitud no válida.');
    return s;
  }

  /// Pausa la tarea: cierra el tramo abierto (no cambia de etapa).
  Future<TaskDetail> pause(int id, {double? lat, double? lng}) async {
    final res = await api.postJson('/tasks/$id/pause', data: {
      if (lat != null) 'lat': lat,
      if (lng != null) 'lng': lng,
    });
    return TaskDetail.fromJson(res);
  }

   /// "Comentario para oficina" (§4.9.1): se acumula en x_notas_chofer. Interno.
  Future<TaskDetail> addNote(int id, String text) async {
    await api.postJson('/tasks/$id/note', data: {'text': text});
    return detail(id);
  }

  /// v3.12 §4.9.2 — observaciones del albarán (las ve el cliente). Vacío = borrar.
  Future<TaskDetail> setObservaciones(int id, String texto) async {
    final res = await api.postJson('/tasks/$id/observaciones',
        data: {'obs_albaran': texto.trim()});
    return TaskDetail.fromJson(res);
  }

  Future<void> reopen(int id) async {
    await api.postJson('/tasks/$id/stage', data: {'target': 'informado'});
  }

    /// v3.3 §6.2 — sobre la MADRE. Con `firmanteId` el servidor rellena nombre
  /// y documento desde el contacto (y exige firma dibujada). Sin firma dibujada
  /// (regla dos de tres) `signatureBase64` es null.
  Future<void> saveSignature(int id, String? signatureBase64,
      {int? firmanteId, String? signerName, String? dni, String? obsCliente,
       double? lat, double? lng}) async {
    await api.postJson('/tasks/$id/signature', data: {
      if (signatureBase64 != null) 'signature': signatureBase64,
      if (firmanteId != null) 'firmante_id': firmanteId,
      if (signerName != null) 'signer_name': signerName,
      if (dni != null && dni.isNotEmpty) 'dni': dni,
      if (obsCliente != null) 'obs_cliente': obsCliente,
      if (lat != null) 'lat': lat,
      if (lng != null) 'lng': lng,
    });
  }

  /// v3.3 §6.1 — firmantes de la obra de la tarea.
  Future<List<Firmante>> firmantes(int id) async {
    final res = await api.getJson('/tasks/$id/firmantes');
    return Firmante.listFromJson(res['data']);
  }

  /// v3.3 §6.1 [ONLINE] — alta o vinculación por documento (sin duplicar).
  Future<Firmante> crearFirmante(int id,
      {required String nombre, required String documento, String? movil}) async {
    final res = await api.postJson('/tasks/$id/firmantes', data: {
      'nombre': nombre,
      'documento': documento,
      'movil': movil,
    });
    final f = Firmante.fromJson(res);
    if (f == null) throw Exception('Respuesta de firmante no válida.');
    return f;
  }
}

/// Jornada que el servidor abre o registra (respaldo de /start; con "solo
/// horas", la jornada completa calculada de las tareas en /close y /complete).
class JornadaStart {
  final bool abiertaAutomaticamente;
  final String? checkIn;
  final String? checkOut; // v3.8: solo cuando el servidor registra la jornada completa
  final String? error;

  const JornadaStart({
    required this.abiertaAutomaticamente,
    this.checkIn,
    this.checkOut,
    this.error,
  });

  factory JornadaStart.fromJson(Map<String, dynamic> j) => JornadaStart(
        abiertaAutomaticamente: j['abierta_automaticamente'] == true,
        checkIn: j['check_in']?.toString(),
        checkOut: j['check_out']?.toString(),
        error: j['error']?.toString(),
      );
}