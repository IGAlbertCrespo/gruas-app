import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../task_models.dart';
import '../tasks_providers.dart';
import 'worksheet_screen.dart';
import 'signature_screen.dart';

/// Detalle de tarea. Para el jefe en modo "todas" es readOnly (sin acciones).
class TaskDetailScreen extends ConsumerWidget {
  const TaskDetailScreen({super.key, required this.taskId, this.readOnly = false});
  final int taskId;
  final bool readOnly;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(taskDetailProvider(taskId));
    return Scaffold(
      appBar: AppBar(title: const Text('Servicio')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (t) => _DetailBody(task: t, readOnly: readOnly),
      ),
      bottomNavigationBar: (readOnly)
          ? null
          : async.maybeWhen(
              data: (t) => _ActionsBar(task: t, ref: ref),
              orElse: () => null,
            ),
    );
  }
}

class _DetailBody extends StatelessWidget {
  const _DetailBody({required this.task, required this.readOnly});
  final TaskDetail task;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(children: [
          Expanded(child: Text(task.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
          Chip(label: Text(task.stage.name)),
        ]),
        if (task.partner != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(task.partner!)),
        const SizedBox(height: 12),
        _section('Servicio', [
          if (task.fechaServicio != null) _kv('Fecha/Hora', task.fechaServicio!.toLocal().toString().substring(0, 16)),
          if (task.horaSalida != null) _kv('Hora salida', task.horaSalida!.toLocal().toString().substring(0, 16)),
          if (task.vehicle != null) _kv('Vehículo', task.vehicle!),
          if (task.albaran != null) _kv('Albarán', task.albaran!),
        ]),
        _addressCard('Carga', task.carga),
        _addressCard('Descarga', task.descarga),
        _section('Hoja de trabajo', [
          _kv('Horas reales', task.worksheet.horasReales.toStringAsFixed(2)),
          _kv('Horas a facturar', task.worksheet.horasFacturar.toStringAsFixed(2)),
          if ((task.worksheet.obsAlbaran ?? '').isNotEmpty) _kv('Obs. albarán', task.worksheet.obsAlbaran!),
          if ((task.worksheet.obsCliente ?? '').isNotEmpty) _kv('Obs. cliente', task.worksheet.obsCliente!),
          _kv('Firma', task.worksheet.hasSignature ? '✔ recogida' : '— pendiente'),
        ]),
        const SizedBox(height: 80),
      ],
    );
  }

  Widget _section(String title, List<Widget> rows) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ...rows,
          ]),
        ),
      );

  Widget _addressCard(String title, Address a) {
    final lines = [a.direccion, a.poblacion, a.codigoPostal].where((e) => (e ?? '').isNotEmpty).join(', ');
    return _section(title, [
      if (lines.isNotEmpty) _kv('Dirección', lines),
      if ((a.contacto ?? '').isNotEmpty) _kv('Contacto', a.contacto!),
      if ((a.telefono ?? '').isNotEmpty) _kv('Teléfono', a.telefono!),
    ]);
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 110, child: Text(k, style: const TextStyle(color: Colors.black54))),
          Expanded(child: Text(v)),
        ]),
      );
}

class _ActionsBar extends StatelessWidget {
  const _ActionsBar({required this.task, required this.ref});
  final TaskDetail task;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => WorksheetScreen(task: task))),
                icon: const Icon(Icons.edit_note),
                label: const Text('Hoja'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => SignatureScreen(taskId: task.id))),
                icon: const Icon(Icons.draw),
                label: const Text('Firmar'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                onPressed: () => _changeStage(context),
                icon: const Icon(Icons.flag),
                label: const Text('Etapa'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _changeStage(BuildContext context) {
    // El conjunto de transiciones que muestra la app es decisión de negocio.
    const options = {
      'finalizada': 'Finalizada',
      'revisado': 'Revisado',
      'cancelado': 'Cancelado',
    };
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final e in options.entries)
              ListTile(
                title: Text(e.value),
                onTap: () async {
                  Navigator.pop(context);
                  try {
                    await ref.read(tasksRepoProvider).changeStage(task.id, e.key);
                    ref.invalidate(taskDetailProvider(task.id));
                    ref.invalidate(tasksListProvider);
                  } catch (err) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$err')));
                    }
                  }
                },
              ),
          ],
        ),
      ),
    );
  }
}
