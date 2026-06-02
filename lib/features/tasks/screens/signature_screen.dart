import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:signature/signature.dart';

import '../../../shared/location.dart';
import '../task_models.dart';
import '../tasks_providers.dart';

/// Firma del cliente. Muestra lo que el cliente acepta: horas a facturar (o
/// "Servicio mínimo", o aviso si aún no está cerrada), observaciones editables,
/// nombre y firma. Una vez firmada, no se puede volver a firmar ni editar.
class SignatureScreen extends ConsumerStatefulWidget {
  const SignatureScreen({super.key, required this.task});
  final TaskDetail task;
  @override
  ConsumerState<SignatureScreen> createState() => _SignatureScreenState();
}

class _SignatureScreenState extends ConsumerState<SignatureScreen> {
  final _controller = SignatureController(penStrokeWidth: 3, penColor: Colors.black);
  late final TextEditingController _signer =
      TextEditingController(text: widget.task.worksheet.identificacionSig ?? '');
  late final TextEditingController _obs =
      TextEditingController(text: widget.task.worksheet.obsCliente ?? '');
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    _signer.dispose();
    _obs.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_controller.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Falta la firma.')));
      return;
    }
    // Refrendo: el cliente confirma de nuevo antes de fijar la firma.
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Confirmar firma'),
        content: const Text('¿Estás de acuerdo con los datos y la firma? '
            'Una vez confirmada no podrá modificarse.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Revisar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Sí, firmar')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      final bytes = await _controller.toPngBytes();
      if (bytes == null) throw Exception('No se pudo generar la imagen.');
      final (lat, lng) = await bestEffortLocation();
      await ref.read(tasksRepoProvider).saveSignature(
            widget.task.id,
            base64Encode(bytes),
            signerName: _signer.text.trim().isEmpty ? null : _signer.text.trim(),
            obsCliente: _obs.text.trim(),
            lat: lat,
            lng: lng,
          );
      ref.invalidate(taskDetailProvider(widget.task.id));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.task.hasSignature) {
      return Scaffold(
        appBar: AppBar(title: const Text('Firma del cliente')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.verified, size: 64, color: Colors.green),
              SizedBox(height: 16),
              Text('Esta tarea ya está firmada.\nNo puede modificarse.',
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 16)),
            ]),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Firma del cliente'),
        actions: [IconButton(onPressed: () => _controller.clear(), icon: const Icon(Icons.clear))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _HoursBanner(task: widget.task),
          const SizedBox(height: 12),
          TextField(
            controller: _obs,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Observaciones del cliente'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _signer,
            decoration: const InputDecoration(labelText: 'Nombre de quien firma'),
          ),
          const SizedBox(height: 12),
          const Text('Firma:', style: TextStyle(color: Colors.black54)),
          const SizedBox(height: 6),
          Container(
            height: 220,
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: Colors.black26),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Signature(controller: _controller, backgroundColor: Colors.white),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : _save,
            icon: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.check),
            label: const Text('Firmar'),
          ),
        ],
      ),
    );
  }
}

/// Aviso de horas que ve el cliente al firmar.
class _HoursBanner extends StatelessWidget {
  const _HoursBanner({required this.task});
  final TaskDetail task;
  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color color, String text) = !task.cerrada
        ? (Icons.hourglass_empty, Colors.orange.shade800,
            'El cómputo de horas aún no está calculado (tarea sin finalizar).')
        : task.worksheet.aplicarMinimo
            ? (Icons.lock_clock, Colors.indigo, 'Servicio mínimo')
            : (Icons.schedule, Colors.green.shade700,
                'Horas a facturar: ${task.worksheet.horasFacturar.toStringAsFixed(1)} h');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(children: [
        Icon(icon, color: color),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w600))),
      ]),
    );
  }
}
