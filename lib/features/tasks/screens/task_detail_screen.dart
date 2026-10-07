import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'deca_section.dart';
import 'jornada_aviso.dart';
import '../../../shared/odoo_dt.dart';
import '../../../core/network/api_exception.dart';
import '../../../shared/location.dart';
import '../../../shared/widgets/upgrade_required.dart';
import '../../auth/session_controller.dart';
import '../task_models.dart';
import '../tasks_providers.dart';
import '../tasks_repository.dart';

import 'signature_screen.dart';
import 'cierre_recurso.dart';
import 'resumen_albaran_view.dart';


class TaskDetailScreen extends ConsumerStatefulWidget {
  const TaskDetailScreen({super.key, required this.taskId, this.readOnly = false});
  final int taskId;
  final bool readOnly;

  @override
  ConsumerState<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends ConsumerState<TaskDetailScreen> {
  bool _notesShown = false;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(taskDetailProvider(widget.taskId));

    // Popup automático de notas del chófer al abrir, si las hay.
    ref.listen(taskDetailProvider(widget.taskId), (prev, next) {
      final t = next.asData?.value;
      if (t != null && !_notesShown && (t.notasChofer?.trim().isNotEmpty ?? false)) {
        _notesShown = true;
        WidgetsBinding.instance.addPostFrameCallback((_) => _showNotes(t.notasChofer!));
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Servicio'),
        actions: [
          async.maybeWhen(
            data: (t) => IconButton(
              tooltip: 'Notas del chófer',
              icon: const Icon(Icons.sticky_note_2_outlined),
              onPressed: () => _showNotes(t.notasChofer ?? ''),
            ),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => e is ApiException && e.upgradeRequired
            ? UpgradeRequiredView(error: e)
            : Center(child: Text('$e')),
        data: (t) => _Body(task: t),
      ),
      bottomNavigationBar: widget.readOnly
          ? null
          : async.maybeWhen(
              data: (t) => _actionsBar(t),
              orElse: () => null,
            ),
    );
  }

  // ---------- Notas ----------
  void _showNotes(String notas) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.sticky_note_2_outlined),
          SizedBox(width: 8),
          Text('Notas del chófer'),
        ]),
        content: SingleChildScrollView(
          child: Text(notas.trim().isEmpty ? 'Sin notas.' : notas),
        ),
        actions: [
          if (!widget.readOnly)
            TextButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _addComment();
              },
              icon: const Icon(Icons.add_comment),
              label: const Text('Añadir comentario'),
            ),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar')),
        ],
      ),
    );
  }

  Future<void> _addComment() async {
    final ctrl = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Añadir comentario'),
        content: TextField(
          controller: ctrl,
          maxLines: 4,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Tu comentario…'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(context, ctrl.text.trim()),
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

  // ---------- Acciones ----------

  Widget? _actionsBar(TaskDetail t) {
    final parts = <Widget>[];
    if (t.hasSignature) {
      parts.add(OutlinedButton.icon(
        onPressed: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => SignatureScreen(task: t))),
        icon: const Icon(Icons.visibility),
        label: const Text('Ver firma'),
      ));
    }
    if (t.stage.alias != 'Finalizada') {
      parts.add(FilledButton.icon(
        style: FilledButton.styleFrom(backgroundColor: Colors.green.shade700),
        onPressed: _busy ? null : () => _finalizarTarea(t),
        icon: const Icon(Icons.check_circle),
        label: const Text('Finalizar tarea'),
      ));
    }
    if (parts.isEmpty) return null;
    final row = <Widget>[];
    for (var i = 0; i < parts.length; i++) {
      if (i > 0) row.add(const SizedBox(width: 8));
      row.add(Expanded(child: parts[i]));
    }
    return SafeArea(child: Padding(padding: const EdgeInsets.all(12), child: Row(children: row)));
  }

  Future<void> _finalizarTarea(TaskDetail t) async {
    // Guarda: no se puede finalizar una tarea que no se ha iniciado. Se mira
    // 'iniciada' (no 'pendientes'), para no bloquear el caso legítimo de
    // recursos ya iniciados y cerrados que van a firma.
    if (!t.recursos.any((r) => r.esMio && r.iniciada)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Inicia la tarea antes de finalizarla.')));
      return;
    }
    try {
      final pendientes = t.recursos.where((r) => r.esMio && r.iniciada && !r.cerrada).toList();
      for (final r in pendientes) {
        final ok = await cerrarRecursoDialog(context, ref, r);
        if (!ok || !mounted) return;
      }
      ref.invalidate(taskDetailProvider(t.id));
      final fresh = await ref.read(tasksRepoProvider).detail(t.id);
      if (!mounted) return;
      await Navigator.push(context, MaterialPageRoute(builder: (_) => SignatureScreen(task: fresh)));
      ref.invalidate(taskDetailProvider(t.id));
      ref.invalidate(tasksListProvider);
    } catch (e) {
      if (mounted) await mostrarErrorAccion(context, e);
    }
  }



  Future<void> _reopen(TaskDetail t) async {
    setState(() => _busy = true);
    try {
      await ref.read(tasksRepoProvider).reopen(t.id);
      // Al reabrir, retira del libro las pausas imputadas de sus recursos para
      // que no cuenten si la tarea ya no se vuelve a cerrar.
      for (final r in t.recursos) {
        await ref.read(journeyLedgerProvider).removeDeclared(r.id);
      }
      ref.invalidate(taskDetailProvider(t.id));
      ref.invalidate(tasksListProvider);
    } catch (e) {
      if (mounted) await mostrarErrorAccion(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  }

// ============================ Cuerpo (presentación) ============================
class _Body extends ConsumerWidget {            // ← era StatelessWidget
  const _Body({required this.task});
  final TaskDetail task;                          // ← SOLO task como campo. NADA de mostrarReales aquí.

  @override
  Widget build(BuildContext context, WidgetRef ref) {   // ← añade WidgetRef ref
    final scheme = Theme.of(context).colorScheme;
    final mostrarReales =                          // ← AQUÍ, variable LOCAL dentro de build
        ref.read(sessionControllerProvider).profile?.config.mostrarHorasReales ?? false;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Cabecera
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(task.name,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            _StageChip(alias: task.stage.alias, name: task.stage.name),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 4, children: [
          if (task.recargo != null)
            _Tag(icon: Icons.bolt, label: task.recargo!, color: Colors.deepPurple),
          if (task.iniciada)
            _Tag(icon: Icons.play_circle, label: 'Iniciada', color: Colors.blue),
          if (task.hasSignature)
            _Tag(icon: Icons.draw, label: 'Firmada', color: Colors.green),
        ]),
        const SizedBox(height: 8),

        _Section(icon: Icons.event, title: 'Servicio', color: scheme.primary, rows: [
          if (task.fechaServicio != null)
            _kv('Fecha/Hora', task.fechaServicio!.toLocal().toString().substring(0, 16)),
          if (task.vehicle != null) _kv('Vehículo', task.vehicle!),
          if (task.albaran != null) _kv('Albarán', task.albaran!),
          if (task.horaSalida != null)
            _kv('Salida', task.horaSalida!.toLocal().toString().substring(0, 16)),
          if (task.aperturaHora != null)
            _kv('Inicio', task.aperturaHora!.toLocal().toString().substring(0, 16)),
          if (task.cierreHora != null)
            _kv('Cierre', task.cierreHora!.toLocal().toString().substring(0, 16)),
        ]),
        DecaSection(deca: task.deca, titulo: task.albaran ?? task.name),

        _RecursosSection(madreId: task.id, recursos: task.recursos),

        if (task.accesorios.isNotEmpty)
          _Section(icon: Icons.handyman, title: 'Accesorios a cargar',
              color: scheme.primary, rows: [
            for (final acc in task.accesorios) _AccesorioTile(acc: acc),
          ]),
        _AddressCard(title: 'Carga', icon: Icons.upload, color: Colors.orange.shade800, a: task.carga),
        _AddressCard(title: 'Descarga', icon: Icons.download, color: Colors.teal.shade700, a: task.descarga),

        if ((task.descripcionServicio ?? '').trim().isNotEmpty)
          _Section(icon: Icons.notes, title: 'Observaciones del Servicio', color: scheme.primary, rows: [
            Text(task.descripcionServicio!.trim()),
          ]),

        _Section(icon: Icons.assignment_turned_in, title: 'Hoja de trabajo', color: scheme.primary, rows: [
          if (mostrarReales)
            _kv('Horas reales', task.worksheet.horasReales.toStringAsFixed(2)),
          if (task.resumenAlbaran != null)
            ResumenAlbaranView(resumen: task.resumenAlbaran!)
          else ...[
            if ((task.worksheet.obsAlbaran ?? '').isNotEmpty) _kv('Obs. conductor', task.worksheet.obsAlbaran!),
            if ((task.worksheet.obsCliente ?? '').isNotEmpty) _kv('Obs. cliente', task.worksheet.obsCliente!),
          ],
          _kv('Firma', task.worksheet.hasSignature ? '✔ recogida' : '— pendiente'),
        ]),
        const SizedBox(height: 80),
      ],
    );
  }
}

