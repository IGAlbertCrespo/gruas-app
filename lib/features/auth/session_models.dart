/// Capacidades del operador, derivadas de los flags de hr.employee en el backend.
class Capabilities {
  final bool app, tasks, requests, admin, attendance;
  const Capabilities({
    this.app = false,
    this.tasks = false,
    this.requests = false,
    this.admin = false,
    this.attendance = false,
  });

  factory Capabilities.fromJson(Map<String, dynamic> j) => Capabilities(
        app: j['app'] == true,
        tasks: j['tasks'] == true,
        requests: j['requests'] == true,
        admin: j['admin'] == true,
        attendance: j['attendance'] == true,
      );
}

/// Perfil del operador devuelto por /me.
class OperatorProfile {
  final int employeeId;
  final String employeeName;
  final String deviceName;
  final String deviceMode; // personal | kiosk
  final bool isManager;    // jefe de tráfico (x_app_admin)
  final Capabilities capabilities;
  final SessionConfig config;

  const OperatorProfile({
    required this.employeeId,
    required this.employeeName,
    required this.deviceName,
    required this.deviceMode,
    required this.isManager,
    required this.capabilities,
    this.config = SessionConfig.fallback,
  });

  factory OperatorProfile.fromJson(Map<String, dynamic> j) {
    final emp = (j['employee'] ?? {}) as Map<String, dynamic>;
    final dev = (j['device'] ?? {}) as Map<String, dynamic>;
    return OperatorProfile(
      employeeId: (emp['id'] ?? 0) as int,
      employeeName: (emp['name'] ?? '') as String,
      deviceName: (dev['name'] ?? '') as String,
      deviceMode: (dev['mode'] ?? 'personal') as String,
      isManager: j['is_manager'] == true,
      capabilities: Capabilities.fromJson((j['capabilities'] ?? {}) as Map<String, dynamic>),
      config: j['config'] is Map
          ? SessionConfig.fromJson(j['config'] as Map<String, dynamic>)
          : SessionConfig.fallback,
    );
  }
}

/// Permisos de compañía para las acciones v3 (CONTRATO §2). Ausente → false:
/// la APP oculta la acción y el servidor respondería 403 sin_permiso.
class Permisos {
  final bool cambiarServicio, anadirCargos, anularCargos,
      editarRecargo, editarSalida, firmaDiferida, crearTareas;
  const Permisos({
    this.cambiarServicio = false,
    this.anadirCargos = false,
    this.anularCargos = false,
    this.editarRecargo = false,
    this.editarSalida = false,
    this.firmaDiferida = false,
    this.crearTareas = false, // v3.11
  });

  factory Permisos.fromJson(Map<String, dynamic> j) => Permisos(
        cambiarServicio: j['cambiar_servicio'] == true,
        anadirCargos: j['anadir_cargos'] == true,
        anularCargos: j['anular_cargos'] == true,
        editarRecargo: j['editar_recargo'] == true,
        editarSalida: j['editar_salida'] == true,
        firmaDiferida: j['firma_diferida'] == true,
        crearTareas: j['crear_tareas'] == true, // v3.11
      );
}
/// v3.10: cómo declara el conductor el tiempo al terminar (CONTRATO §2, §4.1).
enum FormatoCierre {
  horas('horas', 'Horas', 'Solo el número de horas'),
  inicioHoras('inicio_horas', 'Inicio + horas', 'Hora de inicio y número de horas'),
  inicioFin('inicio_fin', 'Inicio y fin', 'Hora de inicio y hora de fin');

  const FormatoCierre(this.wire, this.label, this.ayuda);

  /// Valor que viaja en la API.
  final String wire;
  final String label;
  final String ayuda;

  bool get pideInicio => this != FormatoCierre.horas;
  bool get pideFin => this == FormatoCierre.inicioFin;
}

/// v3.10: duración de comida ofrecida por la compañía ("Sin comida" la añade la APP).
class ComidaOpcion {
  final int minutos;
  final String label;
  final bool defecto;

  const ComidaOpcion({required this.minutos, required this.label, this.defecto = false});

  double get horas => minutos / 60.0;

  static ComidaOpcion? fromJson(dynamic j) {
    if (j is! Map) return null;
    final m = (j['minutos'] as num?)?.toInt() ?? 0;
    if (m <= 0) return null;
    return ComidaOpcion(
      minutos: m,
      label: j['label']?.toString() ?? '$m min',
      defecto: j['defecto'] == true,
    );
  }
}

