import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/location.dart';
import '../../auth/session_controller.dart';
import '../task_models.dart';
import '../tasks_providers.dart';
import 'signature_screen.dart';

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
        error: (e, _) => Center(child: Text('$e')),
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  // ---------- Acciones ----------
  Widget? _actionsBar(TaskDetail t) {
    final alias = t.stage.alias;
    final parts = <Widget>[];

    // ¿Hay OTRA tarea en marcha? (iniciada y sin finalizar, distinta de esta).
    final lista = ref.read(tasksListProvider).valueOrNull;
    final otraEnMarcha =
        lista?.tasks.any((x) => x.id != t.id && x.iniciada && !x.cerrada) ?? false;

    // No se pueden hacer dos tareas a la vez: avisamos en lugar de dejar iniciar.
    if (alias == 'Informado' && !t.iniciada && otraEnMarcha) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Row(children: [
              Icon(Icons.info_outline, color: Colors.orange.shade800),
              const SizedBox(width: 10),
              Expanded(child: Text(
                'Tienes una tarea en proceso. Finalízala antes de iniciar otra.',
                style: TextStyle(color: Colors.orange.shade900))),
            ]),
          ),
        ),
      );
    }

    // Botón de etapa: Iniciar / Finalizar / Reabrir (excluyentes).
    if (alias == 'Informado' && !t.iniciada) {
      parts.add(FilledButton.icon(
        onPressed: _busy ? null : () => _start(t),
        icon: const Icon(Icons.play_arrow),
        label: const Text('Iniciar'),
      ));
    } else if (alias == 'Informado' && t.iniciada) {
      parts.add(FilledButton.icon(
        style: FilledButton.styleFrom(backgroundColor: Colors.green.shade700),
        onPressed: _busy ? null : () => _finish(t),
        icon: const Icon(Icons.check_circle),
        label: const Text('Finalizar'),
      ));
    } else if (alias == 'Finalizada') {
      parts.add(OutlinedButton.icon(
        onPressed: _busy ? null : () => _reopen(t),
        icon: const Icon(Icons.undo),
        label: const Text('Reabrir'),
      ));
    }

    // Firma: "Ver firma" siempre que esté firmada; "Firmar" solo si está iniciada
    // (no tiene sentido firmar una tarea sin iniciar).
    if (t.hasSignature) {
      parts.add(OutlinedButton.icon(
        onPressed: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => SignatureScreen(task: t))),
        icon: const Icon(Icons.visibility),
        label: const Text('Ver firma'),
      ));
    } else if (t.iniciada) {
      parts.add(OutlinedButton.icon(
        onPressed: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => SignatureScreen(task: t))),
        icon: const Icon(Icons.draw),
        label: const Text('Firmar'),
      ));
    }

    if (parts.isEmpty) return null;
    final row = <Widget>[];
    for (var i = 0; i < parts.length; i++) {
      if (i > 0) row.add(const SizedBox(width: 8));
      row.add(Expanded(child: parts[i]));
    }
    return SafeArea(
      child: Padding(padding: const EdgeInsets.all(12), child: Row(children: row)),
    );
  }
  /// Selector rápido de hora (UX para la calle): Ahora / Hace 30 min / Hace 1 h
  /// / Otra hora… (esta abre el reloj, con la fecha de hoy por defecto).
  Future<DateTime?> _pickTime() async {
    final now = DateTime.now();
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.schedule),
              title: const Text('Ahora'),
              onTap: () => Navigator.pop(context, 'now'),
            ),
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('Hace 30 min'),
              onTap: () => Navigator.pop(context, 'm30'),
            ),
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('Hace 1 hora'),
              onTap: () => Navigator.pop(context, 'h1'),
            ),
            ListTile(
              leading: const Icon(Icons.edit_calendar),
              title: const Text('Otra hora…'),
              onTap: () => Navigator.pop(context, 'custom'),
            ),
          ],
        ),
      ),
    );
    switch (choice) {
      case 'now':
        return DateTime.now();
      case 'm30':
        return DateTime.now().subtract(const Duration(minutes: 30));
      case 'h1':
        return DateTime.now().subtract(const Duration(hours: 1));
      case 'custom':
        return _pickCustom(now);
      default:
        return null;
    }
  }

  /// Reloj directo con la fecha de hoy; si pulsa el icono de calendario puede
  /// cambiar el día (caso raro).
  Future<DateTime?> _pickCustom(DateTime base) async {
    final tm = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(base));
    if (tm == null || !mounted) return null;
    return DateTime(base.year, base.month, base.day, tm.hour, tm.minute);
  }

  Future<void> _start(TaskDetail t) async {
    // La hora de inicio se puede ajustar (p.ej. si se olvidó iniciar a tiempo).
    final hora = await _pickTime();
    if (hora == null) return;
    setState(() => _busy = true);
    try {
      final (lat, lng) = await bestEffortLocation();

      // No se puede trabajar sin jornada: si el empleado tiene control de
      // presencia y no hay jornada abierta, se ficha entrada con la MISMA hora
      // informada de inicio de la tarea. Si falla, NO se inicia la tarea.
      final tieneAttendance =
          ref.read(sessionControllerProvider).profile?.capabilities.attendance ?? false;
      if (tieneAttendance) {
        final estado = await ref.read(attendanceRepoProvider).currentState();
        if (!estado.hasOpen) {
          await ref.read(attendanceRepoProvider).checkIn(_uuid(), lat: lat, lng: lng, at: hora);
          ref.invalidate(attendanceStateProvider);
        }
      }

      await ref.read(tasksRepoProvider).start(t.id, lat: lat, lng: lng, informada: hora);
      ref.invalidate(taskDetailProvider(t.id));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo iniciar: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _uuid() {
    final r = math.Random();
    return List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  Future<void> _reopen(TaskDetail t) async {
    setState(() => _busy = true);
    try {
      await ref.read(tasksRepoProvider).reopen(t.id);
      ref.invalidate(taskDetailProvider(t.id));
      ref.invalidate(tasksListProvider);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _finish(TaskDetail t) async {
    // 1) Hora de cierre (editable).
    final cierre = await _pickTime();
    if (cierre == null) return;

    // 2) Pausa/comida: obligatorio informarla (aunque sea "Ninguna").
    final pausa = await _pickPausa();
    if (pausa == null) return; // canceló: no finaliza

    // 3) Cálculo: horas (ceil 30) menos pausa; el mínimo se evalúa tras el descuento.
    final apertura = t.aperturaInformada ?? t.aperturaHora;
    double horas = 0;
    if (apertura != null) {
      final h = cierre.difference(apertura).inMinutes / 60.0;
      horas = (h * 2).ceil() / 2.0;
    }
    horas = (horas - pausa).clamp(0, double.infinity).toDouble();
    final esMinimo = t.worksheet.servicioMinimo > 0 && horas < t.worksheet.servicioMinimo;

    final ok = await _confirmFinish(horas, esMinimo);
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      final (lat, lng) = await bestEffortLocation();
      await ref.read(tasksRepoProvider).finish(t.id, lat: lat, lng: lng, informada: cierre, pausa: pausa);
      ref.invalidate(taskDetailProvider(t.id));
      ref.invalidate(tasksListProvider);
      // Nos quedamos en el detalle (ya finalizada); no volvemos a la lista.
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Pausa/comida del servicio (obligatorio elegir). Devuelve null si cancela.
  Future<double?> _pickPausa() {
    return showDialog<double>(
      context: context,
      barrierDismissible: false,
      builder: (_) => SimpleDialog(
        title: const Text('Tiempo de pausa / comida'),
        children: [
          for (final opt in const [
            ('Ninguna', 0.0),
            ('30 min', 0.5),
            ('1 hora', 1.0),
            ('1 h 30 min', 1.5),
            ('2 horas', 2.0),
          ])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, opt.$2),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(opt.$1, style: const TextStyle(fontSize: 16)),
              ),
            ),
        ],
      ),
    );
  }

  Future<bool?> _confirmFinish(double horas, bool esMinimo) {
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Finalizar servicio'),
        content: Text(esMinimo
            ? 'El tiempo informado es inferior al mínimo: se facturará el servicio mínimo. ¿Finalizar?'
            : 'Horas a facturar: ${horas.toStringAsFixed(1)} h. ¿Finalizar?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Finalizar')),
        ],
      ),
    );
  }
}

