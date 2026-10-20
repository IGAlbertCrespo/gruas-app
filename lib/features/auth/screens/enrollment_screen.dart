import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers.dart';
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

  /// Vuelve a la pantalla del QR: borra conexión, registro y clave del teléfono.
  Future<void> _cambiarConexion() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cambiar conexión'),
        content: const Text('Se borrará la configuración de este teléfono y tendrás '
            'que escanear de nuevo el código QR de alta.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Cambiar')),
        ],
      ),
    );
    if (ok == true) await ref.read(sessionControllerProvider.notifier).resetPairing();
  }

  @override
  Widget build(BuildContext context) {
    final msg = ref.watch(sessionControllerProvider).message;
    final perfil = ref.watch(connectionProfileProvider);
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
            const SizedBox(height: 32),
            if (perfil != null)
              Text(
                'Servidor: ${perfil.label ?? perfil.baseUrl}\nBase de datos: ${perfil.db}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black54, fontSize: 12),
              ),
            TextButton.icon(
              onPressed: _busy ? null : _cambiarConexion,
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Cambiar conexión (escanear QR)'),
            ),
          ],
        ),
      ),
    );
  }

}
