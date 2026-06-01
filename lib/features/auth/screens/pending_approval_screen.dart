import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../session_controller.dart';

/// El dispositivo está enrolado pero el administrador aún no lo ha aprobado
/// (o ha sido revocado). Muestra la huella para que el admin lo identifique.
class PendingApprovalScreen extends ConsumerWidget {
  const PendingApprovalScreen({super.key, this.revoked = false});
  final bool revoked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: Text(revoked ? 'Dispositivo revocado' : 'Pendiente de aprobación')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(revoked ? Icons.block : Icons.hourglass_top,
                size: 72, color: revoked ? Colors.red : Colors.orange),
            const SizedBox(height: 20),
            Text(
              revoked
                  ? 'Este dispositivo ha sido revocado. Contacta con tu administrador.'
                  : 'Tu dispositivo está registrado y a la espera de que el administrador lo apruebe.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),
            FutureBuilder(
              future: ref.read(secureStoreProvider).readDeviceId(),
              builder: (_, snap) => snap.data == null
                  ? const SizedBox.shrink()
                  : Text('ID: ${snap.data!.substring(0, 16)}…',
                      style: const TextStyle(fontFamily: 'monospace', color: Colors.black54)),
            ),
            const SizedBox(height: 28),
            if (!revoked)
              FilledButton.icon(
                onPressed: () => ref.read(sessionControllerProvider.notifier).retry(),
                icon: const Icon(Icons.refresh),
                label: const Text('Ya me han aprobado'),
              ),
            TextButton(
              onPressed: () => ref.read(sessionControllerProvider.notifier).resetPairing(),
              child: const Text('Volver a empezar (re-emparejar)'),
            ),
          ],
        ),
      ),
    );
  }
}