// ============================ Cuerpo (presentación) ============================
class _Body extends StatelessWidget {
  const _Body({required this.task});
  final TaskDetail task;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
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

        _AddressCard(title: 'Carga', icon: Icons.upload, color: Colors.orange.shade800, a: task.carga),
        _AddressCard(title: 'Descarga', icon: Icons.download, color: Colors.teal.shade700, a: task.descarga),

        if ((task.descripcionServicio ?? '').trim().isNotEmpty)
          _Section(icon: Icons.notes, title: 'Observaciones del Servicio', color: scheme.primary, rows: [
            Text(task.descripcionServicio!.trim()),
          ]),

        if (task.serviciosAsociados.isNotEmpty)
          _Section(icon: Icons.account_tree, title: 'Otros servicios asociados',
              color: scheme.primary, rows: [
            for (final a in task.serviciosAsociados) _AsociadoTile(a: a),
          ]),

        if (task.accesorios.isNotEmpty)
          _Section(icon: Icons.handyman, title: 'Accesorios a cargar',
              color: scheme.primary, rows: [
            for (final acc in task.accesorios) _AccesorioTile(acc: acc),
          ]),

        _Section(icon: Icons.assignment_turned_in, title: 'Hoja de trabajo', color: scheme.primary, rows: [
          _kv('Horas reales', task.worksheet.horasReales.toStringAsFixed(2)),
          if (task.worksheet.pausaServicio > 0)
            _kv('Pausa', '${task.worksheet.pausaServicio.toStringAsFixed(1)} h'),
          if (task.worksheet.aplicarMinimo)
            _kv('Facturación', 'Servicio mínimo')
          else
            _kv('Horas a facturar', task.worksheet.horasFacturar.toStringAsFixed(2)),
          if ((task.worksheet.obsAlbaran ?? '').isNotEmpty) _kv('Obs. albarán', task.worksheet.obsAlbaran!),
          if ((task.worksheet.obsCliente ?? '').isNotEmpty) _kv('Obs. cliente', task.worksheet.obsCliente!),
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
  @override
  Widget build(BuildContext context) {
    final lines = [a.direccion, a.poblacion, a.codigoPostal].where((e) => (e ?? '').isNotEmpty).join(', ');
    return _Section(icon: icon, title: title, color: color, rows: [
      if (lines.isNotEmpty) _kv('Dirección', lines),
      if ((a.contacto ?? '').isNotEmpty) _kv('Contacto', a.contacto!),
      if ((a.telefono ?? '').isNotEmpty) _kv('Teléfono', a.telefono!),
    ]);
  }
}
class _AsociadoTile extends StatelessWidget {
  const _AsociadoTile({required this.a});
  final ServicioAsociado a;

  String _estado() {
    if (a.estadoTimer == 'corriendo') return 'En proceso';
    if (a.estadoTimer == 'cerrado') return 'Cerrada';
    return '';
  }

  @override
  Widget build(BuildContext context) {
    // Verde = lo operas tú (pulsable); negro = otro operario (solo informativo).
    final color = a.esMio ? Colors.green.shade700 : Colors.black87;
    final estado = _estado();
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Icon(a.esMio ? Icons.person : Icons.person_outline, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(child: Text(a.recurso,
            style: TextStyle(color: color, fontWeight: FontWeight.w500))),
        if (estado.isNotEmpty)
          Text(estado, style: const TextStyle(color: Colors.black54, fontSize: 12)),
        if (a.esMio) const Icon(Icons.chevron_right, size: 18, color: Colors.green),
      ]),
    );
    if (!a.esMio) return row; // negro: no navegable
    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => TaskDetailScreen(taskId: a.id, readOnly: false)),
      ),
      child: row,
    );
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
