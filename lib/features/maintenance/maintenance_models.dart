/// Modelos de la feature de averías de taller (maintenance.request).
/// Contrato: GET /maintenance/catalog, POST /maintenance/requests,
/// GET /maintenance/requests, POST /maintenance/sync.

/// Tipo de avería (maintenance.tipo.averia).
class TipoAveria {
  final int id;
  final String name;
  const TipoAveria({required this.id, required this.name});

  factory TipoAveria.fromJson(Map<String, dynamic> j) => TipoAveria(
        id: (j['id'] ?? 0) as int,
        name: (j['name'] ?? '').toString(),
      );
}

/// Vehículo reportable (fleet.vehicle con x_app = True).
class VehiculoTaller {
  final int id;
  final String name;
  final String matricula;
  const VehiculoTaller({required this.id, required this.name, required this.matricula});

  factory VehiculoTaller.fromJson(Map<String, dynamic> j) => VehiculoTaller(
        id: (j['id'] ?? 0) as int,
        name: (j['name'] ?? '').toString(),
        matricula: (j['matricula'] ?? '').toString(),
      );

  /// Etiqueta para el desplegable: "Grúa 03 · 1234-ABC".
  String get label => matricula.trim().isEmpty ? name : '$name · $matricula';
}

/// Precarga del formulario de alta (cacheable para offline).
class MaintenanceCatalog {
  final bool puedeReportar;
  final bool puedeInmovilizar;
  final List<TipoAveria> tiposAveria;
  final List<VehiculoTaller> vehiculos;

  const MaintenanceCatalog({
    required this.puedeReportar,
    required this.puedeInmovilizar,
    required this.tiposAveria,
    required this.vehiculos,
  });

  factory MaintenanceCatalog.fromJson(Map<String, dynamic> j) {
    final tipos = (j['tipos_averia'] ?? []) as List;
    final vehs = (j['vehiculos'] ?? []) as List;
    return MaintenanceCatalog(
      puedeReportar: j['puede_reportar'] == true,
      puedeInmovilizar: j['puede_inmovilizar'] == true,
      tiposAveria: tipos.map((e) => TipoAveria.fromJson(e as Map<String, dynamic>)).toList(),
      vehiculos: vehs.map((e) => VehiculoTaller.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }
}

/// Resumen de una avería para el histórico del chófer.
///
/// NOTA DE INTEGRACIÓN: el md describe los campos del item de
/// `GET /maintenance/requests` (vehículo, matrícula, tipo, descripción, km,
/// fecha, etapa, cerrada, precisa_inmovilizacion, offline_uuid) pero no fija el
/// nombre EXACTO de cada clave JSON. El parseo es tolerante (prueba varias
/// claves) hasta confirmar los nombres reales contra `maintenance_api.py`.
class MaintenanceRequestSummary {
  final int? id;
  final String? name;
  final String? vehiculo;
  final String? matricula;
  final String? tipo;
  final String descripcion;
  final int? km;
  final String? fecha;
  final String? etapa;
  final bool cerrada;
  final bool precisaInmovilizacion;
  final String? offlineUuid;

  const MaintenanceRequestSummary({
    this.id,
    this.name,
    this.vehiculo,
    this.matricula,
    required this.descripcion,
    this.km,
    this.tipo,
    this.fecha,
    this.etapa,
    this.cerrada = false,
    this.precisaInmovilizacion = false,
    this.offlineUuid,
  });

  factory MaintenanceRequestSummary.fromJson(Map<String, dynamic> j) {
    String? pick(List<String> keys) {
      for (final k in keys) {
        final v = j[k];
        if (v != null && v.toString().isNotEmpty) return v.toString();
      }
      return null;
    }

    int? pickInt(List<String> keys) {
      for (final k in keys) {
        final v = j[k];
        if (v is int) return v;
        if (v != null) {
          final p = int.tryParse(v.toString());
          if (p != null) return p;
        }
      }
      return null;
    }

    return MaintenanceRequestSummary(
      id: pickInt(['id']),
      name: pick(['name', 'display_name']),
      vehiculo: pick(['vehiculo', 'vehicle', 'vehicle_name']),
      matricula: pick(['matricula', 'license_plate', 'matricula_vehiculo']),
      tipo: pick(['tipo', 'tipo_averia', 'tipo_averia_name', 'type']),
      descripcion: pick(['descripcion', 'description']) ?? '',
      km: pickInt(['km']),
      fecha: pick(['fecha', 'fecha_deteccion', 'date']),
      etapa: pick(['etapa', 'stage', 'stage_name']),
      cerrada: j['cerrada'] == true || j['closed'] == true,
      precisaInmovilizacion: j['precisa_inmovilizacion'] == true,
      offlineUuid: pick(['offline_uuid']),
    );
  }
}