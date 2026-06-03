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
  late final TextEditingController _dni =
      TextEditingController(text: widget.task.worksheet.dniSig ?? '');
  late final TextEditingController _obs =
      TextEditingController(text: widget.task.worksheet.obsCliente ?? '');
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    _signer.dispose();
    _dni.dispose();
    _obs.dispose();
    super.dispose();
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 110, child: Text(k, style: const TextStyle(color: Colors.black54))),
          Expanded(child: Text(v)),
        ]),
      );

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
            dni: _dni.text.trim(),
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
      final w = widget.task.worksheet;
      Widget? img;
      final b64 = w.signatureBase64;
      if (b64 != null && b64.isNotEmpty) {
        try {
          img = Image.memory(base64Decode(b64), height: 160, fit: BoxFit.contain);
        } catch (_) {
          img = null;
        }
      }
      return Scaffold(
        appBar: AppBar(title: const Text('Firma del cliente')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(children: [
              Icon(Icons.verified, color: Colors.green.shade700),
              const SizedBox(width: 8),
              const Text('Tarea firmada', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ]),
            const SizedBox(height: 16),
            if ((w.identificacionSig ?? '').isNotEmpty) _kv('Firmante', w.identificacionSig!),
            if ((w.dniSig ?? '').isNotEmpty) _kv('DNI', w.dniSig!),
            if (w.firmaHora != null)
              _kv('Fecha/Hora', w.firmaHora!.toLocal().toString().substring(0, 16)),
            if ((w.obsCliente ?? '').isNotEmpty) _kv('Obs. cliente', w.obsCliente!),
            const SizedBox(height: 16),
            const Text('Firma:', style: TextStyle(color: Colors.black54)),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: Colors.black26),
                borderRadius: BorderRadius.circular(12),
              ),
              child: img ?? const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: Text('Firma no disponible para mostrar.')),
              ),
            ),
          ],
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
          TextField(
            controller: _dni,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(labelText: 'DNI de quien firma'),
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
    final finalizada = task.cerrada || task.stage.alias == 'Finalizada';
    final (IconData icon, Color color, String text) = !finalizada
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
