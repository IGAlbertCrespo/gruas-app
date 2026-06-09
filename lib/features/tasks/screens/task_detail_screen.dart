import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/location.dart';
import '../../auth/session_controller.dart';
import '../task_models.dart';
import '../tasks_providers.dart';
import 'signature_screen.dart';

/// Selector rápido de hora (UX para la calle): Ahora / Hace 30 min / Hace 1 h
/// / Otra hora… (esta abre el reloj, con la fecha de hoy por defecto).

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

    // Tareas en marcha que NO son esta (de la lista global).
    final lista = ref.read(tasksListProvider).valueOrNull;
    final enMarcha = (lista?.tasks ?? [])
        .where((x) => x.id != t.id && x.iniciada && !x.cerrada)
        .toList();

    // ¿Cuáles son del MISMO servicio? (hermanas operables corriendo).
    final idsServicio = {for (final a in t.serviciosAsociados) a.id};
    final mismaEnMarcha = enMarcha.where((x) => idsServicio.contains(x.id)).toList();
    final otraEnMarcha = enMarcha.where((x) => !idsServicio.contains(x.id)).toList();

    // Bloqueo solo si hay otra de OTRO servicio en marcha (las del mismo se concatenan).
    if (alias == 'Informado' && !t.iniciada && otraEnMarcha.isNotEmpty) {
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

    // Botón de etapa según el estado del timer.
    final pausado = t.iniciada && t.tieneTramos && !t.hayTramoAbierto && alias != 'Finalizada';
    if (alias == 'Informado' && !t.iniciada) {
      parts.add(FilledButton.icon(
        onPressed: _busy ? null : () => _start(t),   // primer inicio: pide hora
        icon: const Icon(Icons.play_arrow),
        label: const Text('Iniciar'),
      ));
    } else if (alias == 'Informado' && t.iniciada) {
      if (t.hayTramoAbierto) {
        parts.add(OutlinedButton.icon(
          onPressed: _busy ? null : () => _pause(t),
          icon: const Icon(Icons.pause),
          label: const Text('Pausar'),
        ));
      } else if (pausado) {
        parts.add(FilledButton.icon(
          onPressed: _busy ? null : () => _resume(t),  // reanudar: sin selector de hora
          icon: const Icon(Icons.play_arrow),
          label: const Text('Reanudar'),
        ));
      }
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

  /// Pausa las hermanas del mismo servicio que estén en marcha (concatenación).
  Future<void> _pausarHermanasEnMarcha(TaskDetail t, double? lat, double? lng) async {
    final lista = ref.read(tasksListProvider).valueOrNull;
    final idsServicio = {for (final a in t.serviciosAsociados) a.id};
    final corriendo = (lista?.tasks ?? [])
        .where((x) => x.id != t.id && x.iniciada && !x.cerrada && idsServicio.contains(x.id));
    for (final x in corriendo) {
      await ref.read(tasksRepoProvider).pause(x.id, lat: lat, lng: lng);
      ref.invalidate(taskDetailProvider(x.id));
    }
  }

  Future<void> _start(TaskDetail t) async {
    final hora = await pickFriendlyTime(context);          // primer inicio: hora ajustable
    if (hora == null) return;
    setState(() => _busy = true);
    try {
      final (lat, lng) = await bestEffortLocation();
      await _pausarHermanasEnMarcha(t, lat, lng);   // concatenación

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
      ref.invalidate(tasksListProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo iniciar: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Reanudar: abre un tramo nuevo sin pedir hora (la apertura informada ya está fijada).
  Future<void> _resume(TaskDetail t) async {
    setState(() => _busy = true);
    try {
      final (lat, lng) = await bestEffortLocation();
      await _pausarHermanasEnMarcha(t, lat, lng);   // concatenación
      await ref.read(tasksRepoProvider).start(t.id, lat: lat, lng: lng);  // sin informada
      ref.invalidate(taskDetailProvider(t.id));
      ref.invalidate(tasksListProvider);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo reanudar: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pause(TaskDetail t) async {
    setState(() => _busy = true);
    try {
      final (lat, lng) = await bestEffortLocation();
      await ref.read(tasksRepoProvider).pause(t.id, lat: lat, lng: lng);
      ref.invalidate(taskDetailProvider(t.id));
      ref.invalidate(tasksListProvider);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo pausar: $e')));
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
    final cierre = await pickFriendlyTime(context);
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
class _RecursosSection extends ConsumerStatefulWidget {
  const _RecursosSection({required this.madreId, required this.recursos});
  final int madreId;
  final List<Recurso> recursos;
  @override
  ConsumerState<_RecursosSection> createState() => _RecursosSectionState();

  Future<void> _cerrar(Recurso r) async {
    try {
      final ok = await cerrarRecursoDialog(context, ref, r);
      if (ok) {
        ref.invalidate(taskDetailProvider(widget.madreId));
        ref.invalidate(tasksListProvider);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo cerrar: $e')));
    }
  }
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _iniciar(Recurso r) async {
    final hora = await pickFriendlyTime(context);   // primer inicio: hora ajustable
    if (hora == null) return;
    await _run(() async {
      final (lat, lng) = await bestEffortLocation();
      await _pausarActivo(r.id);                     // concatenación
      await ref.read(tasksRepoProvider).start(r.id, lat: lat, lng: lng, informada: hora);
    });
  }

  Future<void> _reanudar(Recurso r) => _run(() async {
        final (lat, lng) = await bestEffortLocation();
        await _pausarActivo(r.id);                   // concatenación
        await ref.read(tasksRepoProvider).start(r.id, lat: lat, lng: lng); // sin hora
      });

  Future<void> _pausar(Recurso r) => _run(() async {
        final (lat, lng) = await bestEffortLocation();
        await ref.read(tasksRepoProvider).pause(r.id, lat: lat, lng: lng);
      });

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
      return [IconButton(icon: const Icon(Icons.play_arrow, color: Colors.green), tooltip: 'Iniciar', onPressed: () => _iniciar(r))];
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
  final now = DateTime.now();
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
  switch (choice) {                                    // ← AHORA aquí
    case 'now':
      return DateTime.now();
    case 'm30':
      return DateTime.now().subtract(const Duration(minutes: 30));
    case 'h1':
      return DateTime.now().subtract(const Duration(hours: 1));
    case 'custom':
      return _pickCustom(context, now);                // ← ojo: ver punto siguiente
    default:
      return null;
  }
}

/// Si el recurso queda bajo mínimo: el chófer elige Mínimo o Incidencia.
Future<String?> pickMinimoIncidencia(BuildContext context, double horas, double minimo) {
  return showDialog<String>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Por debajo del mínimo'),
      content: Text('Has indicado ${horas.toStringAsFixed(1)} h, por debajo del mínimo '
          'de ${minimo.toStringAsFixed(0)} h.\n\n'
          '· Mínimo: se factura el servicio mínimo.\n'
          '· Incidencia: se factura lo indicado. Anota el motivo en observaciones.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        OutlinedButton(onPressed: () => Navigator.pop(context, 'incidencia'), child: const Text('Incidencia')),
        FilledButton(onPressed: () => Navigator.pop(context, 'minimo'), child: const Text('Mínimo')),
      ],
    ),
  );
}

/// Cierre de UN recurso (reutilizable). Devuelve true si se cerró.
Future<bool> cerrarRecursoDialog(BuildContext context, WidgetRef ref, Recurso r) async {
  final cierre = await pickFriendlyTime(context);
  if (cierre == null || !context.mounted) return false;
  final pausa = await pickPausa(context);
  if (pausa == null || !context.mounted) return false;

  String modo = 'normal';
  // Provisional SOLO para decidir si ofrecer Mínimo/Incidencia. El cálculo real lo hace el backend.
  if (r.servicioMinimo > 0 && r.aperturaInformada != null) {
    final h = cierre.difference(r.aperturaInformada!).inMinutes / 60.0;
    final horas = ((h * 2).ceil() / 2.0 - pausa).clamp(0, double.infinity).toDouble();
    if (horas < r.servicioMinimo) {
      final m = await pickMinimoIncidencia(context, horas, r.servicioMinimo);
      if (m == null) return false;
      modo = m;
    }
  }
  final (lat, lng) = await bestEffortLocation();
  await ref.read(tasksRepoProvider).close(r.id, cierreInformada: cierre, pausa: pausa, modo: modo, lat: lat, lng: lng);
  return true;
}

/// Reloj directo con la fecha de hoy; si pulsa el icono de calendario puede
  /// cambiar el día (caso raro).
Future<DateTime?> _pickCustom(BuildContext context, DateTime base) async {
  final tm = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(base));
  if (tm == null) return null;
  return DateTime(base.year, base.month, base.day, tm.hour, tm.minute);
}

/// Pausa/comida del servicio (obligatorio elegir). Devuelve null si cancela.
Future<double?> pickPausa(BuildContext context) {
  return showDialog<double>(
    context: context,
    barrierDismissible: false,
    builder: (_) => SimpleDialog(
      title: const Text('Tiempo de pausa / comida'),
      children: [
        for (final opt in const [
          ('Ninguna', 0.0), ('30 min', 0.5), ('1 hora', 1.0),
          ('1 h 30 min', 1.5), ('2 horas', 2.0),
        ])
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, opt.$2),
            child: Padding(padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(opt.$1, style: const TextStyle(fontSize: 16))),
          ),
      ],
    ),
  );
}