Widget _kv(String k, String v) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 120, child: Text(k, style: const TextStyle(color: Colors.black54))),
        Expanded(child: Text(v)),
      ]),
    );

class _Section extends StatelessWidget {
  const _Section({required this.icon, required this.title, required this.color, required this.rows});
  final IconData icon;
  final String title;
  final Color color;
  final List<Widget> rows;
  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: color)),
            ]),
            const SizedBox(height: 8),
            ...rows,
          ]),
        ),
      );
}

class _AddressCard extends StatelessWidget {
  const _AddressCard({required this.title, required this.icon, required this.color, required this.a});
  final String title;
  final IconData icon;
  final Color color;
  final Address a;

  Future<void> _abrirMaps(BuildContext context, String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo abrir el mapa.')));
    }
  }

  /// Abre el marcador con el número precargado (un toque para llamar).
  /// Normaliza el número a dígitos y '+' por si Odoo lo trae con espacios.
  Future<void> _llamar(BuildContext context, String numero) async {
    final tel = numero.replaceAll(RegExp(r'[^0-9+]'), '');
    if (tel.isEmpty) return;
    final uri = Uri.parse('tel:$tel');
    final ok = await launchUrl(uri);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo abrir el marcador.')));
    }
  }

  /// Fila de teléfono pulsable, con el mismo layout etiqueta/valor que _kv.
  Widget _telRow(BuildContext context, String numero) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SizedBox(
            width: 120,
            child: Text('Teléfono', style: TextStyle(color: Colors.black54)),
          ),
          Expanded(
            child: InkWell(
              onTap: () => _llamar(context, numero),
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(children: [
                  const Icon(Icons.phone, size: 16, color: Colors.blue),
                  const SizedBox(width: 6),
                  Flexible(child: Text(numero, style: const TextStyle(color: Colors.blue))),
                ]),
              ),
            ),
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final lines = [a.direccion, a.poblacion, a.codigoPostal].where((e) => (e ?? '').isNotEmpty).join(', ');
    return _Section(icon: icon, title: title, color: color, rows: [
      if (lines.isNotEmpty) _kv('Dirección', lines),
      if ((a.contacto ?? '').isNotEmpty) _kv('Contacto', a.contacto!),
      if ((a.telefono ?? '').isNotEmpty) _telRow(context, a.telefono!),
      if ((a.url ?? '').isNotEmpty)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => _abrirMaps(context, a.url!),
            icon: const Icon(Icons.map, size: 18),
            label: const Text('Ver en Maps'),
          ),
        ),
    ]);
  }
}

