import 'package:dio/dio.dart';

/// Solo QA. Se activa con `--dart-define=MOCK_V3=true` y nunca en producción
/// (ver `dioProvider` en core/providers.dart).
const bool kMockV3 = bool.fromEnvironment('MOCK_V3');

/// Completa las respuestas de un servidor que aún no es v3 con los bloques del
/// CONTRATO v3.3, para desarrollar pantallas antes de que el backend esté listo.
///
/// Regla: solo AÑADE claves AUSENTES (`putIfAbsent`). En cuanto el servidor
/// envía la clave (aunque sea `null`, como en las tareas hija), manda el servidor.
///
/// Las acciones v3 (recargo, salida, servicio, cargos) se simulan en memoria
/// mientras la APP está abierta y se convierten en `GET /tasks/<id>` para que
/// la respuesta sea el detalle real completado.
class MockV3Interceptor extends Interceptor {
  static final _close = RegExp(r'/tasks/\d+/close$');
  static final _selRe = RegExp(r'/tasks/(\d+)/(recargo|salida)$');
  static final _serviciosRe = RegExp(r'/tasks/(\d+)/servicios$');
  static final _servicioRe = RegExp(r'/tasks/(\d+)/servicio$');
  static final _complementosRe = RegExp(r'/tasks/(\d+)/complementos$');
  static final _cargosRe = RegExp(r'/tasks/(\d+)/cargos$');
  static final _anularRe = RegExp(r'/tasks/(\d+)/cargos/(\d+)/anular$');
  static final _firmantesRe = RegExp(r'/tasks/(\d+)/firmantes$');
  static final _signatureRe = RegExp(r'/tasks/(\d+)/signature$');
  static final _pendientesRe = RegExp(r'/tasks/(\d+)/pendientes-firma$');
  static final _finalizeRe = RegExp(r'/tasks/(\d+)/finalize$');
  static final _solicitudesRe = RegExp(r'/firma/solicitudes$');
  static final _loteRe = RegExp(r'/firma/lote$');

  static const _candidatos = [
    {'line_id': 9001, 'producto': 'Camión grúa 100 t (mock)', 'cambia_minimo': false},
    {'line_id': 9002, 'producto': 'Grúa móvil 200 t (mock)', 'cambia_minimo': true},
  ];
  static const _catalogo = [
    {'product_id': 77, 'producto': 'Balancín'},
    {'product_id': 78, 'producto': 'Ventosa'},
    {'product_id': 79, 'producto': 'Eslingas'},
  ];

  /// Recargo/salida elegidos: {taskId: {campo: value}}.
  final Map<int, Map<String, String>> _sel = {};

  /// Servicio principal elegido: {taskId: producto}.
  final Map<int, String> _servicio = {};

  /// Cargos simulados por tarea (se inicializan con los por defecto).
  final Map<int, List<Map<String, dynamic>>> _cargos = {};
  int _nextCargoId = 900;

  /// Firmantes simulados (por obra no se distingue: basta para QA).
  /// `documento` aquí se guarda completo; hacia la APP se enmascara.
  final List<Map<String, dynamic>> _firmantes = [
    {'id': 5012, 'nombre': 'Joan Puig (mock)', 'documento': '12345678Z', 'movil': '+34600111222'},
    {'id': 5013, 'nombre': 'Marta Soler (mock)', 'documento': 'X1234567L', 'movil': null},
  ];
  int _nextFirmanteId = 6000;

  /// Firma diferida simulada (el servidor v2 no la conoce).
  final Set<int> _diferidas = {};
  final Map<int, Map<String, dynamic>> _solicitudes = {};
  final Set<int> _firmadasLote = {};
  int _nextSolicitudId = 50;
  int _nextLote = 1;

  /// Dos albaranes ficticios de la misma obra para probar la firma en lote.
  static const _pendientesFicticios = [990001, 990002];

  static String _utcStr(DateTime d) {
    String t(int n) => n.toString().padLeft(2, '0');
    final u = d.toUtc();
    return '${u.year}-${t(u.month)}-${t(u.day)} ${t(u.hour)}:${t(u.minute)}:${t(u.second)}';
  }

