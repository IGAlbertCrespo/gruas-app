import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart' show secureStoreProvider;
import '../../../shared/duracion_sospechosa.dart';
import '../../../shared/formulario_tiempo.dart';
import '../../../shared/horas.dart';
import '../../../shared/location.dart';
import '../../../shared/pausa_dialog.dart' show fmtHoras;
import '../../../shared/widgets/upgrade_required.dart' show mostrarErrorAccion;
import '../../auth/session_controller.dart';
import '../../auth/session_models.dart';
import '../actividad_models.dart';
import '../tasks_providers.dart';
import 'jornada_aviso.dart';

/// v3.11 §4.8 — "Nueva tarea": el conductor registra una actividad no
/// productiva (tarea no facturable "Interna", completada al crearse).
///
/// Una sola pantalla: actividad → vehículo → día → tiempo → observaciones.
/// - Actividad: lista con buscador y "Últimas usadas" (en este móvil).
/// - Vehículo: preseleccionado el habitual; matrícula como texto principal.
/// - Día: Hoy / Ayer / Otro día, limitado a `actividades_dias`. Cambiar el día
///   borra el tiempo (el inicio debe ser de ese día).
/// - Tiempo: pantalla de tiempo de la v3.10. Inicio propuesto: hoy, ahora − 1 h
///   (ajustado al paso, sin salir del día); otro día, 08:00.
/// - [ONLINE]: sin conexión se avisa y los datos se quedan en pantalla.
///
/// Devuelve true si se ha creado la tarea.
class NuevaTareaScreen extends ConsumerStatefulWidget {
  const NuevaTareaScreen({super.key});

  @override
  ConsumerState<NuevaTareaScreen> createState() => _NuevaTareaScreenState();
}

class _NuevaTareaScreenState extends ConsumerState<NuevaTareaScreen> {
  static const _maxRecientes = 3;

  List<Actividad>? _actividades;
  List<VehiculoApp>? _vehiculos;
  List<int> _recientes = const [];
  Object? _errorCarga;

  Actividad? _actividad;
  VehiculoApp? _vehiculo;
  late DateTime _dia = soloDia(DateTime.now());
  TiempoDeclarado? _tiempo;
  final _obs = TextEditingController();
  bool _enviando = false;

  SessionConfig get _cfg =>
      ref.read(sessionControllerProvider).profile?.config ?? SessionConfig.fallback;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _obs.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------- datos

  Future<void> _cargar() async {
    setState(() => _errorCarga = null);
    try {
      final repo = ref.read(tasksRepoProvider);
      final r = await Future.wait([repo.actividades(), repo.vehiculos()]);
      final recientes = await _leerRecientes();
      if (!mounted) return;
      final vehiculos = r[1] as List<VehiculoApp>;
      setState(() {
        _actividades = r[0] as List<Actividad>;
        _vehiculos = vehiculos;
        _recientes = recientes;
        _vehiculo ??= vehiculos.where((v) => v.habitual).firstOrNull;
      });
    } catch (e) {
      if (mounted) setState(() => _errorCarga = e);
    }
  }

