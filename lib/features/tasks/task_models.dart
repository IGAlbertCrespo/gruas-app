import '../../shared/odoo_dt.dart';
import 'task_v3_models.dart';
export 'task_v3_models.dart';


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
  /// Etiqueta del tipo de tarea interna (solo no facturables), p. ej. "Taller".
  final String? tipoInterna;
  /// servicio | no_facturable. Ausente en respuestas v1 → servicio.
  final String tipo;
  /// En no facturables el servidor iguala cerrada = completada.
  final bool completada;

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
    this.tipo = 'servicio',
    this.completada = false,
    this.tipoInterna,
  });
  bool get esNoFacturable => tipo == 'no_facturable';
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
        tipo: (j['tipo'] ?? 'servicio').toString(),
        completada: j['completada'] == true ||
            ((j['tipo']?.toString() == 'no_facturable') && j['cerrada'] == true),
        tipoInterna: _recargo(j['tipo_interna']),   // mismo formato {value, label}
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
  final String? obsAlbaran, obsCliente, identificacionSig, dniSig;
  final bool aplicarMinimo, hasSignature;
  final int servicioMinimo;
  final double horasReales, horasFacturar, pausaServicio;
  final double? cantidadPedida;
  final DateTime? firmaHora;
  final String? signatureBase64;
  const Worksheet({
    this.obsAlbaran,
    this.obsCliente,
    this.identificacionSig,
    this.dniSig,
    this.aplicarMinimo = false,
    this.hasSignature = false,
    this.servicioMinimo = 0,
    this.horasReales = 0,
    this.horasFacturar = 0,
    this.pausaServicio = 0,
    this.cantidadPedida,
    this.firmaHora,
    this.signatureBase64,
  });
  factory Worksheet.fromJson(Map<String, dynamic> j) => Worksheet(
        obsAlbaran: j['obs_albaran']?.toString(),
        obsCliente: j['obs_cliente']?.toString(),
        identificacionSig: j['identificacion_sig']?.toString(),
        dniSig: j['dni_sig']?.toString(),
        aplicarMinimo: j['aplicar_minimo'] == true,
        hasSignature: j['has_signature'] == true,
        servicioMinimo: ((j['servicio_minimo'] ?? 0) as num).round(),
        horasReales: (j['horas_reales'] ?? 0).toDouble(),
        horasFacturar: (j['horas_facturar'] ?? 0).toDouble(),
        pausaServicio: (j['pausa_servicio'] ?? 0).toDouble(),
        cantidadPedida: j['cantidad_pedida'] == null ? null : (j['cantidad_pedida']).toDouble(),
        firmaHora: parseOdooDt(j['firma_hora']?.toString()),
        signatureBase64: j['signature']?.toString(),
      );
}
class Recurso {
  final int id;
  final String recurso;
  final String? empleado;
  final bool esMio;
  final bool iniciada;
  final bool cerrada;
  final bool hayTramoAbierto;
  final double horasFacturar;
  final double servicioMinimo;
  final bool incidencia;
  final DateTime? aperturaInformada;
  final bool aplicarMinimo;
  /// v3 (propuesta contrato: resumen_albaran por recurso).
  final ResumenAlbaran? resumenAlbaran;

  const Recurso({
    required this.id, required this.recurso, this.empleado,
    required this.esMio, required this.iniciada, required this.cerrada,
    required this.hayTramoAbierto, required this.horasFacturar,
    required this.servicioMinimo, required this.incidencia,
    this.aperturaInformada, required this.aplicarMinimo, this.resumenAlbaran,
  });

  factory Recurso.fromJson(Map<String, dynamic> j) => Recurso(
        id: (j['id'] as num).toInt(),
        recurso: j['recurso']?.toString() ?? '',
        empleado: j['empleado']?.toString(),
        esMio: j['es_mio'] == true,
        iniciada: j['iniciada'] == true,
        cerrada: j['cerrada'] == true,
        hayTramoAbierto: j['hay_tramo_abierto'] == true,
        horasFacturar: (j['horas_facturar'] as num?)?.toDouble() ?? 0.0,
        servicioMinimo: (j['servicio_minimo'] as num?)?.toDouble() ?? 0.0,
        incidencia: j['incidencia'] == true,
        aperturaInformada: parseOdooDt(j['apertura_informada']?.toString()),
        aplicarMinimo: j['aplicar_minimo'] == true,
        resumenAlbaran: ResumenAlbaran.fromJson(j['resumen_albaran']),
      );
}


class Accesorio {
  final String recurso;
  final num cantidad;

  const Accesorio({required this.recurso, required this.cantidad});

  factory Accesorio.fromJson(Map<String, dynamic> j) => Accesorio(
        recurso: j['recurso']?.toString() ?? '',
        cantidad: (j['cantidad'] as num?) ?? 0,
      );
}

class Tramo {
  final DateTime? inicio;
  final DateTime? fin;
  final double duracionHoras;

