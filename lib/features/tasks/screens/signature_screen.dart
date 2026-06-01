import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:signature/signature.dart';

import '../tasks_providers.dart';

/// Captura la firma del cliente y la sube como PNG base64.
class SignatureScreen extends ConsumerStatefulWidget {
  const SignatureScreen({super.key, required this.taskId});
  final int taskId;
  @override
  ConsumerState<SignatureScreen> createState() => _SignatureScreenState();
}

class _SignatureScreenState extends ConsumerState<SignatureScreen> {
  final _controller = SignatureController(penStrokeWidth: 3, penColor: Colors.black);
  final _signer = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    _signer.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_controller.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Falta la firma.')));
      return;
    }
    setState(() => _busy = true);
    try {
      final bytes = await _controller.toPngBytes();
      if (bytes == null) throw Exception('No se pudo generar la imagen.');
      final b64 = base64Encode(bytes);
      await ref.read(tasksRepoProvider).saveSignature(
            widget.taskId,
            b64,
            signerName: _signer.text.trim().isEmpty ? null : _signer.text.trim(),
          );
      ref.invalidate(taskDetailProvider(widget.taskId));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Firma del cliente'),
        actions: [IconButton(onPressed: () => _controller.clear(), icon: const Icon(Icons.clear))],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _signer,
              decoration: const InputDecoration(labelText: 'Nombre de quien firma'),
            ),
          ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: Colors.black26),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Signature(controller: _controller, backgroundColor: Colors.white),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton.icon(
              onPressed: _busy ? null : _save,
              icon: _busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check),
              label: const Text('Guardar firma'),
            ),
          ),
        ],
      ),
    );
  }
}
