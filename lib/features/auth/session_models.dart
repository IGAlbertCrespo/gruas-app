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

class SessionConfig {
  final bool capturaManualHoras;
  final bool mostrarInicioCierre;
  final bool mostrarHorasReales;
  /// informada | planificada. En planificada el servidor ignora `informada`.
  final String modoInicio;
  /// hora | duracion. El selector de duración va en 4.3.
  final String modoCierre;
  final bool tramos;

  const SessionConfig({
    required this.capturaManualHoras,
    required this.mostrarInicioCierre,
    this.mostrarHorasReales = false,
    this.modoInicio = 'informada',
    this.modoCierre = 'hora',
    this.tramos = false,
  });

  bool get inicioPlanificado => modoInicio == 'planificada';

  factory SessionConfig.fromJson(Map<String, dynamic> j) => SessionConfig(
        capturaManualHoras: j['captura_manual_horas'] == true,
        mostrarInicioCierre: j['mostrar_inicio_cierre'] == true,
        mostrarHorasReales: j['mostrar_horas_reales'] == true,
        modoInicio: (j['modo_inicio'] ?? 'informada').toString(),
        modoCierre: (j['modo_cierre'] ?? 'hora').toString(),
        tramos: j['tramos'] == true,
      );

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
