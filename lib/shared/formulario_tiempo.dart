import 'package:flutter/material.dart';

import '../features/auth/session_models.dart';
import 'horas.dart';
import 'observaciones_dialog.dart';
import 'pausa_dialog.dart' show fmtHoras;

// v3.10 — Pantalla única para declarar el tiempo al terminar (CONTRATO §4.1,
// §4.5). La usan el cierre de recurso (`/close`), las no facturables con solo
// horas (`/complete`) y, en v3.11, las tareas creadas por el conductor.
//
// - Formato: uno o varios de `formatos`; si hay varios, elige el conductor.
// - Inicio: el real (tarea iniciada en la APP, corregible) o el propuesto
//   (solo horas: hora planificada). La hora se elige dentro de [dia].
// - Horas: valor inicial = tiempo transcurrido (con inicio real) o
//   `horas_previstas`; pasos de `tiempo.paso_min`, +1 h y tecleo.
// - Fin (inicio y fin): fecha deducida del inicio (regla de medianoche).
// - Comida: "Sin comida" + `comida_opciones`; en inicio y fin, además la hora.
//
// No valida el umbral de 16 h: lo hace el servidor (`422 duracion_sospechosa`)
// y el llamador lo confirma con `conConfirmacionDuracion`.

/// Lo que ha declarado el conductor.
class TiempoDeclarado {
  const TiempoDeclarado({
    required this.formato,
    this.inicio,
    this.inicioCambiado = false,
    this.fin,
    this.horas,
    this.comidaMin = 0,
    this.comidaInicio,
    this.obs,
  });

  final FormatoCierre formato;

  /// Inicio declarado (null en `horas`: lo pone el servidor).
  final DateTime? inicio;

  /// El inicio difiere del recibido (tarea iniciada: se envía `apertura_informada`).
  final bool inicioCambiado;

  /// Fin (solo `inicio_fin`), ya normalizado tras el inicio.
  final DateTime? fin;

  /// Horas H (formatos `horas` e `inicio_horas`).
  final double? horas;

  /// Minutos de comida (0 = sin comida).
  final int comidaMin;

  /// Inicio de la comida (solo `inicio_fin` con comida).
  final DateTime? comidaInicio;

  /// v3.12: observaciones del albarán escritas en el formulario (solo si se
  /// abrió con `conObservaciones`). null o vacío = no se envían.
  final String? obs;

  double get comidaHoras => comidaMin / 60.0;

  /// Bruto para el cálculo provisional: H, o la ventana en `inicio_fin`.
  double get bruto {
    final i = inicio, f = fin;
    if (formato == FormatoCierre.inicioFin && i != null && f != null) {
      return horasEntre(i, f);
    }
    return horas ?? 0.0;
  }
}

/// Abre la pantalla. Devuelve null si el conductor cancela.
///
/// - [inicioReal]: inicio de la tarea iniciada en la APP (sin solo horas).
/// - [inicioPropuesto]: con solo horas, la hora planificada.
/// - [dia]: día al que se limita la hora de inicio (planificado o `fecha`).
Future<TiempoDeclarado?> pedirTiempo(
  BuildContext context, {
  required List<FormatoCierre> formatos,
  required SessionConfig cfg,
  DateTime? inicioReal,
  DateTime? inicioPropuesto,
  DateTime? dia,
  double? horasPrevistas,
  String titulo = 'Tiempo del servicio',
  String? subtitulo,
  bool conObservaciones = false,
  String? obsInicial,
  bool avisoCliente = false,
}) {
  assert(formatos.isNotEmpty);
  return Navigator.of(context).push<TiempoDeclarado>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _FormularioTiempo(
        formatos: formatos,
        cfg: cfg,
        inicioReal: inicioReal,
        inicioPropuesto: inicioPropuesto,
        dia: dia,
        horasPrevistas: horasPrevistas,
        titulo: titulo,
        subtitulo: subtitulo,
        conObservaciones: conObservaciones,
        obsInicial: obsInicial,
        avisoCliente: avisoCliente,
      ),
    ),
  );
}

class _FormularioTiempo extends StatefulWidget {
  const _FormularioTiempo({
    required this.formatos,
    required this.cfg,
    this.inicioReal,
    this.inicioPropuesto,
    this.dia,
    this.horasPrevistas,
    required this.titulo,
    this.subtitulo,
    this.conObservaciones = false,
    this.obsInicial,
    this.avisoCliente = false,
  });

  final List<FormatoCierre> formatos;
  final SessionConfig cfg;
  final DateTime? inicioReal;
  final DateTime? inicioPropuesto;
  final DateTime? dia;
  final double? horasPrevistas;
  final String titulo;
  final String? subtitulo;
  final bool conObservaciones;
  final String? obsInicial;
  final bool avisoCliente;

