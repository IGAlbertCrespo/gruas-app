class TaskStage {
  final int id;
  final String name;
  final String? alias;
  const TaskStage(this.id, this.name, this.alias);
  factory TaskStage.fromJson(Map<String, dynamic> j) =>
      TaskStage(j['id'] as int? ?? 0, j['name']?.toString() ?? '', j['alias']?.toString());
}

class TaskSummary {
  final int id;
  final String name;
  final TaskStage stage;
  final DateTime? fechaServicio;
  final DateTime? horaSalida;
  final String? partner;
  final String? vehicle;
  final String? employee;
  final String? cargaPoblacion;
  final String? descargaPoblacion;
  final String? albaran;
  final bool hasSignature;

  const TaskSummary({
    required this.id,
    required this.name,
    required this.stage,
    this.fechaServicio,
    this.horaSalida,
    this.partner,
    this.vehicle,
    this.employee,
    this.cargaPoblacion,
    this.descargaPoblacion,
    this.albaran,
    this.hasSignature = false,
  });

  static String? _nm(dynamic v) => v is Map ? v['name']?.toString() : null;

  factory TaskSummary.fromJson(Map<String, dynamic> j) => TaskSummary(
        id: j['id'] as int,
        name: j['name']?.toString() ?? '',
        stage: TaskStage.fromJson((j['stage'] ?? {}) as Map<String, dynamic>),
        fechaServicio: DateTime.tryParse(j['fecha_servicio']?.toString() ?? ''),
        horaSalida: DateTime.tryParse(j['hora_salida']?.toString() ?? ''),
        partner: _nm(j['partner']),
        vehicle: _nm(j['vehicle']),
        employee: _nm(j['employee']),
        cargaPoblacion: j['carga_poblacion']?.toString(),
        descargaPoblacion: j['descarga_poblacion']?.toString(),
        albaran: j['albaran']?.toString(),
        hasSignature: j['has_signature'] == true,
      );
}

class Address {
  final String? direccion, poblacion, codigoPostal, contacto, telefono, url;
  const Address({this.direccion, this.poblacion, this.codigoPostal, this.contacto, this.telefono, this.url});
  factory Address.fromJson(Map<String, dynamic> j) => Address(
        direccion: j['direccion']?.toString(),
        poblacion: j['poblacion']?.toString(),
        codigoPostal: j['codigo_postal']?.toString(),
        contacto: j['contacto']?.toString(),
        telefono: j['telefono']?.toString(),
        url: j['url']?.toString(),
      );
}

class Worksheet {
  final String? obsAlbaran, obsCliente, identificacionSig;
  final bool cambioProducto, aplicarMinimo, hasSignature;
  final double horasReales, horasFacturar;
  const Worksheet({
    this.obsAlbaran,
    this.obsCliente,
    this.identificacionSig,
    this.cambioProducto = false,
    this.aplicarMinimo = false,
    this.hasSignature = false,
    this.horasReales = 0,
    this.horasFacturar = 0,
  });
  factory Worksheet.fromJson(Map<String, dynamic> j) => Worksheet(
        obsAlbaran: j['obs_albaran']?.toString(),
        obsCliente: j['obs_cliente']?.toString(),
        identificacionSig: j['identificacion_sig']?.toString(),
        cambioProducto: j['cambio_producto'] == true,
        aplicarMinimo: j['aplicar_minimo'] == true,
        hasSignature: j['has_signature'] == true,
        horasReales: (j['horas_reales'] ?? 0).toDouble(),
        horasFacturar: (j['horas_facturar'] ?? 0).toDouble(),
      );
}

class TaskDetail extends TaskSummary {
  final Address carga;
  final Address descarga;
  final Worksheet worksheet;

  const TaskDetail({
    required super.id,
    required super.name,
    required super.stage,
    super.fechaServicio,
    super.horaSalida,
    super.partner,
    super.vehicle,
    super.employee,
    super.albaran,
    super.hasSignature,
    required this.carga,
    required this.descarga,
    required this.worksheet,
  });

  factory TaskDetail.fromJson(Map<String, dynamic> j) {
    final s = TaskSummary.fromJson(j);
    return TaskDetail(
      id: s.id,
      name: s.name,
      stage: s.stage,
      fechaServicio: s.fechaServicio,
      horaSalida: s.horaSalida,
      partner: s.partner,
      vehicle: s.vehicle,
      employee: s.employee,
      albaran: s.albaran,
      hasSignature: s.hasSignature,
      carga: Address.fromJson((j['carga'] ?? {}) as Map<String, dynamic>),
      descarga: Address.fromJson((j['descarga'] ?? {}) as Map<String, dynamic>),
      worksheet: Worksheet.fromJson((j['worksheet'] ?? {}) as Map<String, dynamic>),
    );
  }
}
