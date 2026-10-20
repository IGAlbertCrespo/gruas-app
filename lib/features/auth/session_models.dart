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
      editarRecargo, editarSalida, firmaDiferida;
  const Permisos({
    this.cambiarServicio = false,
    this.anadirCargos = false,
    this.anularCargos = false,
    this.editarRecargo = false,
    this.editarSalida = false,
    this.firmaDiferida = false,
  });

  factory Permisos.fromJson(Map<String, dynamic> j) => Permisos(
        cambiarServicio: j['cambiar_servicio'] == true,
        anadirCargos: j['anadir_cargos'] == true,
        anularCargos: j['anular_cargos'] == true,
        editarRecargo: j['editar_recargo'] == true,
        editarSalida: j['editar_salida'] == true,
        firmaDiferida: j['firma_diferida'] == true,
      );
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
  });

  bool get inicioPlanificado => modoInicio == 'planificada';
  bool get cierrePorDuracion => modoCierre == 'duracion';
  bool get cierreElegir => modoCierre == 'elegir';
  bool get comidaNunca => comida == 'nunca';
  /// ¿Se pregunta la comida en un cierre por horas totales? (v3.9)
  bool get preguntaComidaEnHoras => !comidaNunca && comidaEnHoras;
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