  @override
  State<_FormularioTiempo> createState() => _FormularioTiempoState();
}

class _FormularioTiempoState extends State<_FormularioTiempo> {
  late FormatoCierre _formato = widget.formatos.first;
  late final DateTime? _inicioOriginal = (widget.inicioReal ?? widget.inicioPropuesto)?.toLocal();
  late DateTime? _inicio = _inicioOriginal;
  late double _horas = horasInicialesV310(
    inicioReal: widget.inicioReal,
    previstas: widget.horasPrevistas,
    pasoMin: _pasoMin,
  );
  DateTime? _fin;
  late int _comidaMin = widget.cfg.comidaDefectoMin;
  DateTime? _comidaInicio;
  bool _comidaInicioManual = false;
  late String _obs = (widget.obsInicial ?? '').trim();

  int get _pasoMin => widget.cfg.tiempo.pasoMin;
  double get _paso => widget.cfg.tiempo.pasoHoras;
  ReglaComida get _regla => reglaComidaDe(widget.cfg.comida);
  bool get _pideComida => widget.cfg.preguntaComida(_formato);
  int get _comidaEfectiva => _pideComida ? _comidaMin : 0;

  @override
  void initState() {
    super.initState();
    _fin = _finInicial();
    _recalcularComida();
  }

  // ------------------------------------------------------------------ valores

  /// Fin propuesto: "ahora" (ajustado al paso) si la tarea se inició en la APP
  /// hace ≤ 16 h; si no, inicio + horas previstas (sin pasar de ahora).
  DateTime? _finInicial() {
    final ini = _inicio;
    if (ini == null) return null;
    final ahora = ajustarHoraAPaso(DateTime.now(), _pasoMin);
    if (widget.inicioReal != null &&
        ahora.isAfter(ini) &&
        horasDesde(ini) <= umbralOlvidoHoras) {
      return ahora;
    }
    final f = ini.add(Duration(minutes: ((widget.horasPrevistas ?? 1.0) * 60).round()));
    return (f.isAfter(ahora) && ahora.isAfter(ini)) ? ahora : f;
  }

  /// Fin resultante en los formatos de horas (con `solo_horario` la ventana es H + C).
  DateTime _finHoras(DateTime ini) {
    final extra = _regla == ReglaComida.soloHorario ? _comidaEfectiva / 60.0 : 0.0;
    return ini.add(Duration(minutes: ((_horas + extra) * 60).round()));
  }

  /// [hora]:[minuto] dentro de la ventana que empieza en [ini] (mismo día o siguiente).
  static DateTime _trasOIgual(DateTime ini, int hora, int minuto) {
    final d = DateTime(ini.year, ini.month, ini.day, hora, minuto);
    return d.isBefore(ini) ? DateTime(ini.year, ini.month, ini.day + 1, hora, minuto) : d;
  }

  /// Comida a la hora por defecto de la compañía, dentro de [inicio, fin − duración].
  void _recalcularComida() {
    if (_comidaInicioManual) return;
    final ini = _inicio, fin = _fin;
    if (ini == null || fin == null || _comidaMin == 0) {
      _comidaInicio = null;
      return;
    }
    final m = widget.cfg.comidaHoraDefectoMin;
    var c = _trasOIgual(ini, m ~/ 60, m % 60);
    final ultimo = fin.subtract(Duration(minutes: _comidaMin));
    if (c.isAfter(ultimo)) c = ultimo;
    if (c.isBefore(ini)) c = ini; // no cabe: lo indica la validación
    _comidaInicio = c;
  }

  // ---------------------------------------------------------------- validación

  String? get _error {
    final ini = _inicio;
    if (_formato.pideInicio) {
      if (ini == null) return 'Indica la hora de inicio.';
      if (esFuturo(ini)) return 'El inicio no puede ser posterior a ahora.';
    }
    if (_formato == FormatoCierre.inicioFin) {
      final fin = _fin;
      if (ini == null || fin == null) return 'Indica la hora de fin.';
      if (esFuturo(fin)) return 'El fin no puede ser posterior a ahora.';
      final c = _comidaEfectiva;
      if (c > 0) {
        final ci = _comidaInicio;
        if (ci == null) return 'Indica la hora de la comida.';
        if (ci.isBefore(ini) || ci.add(Duration(minutes: c)).isAfter(fin)) {
          return 'La comida debe quedar dentro del horario (${_hm(ini)} – ${_hm(fin)}).';
        }
      }
    } else if (_formato.pideInicio && ini != null && esFuturo(_finHoras(ini))) {
      return 'Con ese inicio y esas horas, el fin quedaría posterior a ahora.';
    }
    return null;
  }

  // ------------------------------------------------------------------ acciones

