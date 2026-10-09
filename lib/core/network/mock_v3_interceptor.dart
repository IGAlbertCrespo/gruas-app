import 'package:dio/dio.dart';

/// Solo QA. Se activa con `--dart-define=MOCK_V3=true` y nunca en producción
/// (ver `dioProvider` en core/providers.dart).
const bool kMockV3 = bool.fromEnvironment('MOCK_V3');

/// Completa las respuestas de un servidor que aún no es v3 con los bloques del
/// CONTRATO v3.3, para desarrollar pantallas antes de que el backend esté listo.
///
/// Regla: solo AÑADE claves AUSENTES (`putIfAbsent`). En cuanto el servidor
/// envía la clave (aunque sea `null`, como en las tareas hija), manda el servidor.
class MockV3Interceptor extends Interceptor {
  static final _close = RegExp(r'/tasks/\d+/close$');
  static final _selRe = RegExp(r'/tasks/(\d+)/(recargo|salida)$');

  /// Selecciones hechas en la APP mientras está abierta: {taskId: {campo: value}}.
  final Map<int, Map<String, String>> _sel = {};

  // ─────────────────────────── Peticiones ───────────────────────────

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final d = options.data;
    if (options.method == 'POST' && _close.hasMatch(options.path) &&
        d is Map<String, dynamic> && d.containsKey('modo_cierre')) {
      options.data = _closeV3aV2(d);
    }

    // POST /tasks/<id>/recargo|salida → se recuerda la elección y se convierte
    // en GET /tasks/<id> (el servidor v2 no tiene la ruta). Al inyectar el
    // detalle se aplica la elección.
    final m = _selRe.firstMatch(options.path);
    if (options.method == 'POST' && m != null && d is Map && d['tipo'] is String) {
      _sel.putIfAbsent(int.parse(m[1]!), () => {})[m[2]!] = d['tipo'] as String;
      options
        ..method = 'GET'
        ..path = '${options.path.substring(0, m.start)}/tasks/${m[1]}'
        ..data = null;
    }
    handler.next(options);
  }

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
      'recargo': !t.containsKey('recargo'),
      'salida': !t.containsKey('salida'),
    };

    final partner = t['partner'];
    t.putIfAbsent('obra', () => partner is Map
        ? <String, dynamic>{'id': partner['id'], 'nombre': partner['name']}
        : null);

    t.putIfAbsent('servicio', () => <String, dynamic>{
          'sale_line_id': 4411,
          'producto': 'Camión grúa 80 t (mock)',
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
            {'value': 'none', 'label': 'Sin salida'}, // v3.2
          ],
        });

    t.putIfAbsent('cargos', () => [
          {'id': 301, 'producto': 'Balancín', 'cantidad': 1.0,
           'anulado': false, 'origen': 'planificado', 'anulable': true},
          {'id': 305, 'producto': 'Ventosa', 'cantidad': 1.0,
           'anulado': false, 'origen': 'app', 'anulable': true},
        ]);

    t.putIfAbsent('firma', () => <String, dynamic>{
          'falta_firma': false,
          'firmada': t['has_signature'] == true,
          'lote': null,
          'solicitud': null,
        });

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