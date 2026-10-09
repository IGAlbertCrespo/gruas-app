import '../../shared/odoo_dt.dart';

/// Firmante de la obra (§6.1). `documento` llega siempre enmascarado;
/// `movil` en E.164 o null.
class Firmante {
  final int id;
  final String nombre;
  final String? documento;
  final String? movil;
  const Firmante({required this.id, required this.nombre, this.documento, this.movil});

  static Firmante? fromJson(dynamic v) {
    final j = _obj(v);
    final id = _int(j?['id']);
    if (j == null || id == null) return null;
    return Firmante(
      id: id,
      nombre: _txt(j['nombre']) ?? '',
      documento: _txt(j['documento']),
      movil: _txt(j['movil']),
    );
  }

  static List<Firmante> listFromJson(dynamic v) =>
      _lista(v).map(Firmante.fromJson).whereType<Firmante>().toList();
}

/// Bloques v3 del detalle de tarea (CONTRATO_API v3.1 §3 y §4.4).
///
/// Parseo tolerante: bloque ausente o `null` → `null` (o lista vacía).
/// En las tareas HIJA (recursos) el servidor envía `null` en obra, servicio,
/// recargo, salida, cargos y firma; solo `resumen_albaran` viene por tarea.

Map<String, dynamic>? _obj(dynamic v) => v is Map<String, dynamic> ? v : null;

String? _txt(dynamic v) {
  final s = v?.toString().trim();
  return (s == null || s.isEmpty) ? null : s;
}

double? _num(dynamic v) => v is num ? v.toDouble() : null;
int? _int(dynamic v) => v is num ? v.toInt() : null;
DateTime? _dt(dynamic v) => parseOdooDt(_txt(v));

List<Map<String, dynamic>> _lista(dynamic v) =>
    v is List ? v.whereType<Map<String, dynamic>>().toList() : const [];

/// Obra = `task.partner_id`.
class Obra {
  final int id;
  final String nombre;
  const Obra({required this.id, required this.nombre});

  static Obra? fromJson(dynamic v) {
    final j = _obj(v);
    final id = _int(j?['id']);
    if (j == null || id == null) return null;
    return Obra(id: id, nombre: _txt(j['nombre']) ?? '');
  }
}

/// Servicio principal (SOL de la tarea madre).
class ServicioPrincipal {
  final int? saleLineId;
  final String producto;
  final bool editable;
  const ServicioPrincipal({this.saleLineId, required this.producto, this.editable = false});

  static ServicioPrincipal? fromJson(dynamic v) {
    final j = _obj(v);
    if (j == null) return null;
    return ServicioPrincipal(
      saleLineId: _int(j['sale_line_id']),
      producto: _txt(j['producto']) ?? '',
      editable: j['editable'] == true,
    );
  }
}

/// Opción de una selección enviada por el servidor (la APP no hardcodea etiquetas).
class OpcionSel {
  final String value;
  final String label;
  const OpcionSel({required this.value, required this.label});

  static OpcionSel? fromJson(Map<String, dynamic> j) {
    final value = _txt(j['value']);
    if (value == null) return null;
    return OpcionSel(value: value, label: _txt(j['label']) ?? value);
  }
}

/// Valor actual + editable + opciones. Se usa para `recargo` y `salida`.
class Seleccion {
  final String value;
  final String label;
  final bool editable;
  final List<OpcionSel> opciones;
  const Seleccion({
    required this.value,
    required this.label,
    this.editable = false,
    this.opciones = const [],
  });

  /// Editable y con algo que elegir.
  bool get puedeCambiar => editable && opciones.length > 1;

  static Seleccion? fromJson(dynamic v) {
    final j = _obj(v);
    final value = _txt(j?['value']);
    if (j == null || value == null) return null;
    return Seleccion(
      value: value,
      label: _txt(j['label']) ?? value,
      editable: j['editable'] == true,
      opciones: _lista(j['opciones']).map(OpcionSel.fromJson).whereType<OpcionSel>().toList(),
    );
  }
}