  const Tramo({this.inicio, this.fin, required this.duracionHoras});

  bool get abierto => fin == null;

  factory Tramo.fromJson(Map<String, dynamic> j) => Tramo(
        inicio: parseOdooDt(j['inicio']?.toString()),
        fin: parseOdooDt(j['fin']?.toString()),
        duracionHoras: (j['duracion_horas'] as num?)?.toDouble() ?? 0.0,
      );
}

class TaskDetail extends TaskSummary {
  final Address carga;
  final Address descarga;
  final Worksheet worksheet;
  final List<Accesorio> accesorios;
  final DateTime? aperturaHora;
  final DateTime? aperturaInformada;
  final DateTime? cierreHora;
  final DateTime? cierreInformada;
  final String? notasChofer;
  final String? descripcionServicio;
  final List<Tramo> tramos;
  final List<Recurso> recursos;
  final DateTime? fechaCompletada;
  final Deca? deca;
  // --- v3 (CONTRATO v3.1). En tareas hija todo null salvo resumenAlbaran ---
  final Obra? obra;
  final ServicioPrincipal? servicio;
  final Seleccion? recargoSel;   // `recargo` ya existe en TaskSummary (String, de tipo_recargo)
  final Seleccion? salidaSel;
  final List<Cargo> cargos;
  final FirmaEstado? firma;
  final ResumenAlbaran? resumenAlbaran;

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
    super.cerrada,
    super.tipo,
    super.completada,
    super.tipoInterna,
    required this.carga,
    required this.descarga,
    required this.worksheet,
    this.aperturaHora,
    this.aperturaInformada,
    this.cierreHora,
    this.cierreInformada,
    this.notasChofer,
    this.descripcionServicio,
    this.fechaCompletada,
    this.accesorios = const [],
    this.tramos = const [],
    this.recursos = const [],
    this.deca,
    this.obra,
    this.servicio,
    this.recargoSel,
    this.salidaSel,
    this.cargos = const [],
    this.firma,
    this.resumenAlbaran,

  });

  bool get hayTramoAbierto => tramos.any((t) => t.abierto);
  bool get tieneTramos => tramos.isNotEmpty;

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
      cerrada: s.cerrada,
      tipo: s.tipo,
      completada: s.completada,
      tipoInterna: s.tipoInterna,
      deca: Deca.fromJson(j['deca']),
      obra: Obra.fromJson(j['obra']),
      servicio: ServicioPrincipal.fromJson(j['servicio']),
      recargoSel: Seleccion.fromJson(j['recargo']),
      salidaSel: Seleccion.fromJson(j['salida']),
      cargos: Cargo.listFromJson(j['cargos']),
      firma: FirmaEstado.fromJson(j['firma']),
      resumenAlbaran: ResumenAlbaran.fromJson(j['resumen_albaran']),
      fechaCompletada: parseOdooDt(j['fecha_completada']?.toString()),
      carga: Address.fromJson((j['carga'] ?? {}) as Map<String, dynamic>),
      descarga: Address.fromJson((j['descarga'] ?? {}) as Map<String, dynamic>),
      worksheet: Worksheet.fromJson(
          (j['worksheet'] as Map<String, dynamic>?) ?? const <String, dynamic>{}),
      accesorios: ((j['accesorios'] ?? []) as List)
          .map((e) => Accesorio.fromJson(e as Map<String, dynamic>))
          .toList(),
      tramos: ((j['tramos'] ?? []) as List)
          .map((e) => Tramo.fromJson(e as Map<String, dynamic>))
          .toList(),
      aperturaHora: parseOdooDt(apertura['hora_sistema']?.toString()),
      aperturaInformada: parseOdooDt(apertura['hora_informada']?.toString()),
      cierreHora: parseOdooDt(cierre['hora_sistema']?.toString()),
      cierreInformada: parseOdooDt(cierre['hora_informada']?.toString()),
      notasChofer: j['notas_chofer']?.toString(),
      descripcionServicio: j['descripcion_servicio']?.toString(),
      recursos: ((j['recursos'] ?? []) as List)
          .map((e) => Recurso.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
/// DeCA de la tarea. El ESTADO lo calcula el servidor (única fuente de verdad):
/// no_requiere | pendiente | vigente | externo | anulado.
class Deca {
  final String estado;
  final String? url;
  final String? urlExterno;

  const Deca({required this.estado, this.url, this.urlExterno});

  static Deca? fromJson(dynamic j) {
    if (j is! Map) return null;
    final estado = j['estado']?.toString() ?? 'no_requiere';
    final url = _s(j['url']);
    // "vigente" sin URL no se puede pintar: se trata como pendiente.
    return Deca(
      estado: (estado == 'vigente' && url == null) ? 'pendiente' : estado,
      url: url,
      urlExterno: _s(j['url_externo']),
    );
  }

  static String? _s(dynamic v) {
    final s = v?.toString().trim();
    return (s == null || s.isEmpty || s == 'false') ? null : s;
  }
}