/// v3.10: paso de los selectores y redondeo del facturable (CONTRATO §2, §4.6).
class TiempoConfig {
  final int pasoMin;
  final int redondeoMin;
  final int toleranciaMin;

  const TiempoConfig({this.pasoMin = 30, this.redondeoMin = 30, this.toleranciaMin = 15});

  double get pasoHoras => pasoMin / 60.0;

  factory TiempoConfig.fromJson(dynamic j) {
    if (j is! Map) return const TiempoConfig();
    int leer(String k, int defecto) => (j[k] as num?)?.toInt() ?? defecto;
    final paso = leer('paso_min', 30);
    final unidad = leer('redondeo_min', 30);
    final u = unidad > 0 ? unidad : 30;
    return TiempoConfig(
      pasoMin: paso > 0 ? paso : 30,
      redondeoMin: u,
      toleranciaMin: leer('tolerancia_min', 15).clamp(0, u).toInt(),
    );
  }
}

class SessionConfig {
  final bool capturaManualHoras;
  final bool mostrarInicioCierre;
  final bool mostrarHorasReales;
  /// informada | planificada. En planificada el servidor ignora `informada`.
  final String modoInicio;
  /// hora | duracion. El selector de duración va en 4.3.
  final String modoCierre;
    final bool tramos;
  /// siempre | solo_horario | nunca (§4.2)
  final String comida;
  /// Posición inicial del selector de comida, en minutos desde 00:00 (local).
  final int comidaHoraDefectoMin;
  final bool minimoMostrarFin;
  final int firmaEnlaceDias;
  final Permisos permisos;
  /// v3.8: operativa "solo horas" (no se inician tareas; se informan horas).
  final bool soloHoras;
  /// v3.8: la compañía registra la jornada (dato informativo).
  final bool controlJornada;
  /// v3.9: con cierre por horas totales, preguntar la comida. Ausente → true.
  final bool comidaEnHoras;
  /// v3.10: formatos permitidos, en orden fijo (horas, inicio_horas, inicio_fin).
  final List<FormatoCierre> formatosCierre;
  /// v3.10: duraciones de comida (sin "Sin comida": la añade la APP).
  final List<ComidaOpcion> comidaOpciones;
  /// v3.10: paso de registro y redondeo del facturable.
  final TiempoConfig tiempo;
  /// v3.11: días admitidos para la fecha de una tarea creada (hoy incluido).
  final int actividadesDias;


  const SessionConfig({
    required this.capturaManualHoras,
    required this.mostrarInicioCierre,
    this.mostrarHorasReales = false,
    this.modoInicio = 'informada',
    this.modoCierre = 'hora',
    this.tramos = false,
    this.comida = 'siempre',
    this.comidaHoraDefectoMin = 14 * 60,
    this.minimoMostrarFin = false,
    this.firmaEnlaceDias = 7,
    this.permisos = const Permisos(),
    this.soloHoras = false,
    this.controlJornada = false,
    this.comidaEnHoras = true,
    this.formatosCierre = const [FormatoCierre.inicioFin],
    this.comidaOpciones = _comidaOpcionesDefecto,
    this.tiempo = const TiempoConfig(),
    this.actividadesDias = 7,
  });

  bool get inicioPlanificado => modoInicio == 'planificada';
  bool get cierrePorDuracion => modoCierre == 'duracion';
  bool get cierreElegir => modoCierre == 'elegir';
  bool get comidaNunca => comida == 'nunca';
  /// ¿Se pregunta la comida en un cierre por horas totales? (v3.9)
  bool get preguntaComidaEnHoras => !comidaNunca && comidaEnHoras;
  /// v3.10: ¿se pregunta la comida con este formato? En inicio y fin, siempre
  /// (salvo `nunca`); en los de horas, según `comida_en_horas`.
  bool preguntaComida(FormatoCierre f) =>
      !comidaNunca && (f == FormatoCierre.inicioFin || comidaEnHoras);

  /// Minutos de la opción marcada por defecto (una sola, §2); si no hay, la primera.
  int get comidaDefectoMin {
    if (comidaOpciones.isEmpty) return 0;
    return comidaOpciones
        .firstWhere((o) => o.defecto, orElse: () => comidaOpciones.first)
        .minutos;
  }