/// Cargo extra (`project.task.cargo.extra`), solo tipo `none`.
class Cargo {
  final int id;
  final String producto;
  final double cantidad;
  final bool anulado;
  final String origen; // planificado | app
  final bool anulable;
  const Cargo({
    required this.id,
    required this.producto,
    required this.cantidad,
    required this.anulado,
    required this.origen,
    required this.anulable,
  });

  bool get deApp => origen == 'app';

  static Cargo? fromJson(Map<String, dynamic> j) {
    final id = _int(j['id']);
    if (id == null) return null;
    final cantidad = _num(j['cantidad']) ?? 0.0;
    return Cargo(
      id: id,
      producto: _txt(j['producto']) ?? '',
      cantidad: cantidad,
      anulado: j['anulado'] == true,
      origen: _txt(j['origen']) ?? 'planificado',
      anulable: j['anulable'] == true,
    );
  }

  static List<Cargo> listFromJson(dynamic v) =>
      _lista(v).map(Cargo.fromJson).whereType<Cargo>().toList();
}

class FirmaLote {
  final String codigo;
  final int nAlbaranes;
  const FirmaLote({required this.codigo, required this.nAlbaranes});

  static FirmaLote? fromJson(dynamic v) {
    final j = _obj(v);
    final codigo = _txt(j?['codigo']);
    if (j == null || codigo == null) return null;
    return FirmaLote(codigo: codigo, nAlbaranes: _int(j['n_albaranes']) ?? 0);
  }
}

/// Solicitud de firma por enlace. estado: pendiente | firmada | firmada_parcial | caducada | anulada.
class SolicitudFirma {
  final int id;
  final String estado;
  final String? url;
  final DateTime? expira;
  const SolicitudFirma({required this.id, required this.estado, this.url, this.expira});

  bool get viva => estado == 'pendiente';

  static SolicitudFirma? fromJson(dynamic v) {
    final j = _obj(v);
    final id = _int(j?['id']);
    if (j == null || id == null) return null;
    return SolicitudFirma(
      id: id,
      estado: _txt(j['estado']) ?? 'pendiente',
      url: _txt(j['url']),
      expira: _dt(j['expira']),
    );
  }
}

class FirmaEstado {
  final bool faltaFirma;
  final bool firmada;
  final FirmaLote? lote;
  final SolicitudFirma? solicitud;
  const FirmaEstado({
    this.faltaFirma = false,
    this.firmada = false,
    this.lote,
    this.solicitud,
  });

  static FirmaEstado? fromJson(dynamic v) {
    final j = _obj(v);
    if (j == null) return null;
    return FirmaEstado(
      faltaFirma: j['falta_firma'] == true,
      firmada: j['firmada'] == true,
      lote: FirmaLote.fromJson(j['lote']),
      solicitud: SolicitudFirma.fromJson(j['solicitud']),
    );
  }
}

class ComidaResumen {
  final DateTime? inicio;
  final DateTime? fin;
  final double? duracion;
  const ComidaResumen({this.inicio, this.fin, this.duracion});

  static ComidaResumen? fromJson(dynamic v) {
    final j = _obj(v);
    if (j == null) return null;
    return ComidaResumen(
      inicio: _dt(j['inicio']),
      fin: _dt(j['fin']),
      duracion: _num(j['duracion']),
    );
  }
}

/// Presentación del albarán ya resuelta por el servidor (§4.4).
/// La APP la pinta tal cual: NO recalcula. `horasTexto` se ignora (informativo).
class ResumenAlbaran {
  final String modo; // horario | horas | minimo | incidencia
  final DateTime? inicio;
  final DateTime? fin;
  final ComidaResumen? comida;
  final double? horas; // null con mínimo
  final bool servicioMinimo;
  final String? obsConductor;
  final String? obsCliente;
  const ResumenAlbaran({
    required this.modo,
    this.inicio,
    this.fin,
    this.comida,
    this.horas,
    this.servicioMinimo = false,
    this.obsConductor,
    this.obsCliente,
  });

