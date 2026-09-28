import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/session_controller.dart';
import '../../features/auth/screens/splash_screen.dart' show kAppCommercialName;
import '../../features/attendance/screens/attendance_screen.dart';
import '../../features/tasks/screens/tasks_list_screen.dart';
import '../../features/maintenance/maintenance_providers.dart';
import '../../features/maintenance/screens/maintenance_screen.dart';
import '../../core/env/environment.dart';
import '../../core/providers.dart';
import '../app_version.dart';
import 'brand_logo.dart';
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

    // Gating de averías SIN tocar backend: la pestaña aparece solo si el
    // catálogo confirma `puede_reportar` (x_app_averias). Mientras carga o si
    // falla la red, no se pinta (se reintentará).
    final puedeAverias =
        ref.watch(maintenanceCatalogProvider).valueOrNull?.puedeReportar ?? false;

    final tabs = <({IconData icon, String label, Widget page})>[
      if (caps?.attendance ?? true)
        (icon: Icons.access_time, label: 'Asistencia', page: const AttendanceScreen()),
      if (caps?.tasks ?? true)
        (icon: Icons.assignment, label: 'Tareas', page: const TasksListScreen()),
      if (puedeAverias)
        (icon: Icons.build, label: 'Averías', page: const MaintenanceScreen()),
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
            icon: const Icon(Icons.info_outline),
            tooltip: 'Acerca de',
            onPressed: () => _showAbout(context),
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
      bottomNavigationBar: tabs.length < 2
          ? null
          : NavigationBar(
              selectedIndex: idx,
              onDestinationSelected: (i) => setState(() => _index = i),
              destinations: [
                for (final t in tabs) NavigationDestination(icon: Icon(t.icon), label: t.label),
              ],
            ),
    );
  }

  /// Diálogo "Acerca de": marca, empresa, entorno, URL del servidor y versión.
  /// Muestra la URL (baseUrl) pero NUNCA la BD, coherente con el resto de la app.
  void _showAbout(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => Consumer(
        builder: (ctx, ref, _) {
          final profile = ref.watch(connectionProfileProvider);
          final version = ref.watch(appVersionProvider).short;
          final empresa = profile?.label;
          final url = profile?.baseUrl;

          return AlertDialog(
            title: const Text('Acerca de'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(child: const BrandLogo(size: 56)),
                const SizedBox(height: 12),
                Center(
                  child: Text(
                    kAppCommercialName,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                ),
                const SizedBox(height: 16),
                if (empresa != null && empresa.trim().isNotEmpty)
                  _aboutRow('Empresa', empresa),
                _aboutRow('Entorno', Env.config.label),
                if (url != null && url.trim().isNotEmpty) _aboutRow('Servidor', url),
                _aboutRow('Versión', version),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar')),
            ],
          );
        },
      ),
    );
  }

  Widget _aboutRow(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 76,
              child: Text(label, style: const TextStyle(color: Colors.black54, fontSize: 13)),
            ),
            Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
          ],
        ),
      );

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