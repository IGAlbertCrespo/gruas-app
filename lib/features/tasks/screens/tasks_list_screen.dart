import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/session_controller.dart';
import '../task_models.dart';
import '../tasks_providers.dart';
import 'task_detail_screen.dart';

class TasksListScreen extends ConsumerWidget {
  const TasksListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isManager = ref.watch(sessionControllerProvider).profile?.isManager ?? false;
    final scope = ref.watch(taskScopeProvider);
    final listAsync = ref.watch(tasksListProvider);

    return Column(
      children: [
        // El jefe puede alternar entre sus tareas y todas (solo lectura en "todas").
        if (isManager)
          Padding(
            padding: const EdgeInsets.all(12),
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
                Padding(padding: const EdgeInsets.all(24), child: Center(child: Text('$e'))),
              ]),
              data: (res) => res.tasks.isEmpty
                  ? ListView(children: const [
                      Padding(padding: EdgeInsets.all(40), child: Center(child: Text('No hay tareas.'))),
                    ])
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: res.tasks.length,
                      itemBuilder: (_, i) => _TaskCard(
                        task: res.tasks[i],
                        readOnly: scope == 'all' && isManager,
                      ),
                    ),
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
    final route = [task.cargaPoblacion, task.descargaPoblacion].where((e) => e != null && e.isNotEmpty);
    return Card(
      child: ListTile(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => TaskDetailScreen(taskId: task.id, readOnly: readOnly)),
        ),
        title: Text(task.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (task.partner != null) Text(task.partner!),
            if (route.isNotEmpty) Text(route.join('  →  '), style: const TextStyle(color: Colors.black54)),
            if (task.fechaServicio != null)
              Text(task.fechaServicio!.toLocal().toString().substring(0, 16),
                  style: const TextStyle(fontSize: 12, color: Colors.black45)),
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