class _AccesorioTile extends StatelessWidget {
  const _AccesorioTile({required this.acc});
  final Accesorio acc;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          const Icon(Icons.handyman, size: 18, color: Colors.brown),
          const SizedBox(width: 8),
          Expanded(child: Text(acc.recurso)),
          Text('×${acc.cantidad}', style: const TextStyle(color: Colors.black54)),
        ]),
      );
}

class _StageChip extends StatelessWidget {
  const _StageChip({required this.alias, required this.name});
  final String? alias;
  final String name;
  @override
  Widget build(BuildContext context) {
    final color = switch (alias) {
      'Finalizada' => Colors.green,
      'Informado' => Colors.blue,
      _ => Colors.grey,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(name, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12)),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.icon, required this.label, required this.color});
  final IconData icon;
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
      );
}
class _RecursosSection extends ConsumerStatefulWidget {
  const _RecursosSection({required this.madreId, required this.recursos});
  final int madreId;
  final List<Recurso> recursos;
  @override
  ConsumerState<_RecursosSection> createState() => _RecursosSectionState();

}

class _RecursosSectionState extends ConsumerState<_RecursosSection> {
  bool _busy = false;

  bool get _detallista {
    final c = ref.read(sessionControllerProvider).profile?.config;
    return c != null && c.mostrarInicioCierre && !c.capturaManualHoras;
  }

