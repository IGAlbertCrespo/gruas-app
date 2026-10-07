import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../shared/duracion_sospechosa.dart';
import '../../../shared/horas.dart';
import '../../../shared/location.dart';
import '../../../shared/pausa_dialog.dart' show fmtHoras;
import '../../../shared/widgets/upgrade_required.dart';
import '../task_models.dart';
import '../tasks_providers.dart';
import 'jornada_aviso.dart';
import 'task_detail_screen.dart' show pickFriendlyTime;

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
              tooltip: 'Añadir comentario',
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
      if ((t.notasChofer ?? '').trim().isNotEmpty) ...[
        const SizedBox(height: 12),
        _bloque('Notas del chófer', t.notasChofer!.trim()),
      ],
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
    final v = await _pedirInicioFin(t);
    if (v == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final (lat, lng) = await bestEffortLocation();
      if (!mounted) return;
      final res = await conConfirmacionDuracion(
        context,
        (confirmar) => ref.read(tasksRepoProvider).complete(t.id,
            inicio: v.inicio, fin: v.fin, confirmar: confirmar, lat: lat, lng: lng),
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

  /// Hoja de inicio/fin. Primera vez SIN precarga; al modificar, las horas ya
  /// informadas (el conductor solo corrige lo que está mal).
  Future<({DateTime inicio, DateTime fin})?> _pedirInicioFin(TaskDetail t) {
    DateTime? inicio = t.completada ? t.aperturaInformada : null;
    DateTime? fin = t.completada ? t.cierreInformada : null;

    return showModalBottomSheet<({DateTime inicio, DateTime fin})>(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          Future<void> elegir(bool esInicio) async {
            final h = await pickFriendlyTime(ctx);
            if (h == null) return;
            setSheet(() {
              if (esInicio) {
                inicio = h;
              } else {
                fin = h;
              }
            });
          }

          final listo = inicio != null && fin != null;
          final cruza = listo && !fin!.isAfter(inicio!);
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
                  _selector(ctx, 'Inicio', inicio, () => elegir(true)),
                  _selector(ctx, 'Fin', fin, () => elegir(false)),
                  if (listo)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Duración: ${fmtHoras(horasEntre(inicio!, fin!))}'
                        '${cruza ? '  (cruza la medianoche)' : ''}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  const SizedBox(height: 12),
                  FilledButton(
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    onPressed: listo
                        ? () => Navigator.pop(sheetCtx, (inicio: inicio!, fin: fin!))
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

  Future<void> _addComment() async {
    final ctrl = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Añadir comentario'),
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