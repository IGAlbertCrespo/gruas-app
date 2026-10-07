import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../auth/session_controller.dart';
import '../task_models.dart';
import '../tasks_providers.dart';
import 'task_detail_screen.dart';
import 'non_billable_detail_screen.dart';
import '../../../shared/widgets/upgrade_required.dart';

class TasksListScreen extends ConsumerWidget {
  const TasksListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isManager = ref.watch(sessionControllerProvider).profile?.isManager ?? false;
    final scope = ref.watch(taskScopeProvider);
    final view = ref.watch(taskViewProvider);
    final listAsync = ref.watch(tasksListProvider);

    return Column(
      children: [
        // Pendientes (no finalizada+firmada) vs Completadas (finalizada y firmada).
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'pendientes', label: Text('Pendientes')),
              ButtonSegment(value: 'completadas', label: Text('Completadas')),
            ],
            selected: {view},
            onSelectionChanged: (s) => ref.read(taskViewProvider.notifier).state = s.first,
          ),
        ),
        // El jefe puede alternar entre sus tareas y todas (solo lectura en "todas").
        if (isManager)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'mine', label: Text('Mías')),
                ButtonSegment(value: 'all', label: Text('Todas')),
              ],
              selected: {scope},
              onSelectionChanged: (s) => ref.read(taskScopeProvider.notifier).state = s.first,
            ),
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async => ref.invalidate(tasksListProvider),
            child: listAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => ListView(children: [
                if (e is ApiException && e.upgradeRequired)
                  SizedBox(height: 360, child: UpgradeRequiredView(error: e))
                else
                  Padding(padding: const EdgeInsets.all(24), child: Center(child: Text('$e'))),
              ]),
              data: (res) {
                // No facturables: completada = marcada por el conductor (sin firma).
                final tasks = res.tasks.where((t) {
                  final completada =
                      t.esNoFacturable ? t.completada : (t.cerrada && t.hasSignature);
                  return view == 'completadas' ? completada : !completada;
                }).toList();
                if (tasks.isEmpty) {
                  return ListView(children: [
                    Padding(
                      padding: const EdgeInsets.all(40),
                      child: Center(child: Text(
                        view == 'completadas' ? 'No hay tareas completadas.' : 'No hay tareas pendientes.')),
                    ),
                  ]);
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: tasks.length,
                  itemBuilder: (_, i) => _TaskCard(
                    task: tasks[i],
                    readOnly: scope == 'all' && isManager,
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({required this.task, required this.readOnly});
  final TaskSummary task;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    if (task.esNoFacturable) return _NoFacturableCard(task: task, readOnly: readOnly);
    final route = [task.cargaPoblacion, task.descargaPoblacion].where((e) => e != null && e.isNotEmpty);
    final enProceso = task.iniciada && !task.cerrada;
    final pteFirma = task.cerrada && !task.hasSignature;
    return Card(
      color: enProceso ? Colors.green.shade50 : null,
      child: ListTile(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => TaskDetailScreen(taskId: task.id, readOnly: readOnly)),
        ),
        title: Text(task.name, maxLines: 3, overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (enProceso)
              const _StatusBadge(text: 'EN PROCESO', color: Colors.green, icon: Icons.play_circle)
            else if (pteFirma)
              const _StatusBadge(text: 'PTE. FIRMA', color: Colors.red, icon: Icons.draw),
            if (task.horaSalida != null)
              Text('Salida: ${task.horaSalida!.toLocal().toString().substring(0, 16)}',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            if (route.isNotEmpty) Text(route.join('  →  '), style: const TextStyle(color: Colors.black54)),
            if (task.fechaServicio != null)
              Text(task.fechaServicio!.toLocal().toString().substring(0, 16),
                  style: const TextStyle(fontSize: 12, color: Colors.black45)),
            if (task.recargo != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.bolt, size: 14, color: Colors.deepPurple.shade400),
                  const SizedBox(width: 2),
                  Text(task.recargo!,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.deepPurple.shade400)),
                ]),
              ),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Chip(
              label: Text(task.stage.name, style: const TextStyle(fontSize: 11)),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
            ),
            if (task.hasSignature) const Icon(Icons.draw, size: 16, color: Colors.green),
          ],
        ),
      ),
    );
  }
}

/// Distintivo de estado en la tarjeta: EN PROCESO (verde) / PTE. FIRMA (rojo).
class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.text, required this.color, required this.icon});
  final String text;
  final MaterialColor color;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: color.shade100,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 14, color: color.shade800),
            const SizedBox(width: 4),
            Text(text,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color.shade800)),
          ]),
        ),
      );
}
/// Tarjeta de tarea interna (no facturable): ámbar, sin etapas ni firma.
class _NoFacturableCard extends StatelessWidget {
  const _NoFacturableCard({required this.task, required this.readOnly});
  final TaskSummary task;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.amber.shade50,
      child: ListTile(
        leading: Icon(Icons.engineering, color: Colors.amber.shade800, size: 32),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => NonBillableDetailScreen(taskId: task.id, readOnly: readOnly)),
        ),
        title: Text(task.name, maxLines: 3, overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _StatusBadge(
              text: (task.tipoInterna ?? 'Tarea interna').toUpperCase(),
              color: Colors.amber,
              icon: Icons.engineering,
            ),
            if (task.partner != null)
              Text(task.partner!, style: const TextStyle(color: Colors.black54)),
            if (task.fechaServicio != null)
              Text(task.fechaServicio!.toLocal().toString().substring(0, 16),
                  style: const TextStyle(fontSize: 12, color: Colors.black45)),
          ],
        ),
        trailing: task.completada ? const Icon(Icons.check_circle, color: Colors.green) : null,
      ),
    );
  }
}