  Future<List<int>> _leerRecientes() async {
    try {
      return await ref.read(secureStoreProvider).readActividadesRecientes();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _guardarReciente(int lineId) async {
    final ids = [lineId, ..._recientes.where((i) => i != lineId)].take(10).toList();
    try {
      await ref.read(secureStoreProvider).saveActividadesRecientes(ids);
    } catch (_) {
      // Solo es una comodidad: si falla, no pasa nada.
    }
  }

  // --------------------------------------------------------------- acciones

  Future<void> _elegirActividad() async {
    final todas = _actividades ?? const <Actividad>[];
    final porId = {for (final a in todas) a.lineId: a};
    final recientes = [
      for (final id in _recientes)
        if (porId[id] != null) porId[id]!,
    ].take(_maxRecientes).toList();

    final a = await Navigator.of(context).push<Actividad>(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _SelectorLista<Actividad>(
        titulo: 'Actividad',
        items: todas,
        destacados: recientes,
        tituloDestacados: 'Últimas usadas',
        texto: (a) => a.descripcion,
        textoBusqueda: (a) => a.descripcion,
      ),
    ));
    if (a != null && mounted) setState(() => _actividad = a);
  }

  Future<void> _elegirVehiculo() async {
    final v = await Navigator.of(context).push<VehiculoApp>(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _SelectorLista<VehiculoApp>(
        titulo: 'Vehículo',
        items: _vehiculos ?? const <VehiculoApp>[],
        texto: (v) => v.principal,
        subtexto: (v) => v.secundario,
        etiqueta: (v) => v.habitual ? 'Habitual' : null,
        textoBusqueda: (v) => '${v.matricula ?? ''} ${v.nombre}',
        textoNegrita: true,
      ),
    ));
    if (v != null && mounted) setState(() => _vehiculo = v);
  }