  static const _comidaOpcionesDefecto = [
    ComidaOpcion(minutos: 30, label: '½ h', defecto: true),
    ComidaOpcion(minutos: 60, label: '1 h'),
  ];

  /// v3.10 `formatos_cierre`. Sin la clave (servidor anterior) se deduce de
  /// `solo_horas` / `modo_cierre`, con la misma regla que la migración del servidor.
  static List<FormatoCierre> _formatosDe(Map<String, dynamic> j) {
    final soloHoras = j['solo_horas'] == true;
    final raw = j['formatos_cierre'];
    if (raw is List) {
      final out = [
        for (final f in FormatoCierre.values)
          if (raw.contains(f.wire) && (soloHoras || f != FormatoCierre.horas)) f,
      ];
      if (out.isNotEmpty) return out;
    }
    if (soloHoras) return const [FormatoCierre.horas];
    return switch (j['modo_cierre']) {
      'duracion' => const [FormatoCierre.inicioHoras],
      'elegir' => const [FormatoCierre.inicioHoras, FormatoCierre.inicioFin],
      _ => const [FormatoCierre.inicioFin],
    };
  }

  static List<ComidaOpcion> _comidaOpcionesDe(dynamic raw) => raw is List
      ? raw.map(ComidaOpcion.fromJson).whereType<ComidaOpcion>().toList()
      : _comidaOpcionesDefecto;
  /// La jornada la construye el servidor a partir de las tareas: sin fichaje manual.
  bool get jornadaDesdeTareas => soloHoras && controlJornada;

  factory SessionConfig.fromJson(Map<String, dynamic> j) => SessionConfig(
        capturaManualHoras: j['captura_manual_horas'] == true,
        mostrarInicioCierre: j['mostrar_inicio_cierre'] == true,
        mostrarHorasReales: j['mostrar_horas_reales'] == true,
        modoInicio: (j['modo_inicio'] ?? 'informada').toString(),
        modoCierre: (j['modo_cierre'] ?? 'hora').toString(),
        tramos: j['tramos'] == true,
        comida: (j['comida'] ?? 'siempre').toString(),
        comidaHoraDefectoMin: _horaMin(j['comida_hora_defecto']),
        minimoMostrarFin: j['minimo_mostrar_fin'] == true,
        firmaEnlaceDias: (j['firma_enlace_dias'] as num?)?.toInt() ?? 7,
        permisos: j['permisos'] is Map<String, dynamic>
            ? Permisos.fromJson(j['permisos'] as Map<String, dynamic>)
            : const Permisos(),
        soloHoras: j['solo_horas'] == true,
        controlJornada: j['control_jornada'] == true,
        comidaEnHoras: j['comida_en_horas'] != false, // v3.9: ausente → true
        formatosCierre: _formatosDe(j),                         // v3.10
        comidaOpciones: _comidaOpcionesDe(j['comida_opciones']), // v3.10
        tiempo: TiempoConfig.fromJson(j['tiempo']),             // v3.10
        actividadesDias:                                        // v3.11
            ((j['actividades_dias'] as num?)?.toInt() ?? 7).clamp(1, 366).toInt(),
  );

  /// "HH:MM" (contrato) → minutos. Tolera un número decimal (14.5 = 14:30).
  static int _horaMin(dynamic v) {
    const def = 14 * 60;
    if (v is num) return (v * 60).round().clamp(0, 24 * 60 - 1);
    final m = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(v?.toString() ?? '');
    if (m == null) return def;
    final h = int.parse(m[1]!), mi = int.parse(m[2]!);
    return (h > 23 || mi > 59) ? def : h * 60 + mi;
  }

  // Por si un /me viejo no trae config: por defecto, comportamiento actual
  // (timer con botón = detallista).
  static const fallback = SessionConfig(
    capturaManualHoras: false,
    mostrarInicioCierre: true,
  );
}
/// Estado de enrolamiento del dispositivo.
enum EnrollmentState { pending, approved, revoked, unknown }

EnrollmentState enrollmentFromString(String? s) => switch (s) {
      'pending' => EnrollmentState.pending,
      'approved' => EnrollmentState.approved,
      'revoked' => EnrollmentState.revoked,
      _ => EnrollmentState.unknown,
    };