  void _cambiarFormato(FormatoCierre f) => setState(() {
        _formato = f;
        _recalcularComida();
      });

  Future<void> _elegirInicio() async {
    final base = _inicio ?? DateTime.now();
    final tm = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(base),
      helpText: 'Hora de inicio',
    );
    if (tm == null || !mounted) return;
    final d = widget.dia != null ? soloDia(widget.dia!) : soloDia(base);
    setState(() {
      final ini = DateTime(d.year, d.month, d.day, tm.hour, tm.minute);
      _inicio = ini;
      final f = _fin;
      if (f != null) _fin = finTrasInicio(ini, f.hour, f.minute);
      _recalcularComida();
    });
  }

  Future<void> _elegirFin() async {
    final ini = _inicio;
    if (ini == null) return;
    final tm = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_fin ?? DateTime.now()),
      helpText: 'Hora de fin',
    );
    if (tm == null || !mounted) return;
    setState(() {
      _fin = finTrasInicio(ini, tm.hour, tm.minute);
      _recalcularComida();
    });
  }

  Future<void> _elegirHoraComida() async {
    final ini = _inicio;
    if (ini == null) return;
    final tm = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_comidaInicio ?? ini),
      helpText: 'Hora de la comida',
    );
    if (tm == null || !mounted) return;
    setState(() {
      _comidaInicio = _trasOIgual(ini, tm.hour, tm.minute);
      _comidaInicioManual = true;
    });
  }

  void _elegirComida(int minutos) => setState(() {
        _comidaMin = minutos;
        _recalcularComida();
      });

  void _sumarHoras(double delta) => setState(() {
        _horas = (_horas + delta).clamp(_paso, horasTotalesMax).toDouble();
      });

  Future<void> _teclearHoras() async {
    final ctrl = TextEditingController(text: _fmtNum(_horas));
    final v = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Horas'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(hintText: 'p. ej. 8 o 8,5'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () =>
                Navigator.pop(ctx, double.tryParse(ctrl.text.trim().replaceAll(',', '.'))),
            child: const Text('Aceptar'),
          ),
        ],
      ),
    );
    if (v == null || !mounted) return;
    setState(() {
      _horas = ajustarHorasAPaso(v, _pasoMin).clamp(_paso, horasTotalesMax).toDouble();
    });
  }

  void _continuar() {
    final ini = _formato.pideInicio ? _inicio : null;
    final orig = _inicioOriginal;
    final c = _comidaEfectiva;
    final esIF = _formato == FormatoCierre.inicioFin;
    Navigator.of(context).pop(TiempoDeclarado(
      formato: _formato,
      inicio: ini,
      inicioCambiado: ini != null && (orig == null || !ini.isAtSameMomentAs(orig)),
      fin: esIF ? _fin : null,
      horas: esIF ? null : _horas,
      comidaMin: c,
      comidaInicio: esIF && c > 0 ? _comidaInicio : null,
      obs: widget.conObservaciones && _obs.isNotEmpty ? _obs : null,
    ));
  }

  /// v3.12: observaciones opcionales. En facturables las ve el cliente.
  Future<void> _editarObs() async {
    final t = await pedirObsAlbaran(context,
        inicial: _obs, avisoCliente: widget.avisoCliente, titulo: 'Observaciones',
        accion: 'Aceptar');
    if (t != null && mounted) setState(() => _obs = t);
  }

  // ---------------------------------------------------------------------- UI

  static String _dos(int n) => n.toString().padLeft(2, '0');
  static String _hm(DateTime d) {
    final l = d.toLocal();
    return '${_dos(l.hour)}:${_dos(l.minute)}';
  }

  static String _fmtNum(double h) =>
      h % 1 == 0 ? h.toInt().toString() : h.toString().replaceAll('.', ',');

  Widget _seccion(String texto) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 8),
        child: Text(texto, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
      );

  Widget _selectorFormato() => SegmentedButton<FormatoCierre>(
        segments: [
          for (final f in widget.formatos)
            ButtonSegment<FormatoCierre>(value: f, label: Text(f.label)),
        ],
        selected: {_formato},
        showSelectedIcon: false,
        onSelectionChanged: (s) => _cambiarFormato(s.first),
      );

  Widget _selectorHoras() => Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton.filledTonal(
                iconSize: 32,
                onPressed: _horas > _paso ? () => _sumarHoras(-_paso) : null,
                icon: const Icon(Icons.remove),
              ),
              InkWell(
                onTap: _teclearHoras,
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 150,
                  child: Text(
                    fmtHoras(_horas),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              IconButton.filledTonal(
                iconSize: 32,
                onPressed: _horas < horasTotalesMax ? () => _sumarHoras(_paso) : null,
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          TextButton(
            onPressed: _horas + 1 <= horasTotalesMax ? () => _sumarHoras(1) : null,
            child: const Text('+1 h'),
          ),
          const Text('Toca la cifra para escribirla',
              style: TextStyle(color: Colors.black54, fontSize: 12)),
        ],
      );

  Widget _selectorComida() {
    final opciones = <(int, String)>[
      (0, 'Sin comida'),
      for (final o in widget.cfg.comidaOpciones) (o.minutos, o.label),
    ];
    if (opciones.length <= 4) {
      return SegmentedButton<int>(
        segments: [
          for (final (m, l) in opciones) ButtonSegment<int>(value: m, label: Text(l)),
        ],
        selected: {_comidaMin},
        showSelectedIcon: false,
        onSelectionChanged: (s) => _elegirComida(s.first),
      );
    }
    return DropdownButton<int>(
      value: opciones.any((o) => o.$1 == _comidaMin) ? _comidaMin : 0,
      isExpanded: true,
      items: [
        for (final (m, l) in opciones) DropdownMenuItem<int>(value: m, child: Text(l)),
      ],
      onChanged: (v) {
        if (v != null) _elegirComida(v);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final ini = _inicio;
    final fin = _fin;
    final esIF = _formato == FormatoCierre.inicioFin;
    final error = _error;
    final ci = _comidaInicio;

    return Scaffold(
      // Continuar arriba: el teclado nunca lo tapa. Cancelar = la X del diálogo.
      appBar: AppBar(
        title: Text(widget.titulo),
        actions: [
          TextButton(
            onPressed: error == null ? _continuar : null,
            child: const Text('Continuar'),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          children: [
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(error, style: const TextStyle(color: Colors.red)),
              ),
            if (widget.subtitulo != null)
              Text(widget.subtitulo!, style: const TextStyle(color: Colors.black54)),
            if (widget.formatos.length > 1) ...[
              _seccion('¿Cómo indicas el tiempo?'),
              _selectorFormato(),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(_formato.ayuda,
                    style: const TextStyle(color: Colors.black54, fontSize: 12)),
              ),
            ],

            // Día (formato horas: el inicio lo pone el servidor)
            if (!_formato.pideInicio && widget.dia != null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event),
                title: const Text('Día'),
                subtitle: Text(fmtDia(widget.dia!)),
              ),

            // Inicio
            if (_formato.pideInicio)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.play_arrow),
                title: const Text('Inicio'),
                subtitle: Text(ini == null ? 'Elegir…' : fmtDiaHora(ini),
                    style: const TextStyle(fontSize: 16)),
                trailing: const Icon(Icons.edit),
                onTap: _elegirInicio,
              ),

            // Fin (inicio y fin) u horas
            if (esIF)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.stop),
                title: const Text('Fin'),
                subtitle: Text(fin == null ? 'Elegir…' : fmtDiaHora(fin),
                    style: const TextStyle(fontSize: 16)),
                trailing: const Icon(Icons.edit),
                onTap: ini == null ? null : _elegirFin,
              )
            else ...[
              _seccion(_formato.pideInicio ? 'Horas desde el inicio' : '¿Cuántas horas?'),
              _selectorHoras(),
            ],

            // Resultado
            if (esIF && ini != null && fin != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Duración: ${fmtHoras(horasEntre(ini, fin))}',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              )
            else if (!esIF && _formato.pideInicio && ini != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Fin: ${fmtDiaHora(_finHoras(ini))}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),

            // Comida
            if (_pideComida) ...[
              _seccion('Comida'),
              _selectorComida(),
              if (!esIF && _regla != ReglaComida.nunca)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    _regla == ReglaComida.siempre
                        ? 'Las horas incluyen la comida.'
                        : 'Las horas no incluyen la comida.',
                    style: const TextStyle(color: Colors.black54, fontSize: 12),
                  ),
                ),
              if (esIF && _comidaMin > 0)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.restaurant),
                  title: const Text('Hora de la comida'),
                  subtitle: Text(
                      ci == null
                          ? 'Elegir…'
                          : '${_hm(ci)} – ${_hm(ci.add(Duration(minutes: _comidaMin)))}',
                      style: const TextStyle(fontSize: 16)),
                  trailing: const Icon(Icons.edit),
                  onTap: ini == null ? null : _elegirHoraComida,
                ),
            ],

            // Observaciones (v3.12, opcionales)
            if (widget.conObservaciones)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.notes),
                title: Text(_obs.isEmpty ? 'Añadir observaciones' : 'Observaciones'),
                subtitle: _obs.isEmpty
                    ? null
                    : Text(_obs, maxLines: 3, overflow: TextOverflow.ellipsis),
                trailing: Icon(_obs.isEmpty ? Icons.add : Icons.edit),
                onTap: _editarObs,
              ),
          ],
        ),
      ),
    );
  }
}