import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/location.dart';
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
    final List<Widget> buttons = [];

    if (alias == 'Informado' && !t.iniciada) {
      buttons.add(Expanded(
        child: FilledButton.icon(
          onPressed: _busy ? null : () => _start(t),
          icon: const Icon(Icons.play_arrow),
          label: const Text('Iniciar'),
        ),
      ));
    } else if (alias == 'Informado' && t.iniciada) {
      buttons.add(Expanded(
        child: OutlinedButton.icon(
          onPressed: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => SignatureScreen(task: t))),
          icon: const Icon(Icons.draw),
          label: const Text('Firmar'),
        ),
      ));
      buttons.add(const SizedBox(width: 8));
      buttons.add(Expanded(
        child: FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: Colors.green.shade700),
          onPressed: _busy ? null : () => _finish(t),
          icon: const Icon(Icons.check_circle),
          label: const Text('Finalizar'),
        ),
      ));
    } else if (alias == 'Finalizada') {
      buttons.add(Expanded(
        child: OutlinedButton.icon(
          onPressed: _busy ? null : () => _reopen(t),
          icon: const Icon(Icons.undo),
          label: const Text('Reabrir'),
        ),
      ));
    }

    if (buttons.isEmpty) return null;
    return SafeArea(
      child: Padding(padding: const EdgeInsets.all(12), child: Row(children: buttons)),
    );
  }
  /// Selector de fecha + hora (para inicio/cierre). Devuelve null si se cancela.
  Future<DateTime?> _pickDateTime(DateTime initial) async {
    final d = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (d == null || !mounted) return null;
    final tm = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(initial));
    if (tm == null) return null;
    return DateTime(d.year, d.month, d.day, tm.hour, tm.minute);
  }

  Future<void> _start(TaskDetail t) async {
    // La hora de inicio se puede ajustar (p.ej. si se olvidó iniciar a tiempo).
    final hora = await _pickDateTime(DateTime.now());
    if (hora == null) return;
    setState(() => _busy = true);
    try {
      final (lat, lng) = await bestEffortLocation();
      await ref.read(tasksRepoProvider).start(t.id, lat: lat, lng: lng, informada: hora);
      ref.invalidate(taskDetailProvider(t.id));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
    // La hora de cierre es editable; las horas a facturar se calculan con las
    // horas informadas (inicio informado -> cierre informado), por exceso a 30 min.
    final cierre = await _pickDateTime(DateTime.now());
    if (cierre == null) return;

    final apertura = t.aperturaInformada ?? t.aperturaHora;
    double horas = 0;
    if (apertura != null) {
      final h = cierre.difference(apertura).inMinutes / 60.0;
      horas = (h * 2).ceil() / 2.0;
      if (horas < 0) horas = 0;
    }
    final esMinimo = t.worksheet.servicioMinimo > 0 && horas < t.worksheet.servicioMinimo;

    final ok = await _confirmFinish(horas, esMinimo);
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      final (lat, lng) = await bestEffortLocation();
      await ref.read(tasksRepoProvider).finish(t.id, lat: lat, lng: lng, informada: cierre);
      ref.invalidate(taskDetailProvider(t.id));
      ref.invalidate(tasksListProvider);
      if (mounted) Navigator.pop(context);
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
        if (task.partner != null)
          Padding(padding: const EdgeInsets.only(top: 4), child: Text(task.partner!)),
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

        _Section(icon: Icons.assignment_turned_in, title: 'Hoja de trabajo', color: scheme.primary, rows: [
          _kv('Horas reales', task.worksheet.horasReales.toStringAsFixed(2)),
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
