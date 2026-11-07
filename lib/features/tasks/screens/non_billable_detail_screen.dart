import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../shared/duracion_sospechosa.dart';
import '../../../shared/horas.dart';
import '../../../shared/horas_totales_dialog.dart';
import '../../../shared/selector_hora.dart';
import '../../../shared/location.dart';
import '../../../shared/observaciones_dialog.dart';
import '../../../shared/pausa_dialog.dart' show fmtHoras;
import '../../../shared/widgets/upgrade_required.dart';
import '../../../shared/formulario_tiempo.dart';
import '../task_models.dart';
import '../tasks_providers.dart';
import '../../auth/session_controller.dart';
import '../../auth/session_models.dart';
import 'jornada_aviso.dart';
import 'observaciones_albaran.dart';


String _two(int n) => n.toString().padLeft(2, '0');

/// Detalle de una tarea NO FACTURABLE (tarea interna).
///
/// Sin hoja de trabajo, firma ni recursos: el conductor informa inicio y fin
/// (/complete). Repetible durante el día (oficina no las valida); al día
/// siguiente dejan de aparecer en la lista.
class NonBillableDetailScreen extends ConsumerStatefulWidget {
  const NonBillableDetailScreen({super.key, required this.taskId, this.readOnly = false});

  final int taskId;
  final bool readOnly;

  @override
  ConsumerState<NonBillableDetailScreen> createState() => _NonBillableDetailScreenState();
}

