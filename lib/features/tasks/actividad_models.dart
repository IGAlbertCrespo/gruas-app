/// v3.11 §4.8 — Tareas creadas por el conductor: catálogo de actividades y
/// vehículos disponibles en la APP.
library;

/// Actividad del catálogo (línea del pedido interno). Se elige por la descripción.
class Actividad {
  final int lineId;
  final String descripcion;

  const Actividad({required this.lineId, required this.descripcion});

  static Actividad? fromJson(dynamic j) {
    if (j is! Map) return null;
    final id = (j['line_id'] as num?)?.toInt();
    if (id == null) return null;
    return Actividad(lineId: id, descripcion: j['descripcion']?.toString() ?? '');
  }

  static List<Actividad> listFromJson(dynamic raw) => raw is List
      ? raw.map(Actividad.fromJson).whereType<Actividad>().toList()
      : const [];
}

/// Vehículo con "Disponible en APP". `habitual`: el que tiene al conductor asignado.
class VehiculoApp {
  final int id;
  final String nombre;
  final String? matricula;
  final bool habitual;

  const VehiculoApp({
    required this.id,
    required this.nombre,
    this.matricula,
    this.habitual = false,
  });

  bool get _tieneMatricula => (matricula ?? '').trim().isNotEmpty;

  /// Texto principal: la matrícula (petición de TSME); si no hay, el nombre.
  String get principal => _tieneMatricula ? matricula!.trim() : nombre;

  /// Texto secundario (gris, recortable): el nombre si la matrícula va delante.
  String? get secundario => _tieneMatricula ? nombre : null;

  static VehiculoApp? fromJson(dynamic j) {
    if (j is! Map) return null;
    final id = (j['id'] as num?)?.toInt();
    if (id == null) return null;
    return VehiculoApp(
      id: id,
      nombre: j['nombre']?.toString() ?? '',
      matricula: j['matricula']?.toString(),
      habitual: j['habitual'] == true,
    );
  }

  /// Habituales primero; el resto, en el orden del servidor.
  static List<VehiculoApp> listFromJson(dynamic raw) {
    if (raw is! List) return const [];
    final todos = raw.map(VehiculoApp.fromJson).whereType<VehiculoApp>().toList();
    return [...todos.where((v) => v.habitual), ...todos.where((v) => !v.habitual)];
  }
}