  Map<String, dynamic> _nuevaSolicitud(int taskId) {
    final id = _nextSolicitudId++;
    final s = <String, dynamic>{
      'id': id,
      'estado': 'pendiente',
      'url': 'https://mock.invalid/firma/tok$id',
      'expira': _utcStr(DateTime.now().add(const Duration(days: 7))),
    };
    _solicitudes[taskId] = s;
    return s;
  }

  Map<String, dynamic>? _firmaDe(int? id, bool firmadaServidor) => {
        'falta_firma': id != null && _diferidas.contains(id),
        'firmada': firmadaServidor || (id != null && _firmadasLote.contains(id)),
        'lote': id != null && _firmadasLote.contains(id)
            ? {'codigo': 'LOTE/2026/MOCK', 'n_albaranes': _firmadasLote.length}
            : null,
        'solicitud': id != null ? _solicitudes[id] : null,
      };

  static Map<String, dynamic> _firmanteApp(Map<String, dynamic> f) {
    final d = (f['documento'] ?? '') as String;
    return {
      'id': f['id'],
      'nombre': f['nombre'],
      'documento': d.length > 4 ? '****${d.substring(d.length - 4)}' : d,
      'movil': f['movil'],
    };
  }

  List<Map<String, dynamic>> _cargosDe(int id) => _cargos.putIfAbsent(id, () => [
        {'id': 301, 'producto': 'Balancín', 'cantidad': 1.0,
         'anulado': false, 'origen': 'planificado', 'anulable': true},
      ]);

  // ─────────────────────────── Peticiones ───────────────────────────

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final d = options.data;
    final post = options.method == 'POST';
    final path = options.path;

    if (post && _close.hasMatch(path) && d is Map<String, dynamic> && d.containsKey('modo_cierre')) {
      options.data = _closeV3aV2(d);
      return handler.next(options);
    }

    // POST recargo|salida → se recuerda y se pide el detalle.
    var m = _selRe.firstMatch(path);
    if (post && m != null && d is Map && d['tipo'] is String) {
      _sel.putIfAbsent(int.parse(m[1]!), () => {})[m[2]!] = d['tipo'] as String;
      return handler.next(_aDetalle(options, m));
    }

    // GET candidatos de servicio.
    m = _serviciosRe.firstMatch(path);
    if (!post && m != null) return handler.resolve(_ok(options, _candidatos));

    // POST servicio.
    m = _servicioRe.firstMatch(path);
    if (post && m != null && d is Map) {
      final cand = _candidatos.where((c) => c['line_id'] == d['line_id']).firstOrNull;
      if (cand == null) {
        return handler.reject(_error(options, 'linea_no_valida', 'La línea no es candidata.'));
      }
      if (cand['cambia_minimo'] == true && d['confirmar'] != true) {
        return handler.reject(_error(options, 'cambio_minimo',
            'El servicio nuevo tiene un servicio mínimo distinto al actual.'));
      }
      _servicio[int.parse(m[1]!)] = cand['producto'] as String;
      return handler.next(_aDetalle(options, m));
    }

    // GET complementos = catálogo menos los cargos activos.
    m = _complementosRe.firstMatch(path);
    if (!post && m != null) {
      final activos = _cargosDe(int.parse(m[1]!))
          .where((c) => c['anulado'] != true)
          .map((c) => c['producto'])
          .toSet();
      return handler.resolve(
          _ok(options, _catalogo.where((p) => !activos.contains(p['producto'])).toList()));
    }

    // POST añadir cargo.
    m = _cargosRe.firstMatch(path);
    if (post && m != null && d is Map) {
      final id = int.parse(m[1]!);
      final prod = _catalogo.where((p) => p['product_id'] == d['product_id']).firstOrNull;
      final lista = _cargosDe(id);
      if (prod == null ||
          lista.any((c) => c['producto'] == prod['producto'] && c['anulado'] != true)) {
        return handler.reject(_error(options, 'cargo_duplicado', 'El complemento ya está en la tarea.'));
      }
      lista.add({'id': _nextCargoId++, 'producto': prod['producto'], 'cantidad': 1.0,
                 'anulado': false, 'origen': 'app', 'anulable': true});
      return handler.next(_aDetalle(options, m));
    }