class _NonBillableDetailScreenState extends ConsumerState<NonBillableDetailScreen> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(taskDetailProvider(widget.taskId));
    final t = async.valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tarea interna'),
        actions: [
          if (!widget.readOnly && t != null)
            IconButton(
              icon: const Icon(Icons.add_comment),
              tooltip: 'Comentario para oficina',
              onPressed: _busy ? null : _addComment,
            ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => (e is ApiException && e.upgradeRequired)
            ? Center(child: SingleChildScrollView(child: UpgradeRequiredView(error: e)))
            : Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('$e'))),
        data: (t) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(taskDetailProvider(widget.taskId)),
          child: ListView(padding: const EdgeInsets.all(16), children: _contenido(t)),
        ),
      ),
      bottomNavigationBar: (t == null || widget.readOnly)
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  onPressed: _busy ? null : () => _completar(t),
                  icon: _busy
                      ? const SizedBox(
                          width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(t.completada ? Icons.edit : Icons.check_circle),
                  label: Text(t.completada ? 'Modificar horas' : 'Completar'),
                ),
              ),
            ),
    );
  }

  // ---------- Contenido ----------

  List<Widget> _contenido(TaskDetail t) {
    final ini = t.aperturaInformada;
    final fin = t.cierreInformada;
    return [
      Text(t.name, style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 4, children: [
        _chip(Icons.engineering, t.tipoInterna ?? 'Tarea interna', Colors.amber),
        if (t.completada)
          _chip(Icons.check_circle, 'Completada', Colors.green)
        else
          _chip(Icons.pending_actions, 'Pendiente', Colors.blueGrey),
      ]),
      const SizedBox(height: 12),
      if (t.partner != null) _fila(Icons.business, 'Cliente', t.partner!),
      if (t.albaran != null) _fila(Icons.receipt_long, 'Albarán', t.albaran!),
      if (t.vehicle != null) _fila(Icons.local_shipping, 'Vehículo', t.vehicle!),
      if (t.fechaServicio != null) _fila(Icons.event, 'Fecha', _fechaHora(t.fechaServicio!)),
      if (t.completada && ini != null && fin != null)
        _fila(Icons.schedule, 'Horas',
            '${_hm(ini)} – ${_hm(fin)}  (${fmtHoras(horasEntre(ini, fin))})'),
      if ((t.descripcionServicio ?? '').trim().isNotEmpty) ...[
        const SizedBox(height: 12),
        _bloque('Descripción', t.descripcionServicio!.trim()),
      ],
      // v3.12: las notas (descripción de Tráfico + comentarios) en un enlace.
      if ((t.notasChofer ?? '').trim().isNotEmpty)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            style: TextButton.styleFrom(padding: EdgeInsets.zero),
            onPressed: () => _verNotas(t.notasChofer!.trim()),
            icon: const Icon(Icons.description_outlined, size: 18),
            label: const Text('Ver notas del chófer'),
          ),
        ),
      // v3.12 §4.9: observaciones (en no facturables no las ve ningún cliente).
      const SizedBox(height: 12),
      ObsAlbaranTile(
        texto: t.obsAlbaran,
        onEditar: (!widget.readOnly && t.obsEditable)
            ? () => editarObsAlbaran(context, ref,
                taskId: t.id, inicial: t.obsAlbaran, avisoCliente: false)
            : null,
      ),
    ];
  }

  Widget _chip(IconData icon, String text, MaterialColor c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: c.shade100, borderRadius: BorderRadius.circular(6)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 16, color: c.shade800),
          const SizedBox(width: 4),
          Text(text, style: TextStyle(fontWeight: FontWeight.bold, color: c.shade800)),
        ]),
      );

  Widget _fila(IconData icon, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 18, color: Colors.black54),
          const SizedBox(width: 8),
          SizedBox(width: 80, child: Text(label, style: const TextStyle(color: Colors.black54))),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w500))),
        ]),
      );

  /// v3.12: texto completo de las notas del chófer en una hoja desplazable.
  void _verNotas(String notas) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (ctx) => SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Notas del chófer', style: Theme.of(ctx).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Flexible(child: SingleChildScrollView(child: SelectableText(notas))),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Cerrar'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  Widget _bloque(String titulo, String texto) => Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(titulo, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(texto),
          ]),
        ),
      );

  String _hm(DateTime d) {
    final l = d.toLocal();
    return '${_two(l.hour)}:${_two(l.minute)}';
  }

  String _fechaHora(DateTime d) {
    final l = d.toLocal();
    return '${_two(l.day)}/${_two(l.month)}/${l.year} ${_hm(l)}';
  }

  /// "Hoy 08:00" / "Ayer 23:30" / "27/09 10:00": el anclaje al pasado puede
  /// llevar la hora a ayer, y el conductor debe verlo antes de confirmar.
  /// Días comparados en UTC para no fallar en los cambios de horario.
  String _diaHora(DateTime d) {
    final l = d.toLocal();
    final n = DateTime.now();
    final dias = DateTime.utc(n.year, n.month, n.day)
        .difference(DateTime.utc(l.year, l.month, l.day))
        .inDays;
    final pre = dias == 0 ? 'Hoy' : dias == 1 ? 'Ayer' : '${_two(l.day)}/${_two(l.month)}';
    return '$pre ${_hm(l)}';
  }

  // ---------- Acciones ----------

  Future<void> _completar(TaskDetail t) async {
    if (ref.read(sessionControllerProvider).profile?.config.soloHoras ?? false) {
      return _completarHoras(t);
    }
    final v = await _pedirInicioFin(t);
    if (v == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final (lat, lng) = await bestEffortLocation();
      if (!mounted) return;
      final res = await conConfirmacionDuracion(
        context,
        (confirmar) => ref.read(tasksRepoProvider).complete(t.id,
            inicio: v.inicio, fin: v.fin, obsAlbaran: v.obs,
            confirmar: confirmar, lat: lat, lng: lng),
      );
      if (res == null) return; // eligió revisar: el servidor no ha guardado nada
      ref.invalidate(taskDetailProvider(t.id));
      ref.invalidate(tasksListProvider);
      if (mounted) await tratarJornada(context, ref, res.jornada);
    } catch (e) {
      if (mounted) await mostrarErrorAccion(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
    /// Solo horas (v3.10 §4.5.3): día de ejecución (planificado … hoy) y el tiempo
  /// con los formatos de la compañía. Tiempo real, sin redondeo.
  Future<void> _completarHoras(TaskDetail t) async {
    final cfg = ref.read(sessionControllerProvider).profile?.config ?? SessionConfig.fallback;
    final dia = await _pedirDia(t);
    if (dia == null || !mounted) return;

    // Al modificar, se precargan el inicio y las horas ya informados de ese día.
    final ap = t.aperturaInformada, ci = t.cierreInformada;
    final previa = t.completada && ap != null && soloDia(ap) == dia;
    final plan = t.fechaServicio?.toLocal();
    final propuesto = previa
        ? ap.toLocal()
        : DateTime(dia.year, dia.month, dia.day, plan?.hour ?? 8, plan?.minute ?? 0);
    final horas = (previa && ci != null) ? horasEntre(ap, ci) : t.horasPrevistas;

    final tiempo = await pedirTiempo(
      context,
      formatos: cfg.formatosCierre,
      cfg: cfg,
      inicioPropuesto: propuesto,
      dia: dia,
      horasPrevistas: horas,
      titulo: t.completada ? 'Modificar horas' : 'Completar tarea',
      subtitulo: 'Día ${fmtDia(dia)}',
      conObservaciones: true, // v3.12: enlace opcional
      obsInicial: t.obsAlbaran,
    );
    if (tiempo == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final (lat, lng) = await bestEffortLocation();
      if (!mounted) return;
      final res = await conConfirmacionDuracion(
        context,
        (confirmar) => ref.read(tasksRepoProvider).completeTiempo(t.id,
            fecha: dia, tiempo: tiempo, confirmar: confirmar, lat: lat, lng: lng),
      );
      if (res == null) return; // eligió revisar
      ref.invalidate(taskDetailProvider(t.id));
      ref.invalidate(tasksListProvider);
      if (mounted) await tratarJornada(context, ref, res.jornada);
    } catch (e) {
      if (mounted) await mostrarErrorAccion(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Día de ejecución entre el planificado y hoy. Si solo puede ser hoy, no pregunta.
  Future<DateTime?> _pedirDia(TaskDetail t) async {
    final hoy = soloDia(DateTime.now());
    final primero = t.fechaServicio == null ? hoy : soloDia(t.fechaServicio!);
    if (primero.isAfter(hoy)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Esta tarea está programada para el ${fmtDia(primero)}.')));
      return null;
    }
    if (!primero.isBefore(hoy)) return hoy;
    final ap = t.aperturaInformada;
    var inicial = t.completada && ap != null ? soloDia(ap) : hoy;
    if (inicial.isBefore(primero) || inicial.isAfter(hoy)) inicial = hoy;
    return showDatePicker(
      context: context,
      initialDate: inicial,
      firstDate: primero,
      lastDate: hoy,
      helpText: 'Día en que se hizo',
    );
  }


  /// Hoja de inicio/duración (v3).
  /// - Inicio entre el día programado y hoy (lo normal, hoy).
  /// - Fin: "¿Cuánto duró?" en horas desde el inicio. Máximo = tiempo
  ///   transcurrido, así el fin nunca es futuro.
  /// Al modificar, se precargan los valores ya informados.
  Future<({DateTime inicio, DateTime fin, String? obs})?> _pedirInicioFin(TaskDetail t) {
    DateTime? inicio = t.completada ? t.aperturaInformada : null;
    var obs = (t.obsAlbaran ?? '').trim(); // v3.12: opcional
    double? duracion = (t.completada && t.aperturaInformada != null && t.cierreInformada != null)
        ? round30(horasEntre(t.aperturaInformada!, t.cierreInformada!))
        : null;
    final desde = t.fechaServicio ?? DateTime.now(); // sin fecha programada: solo hoy

    return showModalBottomSheet<({DateTime inicio, DateTime fin, String? obs})>(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          Future<void> elegirInicio() async {
            final h = await pickFechaHoraInicio(ctx, desde: desde, inicial: inicio);
            if (h == null) return;
            setSheet(() {
              inicio = h;
              if (duracion != null) {
                duracion = duracion!.clamp(horasTotalesMin, horasMaxHasta(h)).toDouble();
              }
            });
          }

          Future<void> elegirDuracion() async {
            final ini = inicio;
            if (ini == null) return;
            final res = await pickHorasTotales(
              ctx,
              inicial: duracion ?? horasTotalesIniciales(apertura: ini),
              apertura: ini,
              titulo: '¿Cuánto duró?',
              maximo: horasMaxHasta(ini),
            );
            if (res == null) return;
            setSheet(() => duracion = res.horas);
          }

          Future<void> editarObs() async {
            final res = await pedirObsAlbaran(ctx,
                inicial: obs, avisoCliente: false, titulo: 'Observaciones', accion: 'Aceptar');
            if (res != null) setSheet(() => obs = res);
          }

          final fin = (inicio != null && duracion != null)
              ? inicio!.add(Duration(minutes: (duracion! * 60).round()))
              : null;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(t.completada ? 'Modificar horas' : 'Completar tarea',
                      style: Theme.of(ctx).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  _selector(ctx, 'Inicio', inicio, elegirInicio),
                  _selectorDuracion(ctx, duracion, inicio == null ? null : elegirDuracion),
                  if (fin != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('Fin: ${_diaHora(fin)}',
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.notes),
                    title: Text(obs.isEmpty ? 'Añadir observaciones' : 'Observaciones'),
                    subtitle: obs.isEmpty
                        ? null
                        : Text(obs, maxLines: 2, overflow: TextOverflow.ellipsis),
                    trailing: Icon(obs.isEmpty ? Icons.add : Icons.edit),
                    onTap: editarObs,
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    onPressed: fin != null
                        ? () => Navigator.pop(sheetCtx,
                            (inicio: inicio!, fin: fin, obs: obs.isEmpty ? null : obs))
                        : null,
                    child: Text(t.completada ? 'Guardar' : 'Completar'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(sheetCtx),
                    child: const Text('Cancelar'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }


  Widget _selector(BuildContext ctx, String label, DateTime? valor, VoidCallback onTap) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.schedule),
        title: Text(label),
        trailing: Text(
          valor == null ? 'Elegir…' : _diaHora(valor),
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: valor == null ? Theme.of(ctx).colorScheme.primary : null,
          ),
        ),
        onTap: onTap,
      );

   Widget _selectorDuracion(BuildContext ctx, double? valor, VoidCallback? onTap) => ListTile(
        contentPadding: EdgeInsets.zero,
        enabled: onTap != null, // deshabilitado hasta elegir el inicio
        leading: const Icon(Icons.timelapse),
        title: const Text('Duración'),
        trailing: Text(
          valor == null ? 'Elegir…' : fmtHoras(valor),
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: valor == null && onTap != null ? Theme.of(ctx).colorScheme.primary : null,
          ),
        ),
        onTap: onTap,
      );
  Future<void> _addComment() async {
    final ctrl = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Comentario para oficina'),
        content: TextField(
          controller: ctrl,
          maxLines: 4,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Tu comentario…'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Añadir'),
          ),
        ],
      ),
    );
    if (text == null || text.isEmpty) return;
    try {
      await ref.read(tasksRepoProvider).addNote(widget.taskId, text);
      ref.invalidate(taskDetailProvider(widget.taskId));
    } catch (e) {
      if (mounted) await mostrarErrorAccion(context, e);
    }
  }
}