  bool get esMinimo => modo == 'minimo';
  bool get esIncidencia => modo == 'incidencia';

  static ResumenAlbaran? fromJson(dynamic v) {
    final j = _obj(v);
    final modo = _txt(j?['modo']);
    if (j == null || modo == null) return null;
    return ResumenAlbaran(
      modo: modo,
      inicio: _dt(j['inicio']),
      fin: _dt(j['fin']),
      comida: ComidaResumen.fromJson(j['comida']),
      horas: _num(j['horas']),
      servicioMinimo: j['servicio_minimo'] == true,
      obsConductor: _txt(j['obs_conductor']),
      obsCliente: _txt(j['obs_cliente']),
    );
  }
}
/// Candidato a servicio principal (§5.3). `cambiaMinimo` no se usa en la APP:
/// el conductor no recibe avisos de mínimos.
class CandidatoServicio {
  final int lineId;
  final String producto;
  const CandidatoServicio({required this.lineId, required this.producto});

  static List<CandidatoServicio> listFromJson(dynamic v) => [
        for (final j in _lista(v))
          if (_int(j['line_id']) != null)
            CandidatoServicio(lineId: _int(j['line_id'])!, producto: _txt(j['producto']) ?? ''),
      ];
}

/// Complemento disponible para añadir (§5.4).
class Complemento {
  final int productId;
  final String producto;
  const Complemento({required this.productId, required this.producto});

  static List<Complemento> listFromJson(dynamic v) => [
        for (final j in _lista(v))
          if (_int(j['product_id']) != null)
            Complemento(productId: _int(j['product_id'])!, producto: _txt(j['producto']) ?? ''),
      ];
}
/// Albarán pendiente de firma de la misma obra (§6.4).
class PendienteFirma {
  final int id;
  final String? albaran;
  final DateTime? fecha;
  final String? servicio;
  final List<Cargo> cargos;
  final String? recargo;
  final String? salida;
  final ResumenAlbaran? resumenAlbaran;
  const PendienteFirma({
    required this.id,
    this.albaran,
    this.fecha,
    this.servicio,
    this.cargos = const [],
    this.recargo,
    this.salida,
    this.resumenAlbaran,
  });

  /// Acepta objeto ({producto} / {label}) o texto.
  static String? _etiqueta(dynamic v, String clave) =>
      v is Map ? _txt(v[clave]) : _txt(v);

  static List<PendienteFirma> listFromJson(dynamic v) => [
        for (final j in _lista(v))
          if (_int(j['id']) != null)
            PendienteFirma(
              id: _int(j['id'])!,
              albaran: _txt(j['albaran']),
              fecha: _dt(j['fecha']),
              servicio: _etiqueta(j['servicio'], 'producto'),
              cargos: Cargo.listFromJson(j['cargos']),
              recargo: _etiqueta(j['recargo'], 'label'),
              salida: _etiqueta(j['salida'], 'label'),
              resumenAlbaran: ResumenAlbaran.fromJson(j['resumen_albaran']),
            ),
      ];
}

/// Respuesta de POST /firma/solicitudes (§6.6).
class SolicitudCreada {
  final int id;
  final String url;
  final DateTime? expira;
  final String? mensaje;
  const SolicitudCreada({required this.id, required this.url, this.expira, this.mensaje});

  static SolicitudCreada? fromJson(dynamic v) {
    final j = _obj(v);
    final id = _int(j?['id']);
    final url = _txt(j?['url']);
    if (j == null || id == null || url == null) return null;
    return SolicitudCreada(id: id, url: url, expira: _dt(j['expira']), mensaje: _txt(j['mensaje']));
  }
}