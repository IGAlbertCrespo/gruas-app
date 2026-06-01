import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'features/auth/session_controller.dart';
import 'features/auth/screens/provisioning_screen.dart';
import 'features/auth/screens/enrollment_screen.dart';
import 'features/auth/screens/pending_approval_screen.dart';
import 'features/auth/screens/splash_screen.dart';
import 'shared/widgets/home_shell.dart';

class GruasApp extends ConsumerStatefulWidget {
  const GruasApp({super.key});
  @override
  ConsumerState<GruasApp> createState() => _GruasAppState();
}

class _GruasAppState extends ConsumerState<GruasApp> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(sessionControllerProvider.notifier).bootstrap());
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Grúas Salvador',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: const _AuthGate(),
    );
  }
}

/// Gate de navegación: la fase de la sesión decide qué pantalla raíz se muestra.
class _AuthGate extends ConsumerWidget {
  const _AuthGate();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final phase = ref.watch(sessionControllerProvider).phase;
    return switch (phase) {
      SessionPhase.loading => const SplashScreen(),
      SessionPhase.needsProfile => const ProvisioningScreen(),
      SessionPhase.needsEnroll => const EnrollmentScreen(),
      SessionPhase.pendingApproval => const PendingApprovalScreen(),
      SessionPhase.revoked => const PendingApprovalScreen(revoked: true),
      SessionPhase.authenticated => const HomeShell(),
    };
  }
}