    // POST anular cargo.
    m = _anularRe.firstMatch(path);
    if (post && m != null) {
      final c = _cargosDe(int.parse(m[1]!))
          .where((c) => c['id'] == int.parse(m![2]!))
          .firstOrNull;
      if (c == null || c['anulado'] == true) {
        return handler.reject(_error(options, 'cargo_no_anulable', 'El cargo no se puede anular.'));
      }
      c..['anulado'] = true..['cantidad'] = 0.0..['anulable'] = false;
      return handler.next(_aDetalle(options, m));
    }

    // GET pendientes de firma de la obra: los ficticios + los diferidos reales.
    m = _pendientesRe.firstMatch(path);
    if (!post && m != null) {
      final ids = [..._pendientesFicticios, ..._diferidas]
          .where((i) => !_firmadasLote.contains(i))
          .toList();
      return handler.resolve(_ok(options, [
        for (final i in ids)
          {
            'id': i,
            'albaran': _pendientesFicticios.contains(i) ? 'ALB/2026/$i (mock)' : 'Tarea $i',
            'fecha': _utcStr(DateTime.now().subtract(Duration(days: i % 3 + 1))),
            'servicio': {'producto': 'Camión grúa 80 t (mock)'},
            'cargos': [
              {'id': 1, 'producto': 'Balancín', 'cantidad': 1.0, 'anulado': false,
               'origen': 'planificado', 'anulable': false},
            ],
            'recargo': {'value': 'none', 'label': 'Sin recargo'},
            'salida': {'value': 'salida', 'label': 'Salida'},
            'resumen_albaran': {
              'modo': 'horario',
              'inicio': _utcStr(DateTime.now().subtract(const Duration(days: 1, hours: 8))),
              'fin': _utcStr(DateTime.now().subtract(const Duration(days: 1))),
              'comida': null, 'horas': 8.0, 'servicio_minimo': false,
              'obs_conductor': null, 'obs_cliente': null,
            },
          },
      ]));
    }

    // POST finalize con firma diferida → se simula (el v2 exige firma).
    m = _finalizeRe.firstMatch(path);
    if (post && m != null && d is Map && d['firma_diferida'] == true) {
      final id = int.parse(m[1]!);
      _diferidas.add(id);
      _nuevaSolicitud(id);
      return handler.next(_aDetalle(options, m));
    }

    // POST solicitudes de firma.
    if (post && _solicitudesRe.hasMatch(path) && d is Map) {
      final ids = (d['task_ids'] as List? ?? const []).whereType<int>().toList();
      Map<String, dynamic>? sol;
      for (final i in ids) {
        sol = _nuevaSolicitud(i);
      }
      if (sol == null) {
        return handler.reject(_error(options, 'datos_invalidos', 'Sin tareas.'));
      }
      return handler.resolve(_ok(options, {
        ...sol,
        'mensaje': 'Hola, Grúas (mock) le envía ${ids.length} albarán(es) para firmar: ${sol['url']}',
      }));
    }

    // POST firma en lote → se simula; el servidor v2 no se toca.
    if (post && _loteRe.hasMatch(path) && d is Map) {
      final ids = (d['task_ids'] as List? ?? const []).whereType<int>().toList();
      _firmadasLote.addAll(ids);
      _diferidas.removeAll(ids);
      ids.forEach(_solicitudes.remove);
      return handler.resolve(_ok(options, {
        'lote': 'LOTE/2026/${(_nextLote++).toString().padLeft(4, '0')} (mock)',
        'tasks': const [],
      }));
    }

    // GET firmantes de la obra.
    m = _firmantesRe.firstMatch(path);
    if (!post && m != null) {
      return handler.resolve(_ok(options, [for (final f in _firmantes) _firmanteApp(f)]));
    }

    // POST firmante: si el documento ya existe se devuelve; si no, se crea.
    if (post && m != null && d is Map) {
      final doc = (d['documento'] ?? '').toString().toUpperCase().replaceAll(RegExp(r'[\s\-]'), '');
      if (doc.isEmpty) {
        return handler.reject(_error(options, 'documento_requerido', 'Falta el documento.'));
      }
      var f = _firmantes.where((x) => x['documento'] == doc).firstOrNull;
      if (f == null) {
        f = {'id': _nextFirmanteId++, 'nombre': d['nombre'], 'documento': doc, 'movil': null};
        _firmantes.add(f);
      }
      final movil = (d['movil'] ?? '').toString().replaceAll(RegExp(r'[\s\-]'), '');
      if (movil.isNotEmpty) f['movil'] = movil.startsWith('+') ? movil : '+34$movil';
      return handler.resolve(_ok(options, _firmanteApp(f)));
    }