  Future<void> _pausarActivo(int exceptoId) async {
    for (final r in widget.recursos) {
      if (r.esMio && r.hayTramoAbierto && r.id != exceptoId) {
        await ref.read(tasksRepoProvider).pause(r.id);
      }
    }
  }

  Future<void> _run(Future<void> Function() body) async {
    setState(() => _busy = true);
    try {
      await body();
      ref.invalidate(taskDetailProvider(widget.madreId));
      ref.invalidate(tasksListProvider);
    } catch (e) {
      if (mounted) await mostrarErrorAccion(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

    Future<void> _avisoJornada(JornadaStart? j) => tratarJornada(context, ref, j);

  Future<void> _iniciar(Recurso r) async {
    final planificada =
        ref.read(sessionControllerProvider).profile?.config.inicioPlanificado ?? false;
    DateTime? hora;
    if (planificada) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Iniciar servicio'),
          content: const Text('¿Iniciar ahora? La hora de apertura la pone la planificación.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Iniciar')),
          ],
        ),
      );
      if (ok != true) return;
    } else {
      hora = await pickFriendlyTime(context);
      if (hora == null) return;
    }
    await _run(() async {
      final (lat, lng) = await bestEffortLocation();
      await _pausarActivo(r.id);
      // En planificada no se envía informada: el servidor usa su hora.
      final res = await ref.read(tasksRepoProvider).start(
            r.id,
            lat: lat,
            lng: lng,
            informada: planificada ? null : hora,
          );
      await _avisoJornada(res.jornada);
    });
  }

  Future<void> _reanudar(Recurso r) => _run(() async {
        final (lat, lng) = await bestEffortLocation();
        await _pausarActivo(r.id);
        final res = await ref.read(tasksRepoProvider).start(r.id, lat: lat, lng: lng);
        await _avisoJornada(res.jornada);
      });

  Future<void> _pausar(Recurso r) => _run(() async {
        final (lat, lng) = await bestEffortLocation();
        await ref.read(tasksRepoProvider).pause(r.id, lat: lat, lng: lng);
      });

  Future<void> _cerrar(Recurso r) async {
        try {
          final ok = await cerrarRecursoDialog(context, ref, r);
          if (ok) {
            ref.invalidate(taskDetailProvider(widget.madreId));
            ref.invalidate(tasksListProvider);
          }
        } catch (e) {
          if (mounted) await mostrarErrorAccion(context, e, prefijo: 'No se pudo cerrar: ');
        }
      }
  @override
  Widget build(BuildContext context) {
    if (widget.recursos.isEmpty) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: const [
            Icon(Icons.list_alt, size: 18),
            SizedBox(width: 8),
            Text('Recursos del servicio', style: TextStyle(fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 8),
          for (final r in widget.recursos) _fila(r),
        ]),
      ),
    );
  }

  Widget _fila(Recurso r) {
    // Verde = mío; gris = de otro operario (lectura).
    final mio = r.esMio;
    final color = mio ? Colors.green.shade800 : Colors.black54;
    final estado = r.cerrada
        ? 'Cerrada'
        : r.hayTramoAbierto
            ? 'En proceso'
            : (r.iniciada ? 'En pausa' : '');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Icon(mio ? Icons.precision_manufacturing : Icons.lock_outline, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(r.recurso, style: TextStyle(color: color, fontWeight: FontWeight.w500)),
            if (!mio && r.empleado != null)
              Text(r.empleado!, style: const TextStyle(color: Colors.black45, fontSize: 12)),
            if (estado.isNotEmpty)
              Text(estado, style: TextStyle(color: color, fontSize: 12)),
          ]),
        ),
        if (mio && !r.cerrada) ..._botones(r),
      ]),
    );
  }

  List<Widget> _botones(Recurso r) {
    if (_busy) return [const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))];
    if (!r.iniciada) {
      return [
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: Colors.green.shade700,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            minimumSize: const Size(0, 36),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onPressed: () => _iniciar(r),
          icon: const Icon(Icons.play_arrow, size: 18),
          label: const Text('Iniciar'),
        ),
      ];
    }
    final acciones = <Widget>[];
    if (_detallista && r.hayTramoAbierto) {
      acciones.add(IconButton(icon: const Icon(Icons.pause, color: Colors.orange), tooltip: 'Pausar', onPressed: () => _pausar(r)));
    } else if (_detallista && !r.hayTramoAbierto) {
      acciones.add(IconButton(icon: const Icon(Icons.play_arrow, color: Colors.green), tooltip: 'Reanudar', onPressed: () => _reanudar(r)));
    }
    acciones.add(IconButton(icon: const Icon(Icons.stop_circle, color: Colors.red), tooltip: 'Cerrar', onPressed: () => _cerrar(r)));
    return acciones;
  }
}
Future<DateTime?> pickFriendlyTime(BuildContext context) async {

  final choice = await showModalBottomSheet<String>(
    context: context,
    builder: (_) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(leading: const Icon(Icons.schedule), title: const Text('Ahora'),
              onTap: () => Navigator.pop(context, 'now')),
          ListTile(leading: const Icon(Icons.history), title: const Text('Hace 30 min'),
              onTap: () => Navigator.pop(context, 'm30')),
          ListTile(leading: const Icon(Icons.history), title: const Text('Hace 1 hora'),
              onTap: () => Navigator.pop(context, 'h1')),
          ListTile(leading: const Icon(Icons.edit_calendar), title: const Text('Otra hora…'),
              onTap: () => Navigator.pop(context, 'custom')),
        ],
      ),
    ),
  );
  if (!context.mounted) return null;
  switch (choice) {                                    // ← AHORA aquí
    case 'now':
      return DateTime.now();
    case 'm30':
      return DateTime.now().subtract(const Duration(minutes: 30));
    case 'h1':
      return DateTime.now().subtract(const Duration(hours: 1));
    case 'custom':
      return _pickCustom(context);
    default:
      return null;
  }
}

/// Reloj "Otra hora…": la hora elegida se ancla a su ocurrencia pasada más
/// reciente (hoy; ahora si es futura ≤ 15 min; ayer si es más futura).
/// Nunca devuelve una hora futura.
Future<DateTime?> _pickCustom(BuildContext context) async {
  final tm = await showTimePicker(context: context, initialTime: TimeOfDay.now());
  if (tm == null) return null;
  return anclarAlPasado(tm.hour, tm.minute);
}