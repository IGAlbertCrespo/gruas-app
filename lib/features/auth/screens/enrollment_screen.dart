import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../session_controller.dart';

/// Genera el keypair en hardware y registra el dispositivo (queda pendiente).
class EnrollmentScreen extends ConsumerStatefulWidget {
  const EnrollmentScreen({super.key});
  @override
  ConsumerState<EnrollmentScreen> createState() => _EnrollmentScreenState();
}

class _EnrollmentScreenState extends ConsumerState<EnrollmentScreen> {
  final _name = TextEditingController();
  bool _busy = false;

  Future<void> _enroll() async {
    setState(() => _busy = true);
    await ref.read(sessionControllerProvider.notifier).enroll(
          deviceName: _name.text.trim().isEmpty ? null : _name.text.trim(),
        );
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final msg = ref.watch(sessionControllerProvider).message;
    return Scaffold(
      appBar: AppBar(title: const Text('Registrar dispositivo')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            const Icon(Icons.smartphone, size: 64),
            const SizedBox(height: 16),
            const Text(
              'Se generará una clave de seguridad única dentro de este teléfono. '
              'No saldrá nunca del dispositivo.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Nombre del dispositivo (opcional)',
                hintText: 'p.ej. Móvil Juan',
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _busy ? null : _enroll,
              icon: _busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.vpn_key),
              label: const Text('Registrar este dispositivo'),
            ),
            if (msg != null) ...[
              const SizedBox(height: 16),
              Text(msg, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
            ],
          ],
        ),
      ),
    );
  }
}