  void _cambiarDia(DateTime d) {
    final nuevo = soloDia(d);
    if (nuevo == _dia) return;
    final teniaTiempo = _tiempo != null;
    setState(() {
      _dia = nuevo;
      _tiempo = null;
    });
    if (teniaTiempo) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Has cambiado el día: vuelve a indicar el tiempo.')));
    }
  }

  Future<void> _elegirOtroDia() async {
    final hoy = soloDia(DateTime.now());
    final primero = DateTime(hoy.year, hoy.month, hoy.day - (_cfg.actividadesDias - 1));
    final d = await showDatePicker(
      context: context,
      initialDate: _dia.isBefore(primero) ? hoy : _dia,
      firstDate: primero,
      lastDate: hoy,
      helpText: 'Día en que se hizo',
    );
    if (d != null && mounted) _cambiarDia(d);
  }

  /// Hoy: ahora − 1 h ajustado al paso (sin salir del día); otro día: 08:00.
  DateTime _inicioPropuesto() {
    final hoy = soloDia(DateTime.now());
    if (_dia == hoy) {
      final t = ajustarHoraAPaso(DateTime.now().subtract(const Duration(hours: 1)), _cfg.tiempo.pasoMin);
      return soloDia(t) == _dia ? t : _dia;
    }
    return DateTime(_dia.year, _dia.month, _dia.day, 8);
  }

  Future<void> _elegirTiempo() async {
    final cfg = _cfg;
    final t = await pedirTiempo(
      context,
      formatos: cfg.formatosCierre,
      cfg: cfg,
      inicioPropuesto: _inicioPropuesto(),
      dia: _dia,
      horasPrevistas: 1.0,
      titulo: 'Tiempo de la tarea',
      subtitulo: [
        if (_actividad != null) _actividad!.descripcion,
        'Día ${fmtDia(_dia)}',
      ].join(' · '),
    );
    if (t != null && mounted) setState(() => _tiempo = t);
  }

  Future<void> _guardar() async {
    final act = _actividad, veh = _vehiculo, tiempo = _tiempo;
    if (act == null || veh == null || tiempo == null) return;
    setState(() => _enviando = true);
    try {
      final (lat, lng) = await bestEffortLocation();
      if (!mounted) return;
      final res = await conConfirmacionDuracion(
        context,
        (confirmar) => ref.read(tasksRepoProvider).crearTarea(
              lineId: act.lineId,
              vehicleId: veh.id,
              fecha: _dia,
              tiempo: tiempo,
              obs: _obs.text,
              confirmar: confirmar,
              lat: lat,
              lng: lng,
            ),
      );
      if (res == null) return; // eligió revisar: no se ha creado nada
      await _guardarReciente(act.lineId);
      ref.invalidate(tasksListProvider);
      if (!mounted) return;
      await tratarJornada(context, ref, res.jornada);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Tarea creada.')));
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.sinConexion) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Necesitas conexión para añadir tareas. Vuelve a intentarlo.')));
      } else {
        await mostrarErrorAccion(context, e);
      }
    } catch (e) {
      if (mounted) await mostrarErrorAccion(context, e);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  // --------------------------------------------------------------------- UI

  static String _dos(int n) => n.toString().padLeft(2, '0');
  static String _hm(DateTime d) {
    final l = d.toLocal();
    return '${_dos(l.hour)}:${_dos(l.minute)}';
  }

  String _resumenTiempo(TiempoDeclarado t) {
    final ini = t.inicio, fin = t.fin, h = t.horas;
    final String base;
    if (t.formato == FormatoCierre.inicioFin && ini != null && fin != null) {
      base = '${_hm(ini)} – ${_hm(fin)} (${fmtHoras(horasEntre(ini, fin))})';
    } else if (t.formato == FormatoCierre.inicioHoras && ini != null && h != null) {
      base = '${_hm(ini)} · ${fmtHoras(h)}';
    } else {
      base = h != null ? fmtHoras(h) : '';
    }
    return t.comidaMin > 0 ? '$base · ${fmtHoras(t.comidaHoras)} comida' : base;
  }

  Widget _seccion(String texto) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 4),
        child: Text(texto, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
      );

  Widget _campo({
    required String texto,
    String? subtexto,
    bool vacio = false,
    VoidCallback? onTap,
  }) =>
      Card(
        margin: EdgeInsets.zero,
        child: ListTile(
          title: Text(
            texto,
            style: TextStyle(
              fontSize: 16,
              fontWeight: vacio ? FontWeight.normal : FontWeight.w600,
              color: vacio ? Theme.of(context).colorScheme.primary : null,
            ),
          ),
          subtitle: subtexto == null
              ? null
              : Text(subtexto,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.black54)),
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
        ),
      );

  Widget _selectorDia() {
    final hoy = soloDia(DateTime.now());
    final ayer = DateTime(hoy.year, hoy.month, hoy.day - 1);
    final dias = _cfg.actividadesDias;
    final esOtro = _dia != hoy && _dia != ayer;
    return Wrap(
      spacing: 8,
      children: [
        ChoiceChip(label: const Text('Hoy'), selected: _dia == hoy, onSelected: (_) => _cambiarDia(hoy)),
        if (dias >= 2)
          ChoiceChip(label: const Text('Ayer'), selected: _dia == ayer, onSelected: (_) => _cambiarDia(ayer)),
        if (dias >= 3)
          ChoiceChip(
            label: Text(esOtro ? fmtDia(_dia) : 'Otro día…'),
            selected: esOtro,
            onSelected: (_) => _elegirOtroDia(),
          ),
      ],
    );
  }

  Widget _cuerpo() {
    if (_errorCarga != null) {
      final e = _errorCarga;
      final texto = (e is ApiException && e.sinConexion)
          ? 'Necesitas conexión para añadir tareas.'
          : 'No se han podido cargar las actividades.\n$e';
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(texto, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _cargar,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }
    if (_actividades == null || _vehiculos == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_actividades!.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('No hay actividades configuradas. Avisa a la oficina.',
              textAlign: TextAlign.center),
        ),
      );
    }

    final tiempo = _tiempo;
    return AbsorbPointer(
      absorbing: _enviando,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          _seccion('Actividad'),
          _campo(
            texto: _actividad?.descripcion ?? 'Elegir…',
            vacio: _actividad == null,
            onTap: _elegirActividad,
          ),
          _seccion('Vehículo'),
          _campo(
            texto: _vehiculo == null
                ? 'Elegir…'
                : '${_vehiculo!.principal}${_vehiculo!.habitual ? '  ·  Habitual' : ''}',
            subtexto: _vehiculo?.secundario,
            vacio: _vehiculo == null,
            onTap: _elegirVehiculo,
          ),
          _seccion('Día'),
          _selectorDia(),
          _seccion('Tiempo'),
          _campo(
            texto: tiempo == null ? 'Indicar…' : _resumenTiempo(tiempo),
            vacio: tiempo == null,
            onTap: _elegirTiempo,
          ),
          _seccion('Observaciones (opcional)'),
          TextField(
            controller: _obs,
            minLines: 2,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'Qué has hecho',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final listo = _actividad != null && _vehiculo != null && _tiempo != null && !_enviando;
    return Scaffold(
      appBar: AppBar(title: const Text('Nueva tarea')),
      body: SafeArea(child: _cuerpo()),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _enviando ? null : () => Navigator.of(context).pop(),
                  child: const Text('Cancelar'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: listo ? _guardar : null,
                  child: _enviando
                      ? const SizedBox(
                          width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Guardar'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Lista a pantalla completa para elegir un elemento, con buscador si hay más
/// de 8 y un bloque opcional de destacados arriba (p. ej. "Últimas usadas").
class _SelectorLista<T> extends StatefulWidget {
  const _SelectorLista({
    required this.titulo,
    required this.items,
    required this.texto,
    required this.textoBusqueda,
    this.subtexto,
    this.etiqueta,
    this.destacados = const [],
    this.tituloDestacados,
    this.textoNegrita = false,
  });

  final String titulo;
  final List<T> items;
  final String Function(T) texto;
  final String Function(T) textoBusqueda;
  final String? Function(T)? subtexto;
  final String? Function(T)? etiqueta;
  final List<T> destacados;
  final String? tituloDestacados;
  final bool textoNegrita;

  @override
  State<_SelectorLista<T>> createState() => _SelectorListaState<T>();
}

class _SelectorListaState<T> extends State<_SelectorLista<T>> {
  final _buscar = TextEditingController();
  String _filtro = '';

  @override
  void dispose() {
    _buscar.dispose();
    super.dispose();
  }

  static String _norm(String s) => s
      .toLowerCase()
      .replaceAll(RegExp('[áàä]'), 'a')
      .replaceAll(RegExp('[éèë]'), 'e')
      .replaceAll(RegExp('[íìï]'), 'i')
      .replaceAll(RegExp('[óòö]'), 'o')
      .replaceAll(RegExp('[úùü]'), 'u')
      .replaceAll(' ', '');

  Widget _fila(T item) {
    final sub = widget.subtexto?.call(item);
    final eti = widget.etiqueta?.call(item);
    return ListTile(
      title: Text(
        widget.texto(item),
        style: TextStyle(
          fontSize: widget.textoNegrita ? 18 : 16,
          fontWeight: widget.textoNegrita ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      subtitle: sub == null
          ? null
          : Text(sub,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.black54)),
      trailing: eti == null ? null : Chip(label: Text(eti), visualDensity: VisualDensity.compact),
      onTap: () => Navigator.of(context).pop(item),
    );
  }

  @override
  Widget build(BuildContext context) {
    final conBuscador = widget.items.length > 8;
    final f = _norm(_filtro);
    final filtrados = f.isEmpty
        ? widget.items
        : widget.items.where((i) => _norm(widget.textoBusqueda(i)).contains(f)).toList();
    final verDestacados = f.isEmpty && widget.destacados.isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: Text(widget.titulo)),
      body: SafeArea(
        child: Column(
          children: [
            if (conBuscador)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: TextField(
                  controller: _buscar,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Buscar…',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _filtro = v),
                ),
              ),
            Expanded(
              child: ListView(
                children: [
                  if (verDestacados) ...[
                    if (widget.tituloDestacados != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: Text(widget.tituloDestacados!,
                            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black54)),
                      ),
                    for (final i in widget.destacados) _fila(i),
                    const Divider(),
                  ],
                  for (final i in filtrados) _fila(i),
                  if (filtrados.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: Text('Sin resultados.')),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}