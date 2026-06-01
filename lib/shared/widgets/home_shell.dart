import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/session_controller.dart';
import '../../features/attendance/screens/attendance_screen.dart';
import '../../features/tasks/screens/tasks_list_screen.dart';
import 'env_banner.dart';

/// Contenedor principal tras autenticarse: navegación entre Asistencia y Tareas.
/// Las pestañas se muestran según las capacidades del operador.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});
  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionControllerProvider);
    final profile = session.profile;
    final caps = profile?.capabilities;

    final tabs = <({IconData icon, String label, Widget page})>[
      if (caps?.attendance ?? true)
        (icon: Icons.access_time, label: 'Asistencia', page: const AttendanceScreen()),
      if (caps?.tasks ?? true)
        (icon: Icons.assignment, label: 'Tareas', page: const TasksListScreen()),
    ];
    if (tabs.isEmpty) {
      return const Scaffold(body: Center(child: Text('Sin permisos asignados en la app.')));
    }
    final idx = _index.clamp(0, tabs.length - 1);

    return Scaffold(
      appBar: AppBar(
        title: Text(profile?.employeeName ?? 'Grúas Salvador'),
        actions: [
          if (profile?.isManager ?? false)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Chip(label: Text('Jefe'), visualDensity: VisualDensity.compact),
            ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Cerrar sesión / re-emparejar',
            onPressed: () => _confirmReset(context),
          ),
        ],
      ),
      body: Column(
        children: [
          const EnvBanner(),
          Expanded(child: tabs[idx].page),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: idx,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          for (final t in tabs) NavigationDestination(icon: Icon(t.icon), label: t.label),
        ],
      ),
    );
  }

  void _confirmReset(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Re-emparejar dispositivo'),
        content: const Text(
            'Se borrará la sesión y la clave de este dispositivo. Tendrás que volver a '
            'configurarlo y a que el administrador lo apruebe. ¿Continuar?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              ref.read(sessionControllerProvider.notifier).resetPairing();
            },
            child: const Text('Re-emparejar'),
          ),
        ],
      ),
    );
  }
}