    // POST signature con firmante_id → el servidor v2 no lo conoce: se rellenan
    // nombre y documento desde el firmante simulado.
    m = _signatureRe.firstMatch(path);
    if (post && m != null && d is Map && d['firmante_id'] != null) {
      final f = _firmantes.where((x) => x['id'] == d['firmante_id']).firstOrNull;
      if (f != null) {
        options.data = Map<String, dynamic>.from(d)
          ..['signer_name'] = f['nombre']
          ..['dni'] = f['documento'];
      }
    }

    handler.next(options);
  }

  /// Convierte la petición en `GET /tasks/<id>` (prefijo de la ruta conservado).
  RequestOptions _aDetalle(RequestOptions o, RegExpMatch m) => o
    ..method = 'GET'
    ..path = '${o.path.substring(0, m.start)}/tasks/${m[1]}'
    ..data = null;

  Response _ok(RequestOptions o, Object data) =>
      Response(requestOptions: o, statusCode: 200, data: data);

  DioException _error(RequestOptions o, String code, String detail) => DioException(
        requestOptions: o,
        type: DioExceptionType.badResponse,
        response: Response(
            requestOptions: o, statusCode: 422, data: {'error': code, 'detail': detail}),
      );

  /// Body v3 de /close → v2 (pausa + modo) para probar contra un servidor v2.
  /// Limitación: sin incidencia se envía 'normal'; el v2 no decide el mínimo.
  Map<String, dynamic> _closeV3aV2(Map<String, dynamic> d) {
    final v2 = Map<String, dynamic>.from(d);
    var pausa = 0.0;
    final c = d['comida'];
    if (c is Map) {
      final dur = c['duracion'];
      if (dur is num) {
        pausa = dur.toDouble();
      } else {
        final ini = _utc(c['inicio']), fin = _utc(c['fin']);
        if (ini != null && fin != null) pausa = fin.difference(ini).inMinutes / 60.0;
      }
    }
    v2['pausa'] = pausa;
    v2['modo'] = d['incidencia'] == true ? 'incidencia' : 'normal';
    return v2;
  }

  static DateTime? _utc(dynamic s) =>
      s is String ? DateTime.tryParse('${s.replaceFirst(' ', 'T')}Z') : null;

  // ─────────────────────────── Respuestas ───────────────────────────

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final data = response.data;
    if (data is Map<String, dynamic>) {
      if (response.requestOptions.path.endsWith('/me')) {
        _config(data);
      } else if (data['tasks'] is List) {
        // Lista: bloque `firma` en cada resumen (propuesta de contrato).
        for (final t in (data['tasks'] as List).whereType<Map<String, dynamic>>()) {
          _marcarLote(t);
          t.putIfAbsent('firma', () => _firmaDe(t['id'] as int?, t['has_signature'] == true));
        }
      } else if (data.containsKey('worksheet')) {
        _detalle(data); // cualquier respuesta con forma de _task_detail
      }
    }
    handler.next(response);
  }

  void _config(Map<String, dynamic> me) {
    final c = me['config'];
    if (c is! Map<String, dynamic>) return;
    c.putIfAbsent('comida', () => 'siempre');
    c.putIfAbsent('comida_hora_defecto', () => '14:00');
    c.putIfAbsent('minimo_mostrar_fin', () => false);
    c.putIfAbsent('firma_enlace_dias', () => 7);
    // En QA todo activo para ver todas las acciones.
    c.putIfAbsent('permisos', () => <String, dynamic>{
          'cambiar_servicio': true,
          'anadir_cargos': true,
          'anular_cargos': true,
          'editar_recargo': true,
          'editar_salida': true,
          'firma_diferida': true,
        });
  }

  void _detalle(Map<String, dynamic> t) {
    // Solo se simula lo que el servidor NO envía.
    final simular = {
      'servicio': !t.containsKey('servicio'),
      'recargo': !t.containsKey('recargo'),
      'salida': !t.containsKey('salida'),
      'cargos': !t.containsKey('cargos'),
    };
    final id = t['id'] is int ? t['id'] as int : null;

    final partner = t['partner'];
    t.putIfAbsent('obra', () => partner is Map
        ? <String, dynamic>{'id': partner['id'], 'nombre': partner['name']}
        : null);

    t.putIfAbsent('servicio', () => <String, dynamic>{
          'sale_line_id': 4411,
          'producto': (id != null ? _servicio[id] : null) ?? 'Camión grúa 80 t (mock)',
          'editable': true,
        });

    final tr = t['tipo_recargo'];
    t.putIfAbsent('recargo', () => <String, dynamic>{
          'value': tr is Map ? (tr['value'] ?? 'none') : 'none',
          'label': tr is Map ? (tr['label'] ?? 'Sin recargo') : 'Sin recargo',
          'editable': true,
          'opciones': [
            {'value': 'none', 'label': 'Sin recargo'},
            {'value': 'nocturno', 'label': 'Nocturno'},
            {'value': 'festivo', 'label': 'Festivo'},
            {'value': 'nocturno_festivo', 'label': 'Nocturno + Festivo'},
          ],
        });

    t.putIfAbsent('salida', () => <String, dynamic>{
          'value': 'salida',
          'label': 'Salida',
          'editable': true,
          'opciones': [
            {'value': 'salida', 'label': 'Salida'},
            {'value': 'coche', 'label': 'Coche'},
            {'value': 'none', 'label': 'Sin salida'},
          ],
        });

    if (simular['cargos'] == true && id != null) {
      t['cargos'] = [for (final c in _cargosDe(id)) Map<String, dynamic>.from(c)];
    }

    _marcarLote(t);
    t.putIfAbsent('firma', () => _firmaDe(id, t['has_signature'] == true));

    final ap = t['apertura'];
    final ci = t['cierre'];
    final ws = t['worksheet'];
    final minimo = ws is Map && ws['aplicar_minimo'] == true;
    // v3.3: null mientras el recurso no esté cerrado.
    final cerrada = ci is Map && ci['hora_informada'] != null;
    t.putIfAbsent('resumen_albaran', () => !cerrada
        ? null
        : <String, dynamic>{
            'modo': minimo ? 'minimo' : 'horario',
            'inicio': ap is Map ? ap['hora_informada'] : null,
            'fin': minimo ? null : ci['hora_informada'],
            'comida': null,
            'horas': minimo ? null : (ws is Map ? ws['horas_facturar'] : null),
            'servicio_minimo': minimo,
            'obs_conductor': ws is Map ? ws['obs_albaran'] : null,
            'obs_cliente': ws is Map ? ws['obs_cliente'] : null,
          });

    final recursos = t['recursos'];
    if (recursos is List) {
      for (final r in recursos.whereType<Map<String, dynamic>>()) {
        if (r['cerrada'] != true) continue;
        final rMin = r['aplicar_minimo'] == true;
        r.putIfAbsent('resumen_albaran', () => <String, dynamic>{
              'modo': rMin ? 'minimo' : (r['incidencia'] == true ? 'incidencia' : 'horas'),
              'inicio': r['apertura_informada'],
              'fin': null,
              'comida': null,
              'horas': rMin ? null : r['horas_facturar'],
              'servicio_minimo': rMin,
              'obs_conductor': null,
              'obs_cliente': null,
            });
      }
    }

    _aplicarSel(t, simular);
  }

  /// Las firmadas en lote simulado se muestran como firmadas y cerradas (solo QA:
  /// en el servidor v2 siguen sin firma).
  void _marcarLote(Map<String, dynamic> t) {
    if (_firmadasLote.contains(t['id'])) {
      t['has_signature'] = true;
      t['cerrada'] = true;
    }
  }

  void _aplicarSel(Map<String, dynamic> t, Map<String, bool> simular) {
    final id = t['id'];
    final sel = id is int ? _sel[id] : null;
    if (sel == null) return;
    sel.forEach((campo, value) {
      final b = t[campo];
      if (simular[campo] != true || b is! Map) return;
      final ops = b['opciones'];
      final op = ops is List
          ? ops.whereType<Map>().where((o) => o['value'] == value).firstOrNull
          : null;
      b['value'] = value;
      b['label'] = op?['label'] ?? value;
    });
  }
}