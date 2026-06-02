import '../../shared/odoo_dt.dart';
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
  final String? recargo; // etiqueta del tipo de recargo, no editable
  final bool hasSignature;
  final bool iniciada;
  final bool cerrada;

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
    this.recargo,
    this.hasSignature = false,
    this.iniciada = false,
    this.cerrada = false,
  });

  static String? _nm(dynamic v) => v is Map ? v['name']?.toString() : null;
  static String? _recargo(dynamic v) => v is Map ? v['label']?.toString() : null;

  factory TaskSummary.fromJson(Map<String, dynamic> j) => TaskSummary(
        id: j['id'] as int,
        name: j['name']?.toString() ?? '',
        stage: TaskStage.fromJson((j['stage'] ?? {}) as Map<String, dynamic>),
        fechaServicio: parseOdooDt(j['fecha_servicio']?.toString()),
        horaSalida: parseOdooDt(j['hora_salida']?.toString()),
        partner: _nm(j['partner']),
        vehicle: _nm(j['vehicle']),
        employee: _nm(j['employee']),
        cargaPoblacion: j['carga_poblacion']?.toString(),
        descargaPoblacion: j['descarga_poblacion']?.toString(),
        albaran: j['albaran']?.toString(),
        recargo: _recargo(j['tipo_recargo']),
        hasSignature: j['has_signature'] == true,
        iniciada: j['iniciada'] == true,
        cerrada: j['cerrada'] == true,
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
  final bool aplicarMinimo, hasSignature;
  final int servicioMinimo;
  final double horasReales, horasFacturar;
  final double? cantidadPedida;
  final DateTime? firmaHora;
  const Worksheet({
    this.obsAlbaran,
    this.obsCliente,
    this.identificacionSig,
    this.aplicarMinimo = false,
    this.hasSignature = false,
    this.servicioMinimo = 0,
    this.horasReales = 0,
    this.horasFacturar = 0,
    this.cantidadPedida,
    this.firmaHora,
  });
  factory Worksheet.fromJson(Map<String, dynamic> j) => Worksheet(
        obsAlbaran: j['obs_albaran']?.toString(),
        obsCliente: j['obs_cliente']?.toString(),
        identificacionSig: j['identificacion_sig']?.toString(),
        aplicarMinimo: j['aplicar_minimo'] == true,
        hasSignature: j['has_signature'] == true,
        servicioMinimo: ((j['servicio_minimo'] ?? 0) as num).round(),
        horasReales: (j['horas_reales'] ?? 0).toDouble(),
        horasFacturar: (j['horas_facturar'] ?? 0).toDouble(),
        cantidadPedida: j['cantidad_pedida'] == null ? null : (j['cantidad_pedida']).toDouble(),
        firmaHora: parseOdooDt(j['firma_hora']?.toString()),
      );
}

class TaskDetail extends TaskSummary {
  final Address carga;
  final Address descarga;
  final Worksheet worksheet;
  final DateTime? aperturaHora;
  final DateTime? aperturaInformada;
  final DateTime? cierreHora;
  final DateTime? cierreInformada;
  final String? notasChofer;
  final String? descripcionServicio;

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
    super.recargo,
    super.hasSignature,
    super.iniciada,
    required this.carga,
    required this.descarga,
    required this.worksheet,
    this.aperturaHora,
    this.aperturaInformada,
    this.cierreHora,
    this.cierreInformada,
    this.notasChofer,
    this.descripcionServicio,
  });

  factory TaskDetail.fromJson(Map<String, dynamic> j) {
    final s = TaskSummary.fromJson(j);
    final apertura = (j['apertura'] ?? {}) as Map<String, dynamic>;
    final cierre = (j['cierre'] ?? {}) as Map<String, dynamic>;
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
      recargo: s.recargo,
      hasSignature: s.hasSignature,
      iniciada: s.iniciada,
      carga: Address.fromJson((j['carga'] ?? {}) as Map<String, dynamic>),
      descarga: Address.fromJson((j['descarga'] ?? {}) as Map<String, dynamic>),
      worksheet: Worksheet.fromJson((j['worksheet'] ?? {}) as Map<String, dynamic>),
      aperturaHora: parseOdooDt(apertura['hora_sistema']?.toString()),
      aperturaInformada: parseOdooDt(apertura['hora_informada']?.toString()),
      cierreHora: parseOdooDt(cierre['hora_sistema']?.toString()),
      cierreInformada: parseOdooDt(cierre['hora_informada']?.toString()),
      notasChofer: j['notas_chofer']?.toString(),
      descripcionServicio: j['descripcion_servicio']?.toString(),
    );
  }
}
