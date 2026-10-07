import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:signature/signature.dart';

import '../../../shared/location.dart';
import '../task_models.dart';
import '../tasks_providers.dart';
import 'cierre_recurso.dart';
import 'resumen_albaran_view.dart';
import '../../auth/session_controller.dart';

/// Firma del servicio. Muestra el resumen de todos los recursos (editable),
/// observaciones del cliente, y la firma. Al confirmar: guarda firma + finaliza
/// la madre (arrastra hijas). Una vez firmada, solo lectura.
class SignatureScreen extends ConsumerStatefulWidget {
  const SignatureScreen({super.key, required this.task});
  final TaskDetail task;
  @override
  ConsumerState<SignatureScreen> createState() => _SignatureScreenState();
}

class _SignatureScreenState extends ConsumerState<SignatureScreen> {
  final _controller = SignatureController(penStrokeWidth: 3, penColor: Colors.black);
  final _signer = TextEditingController();          // antes: text: ...identificacionSig
  final _dni = TextEditingController();              // antes: text: ...dniSig
  late final _obs = TextEditingController(text: widget.task.worksheet.obsCliente ?? '');
  bool _busy = false;
  bool _ausente = false;

  @override
  void dispose() {
    _controller.dispose();
    _signer.dispose();
    _dni.dispose();
    _obs.dispose();
    super.dispose();
  }

  Future<void> _editarRecurso(Recurso r) async {
    try {
      final ok = await cerrarRecursoDialog(context, ref, r);
      if (ok) ref.invalidate(taskDetailProvider(widget.task.id));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo editar: $e')));
    }
  }

  static const _notaAusente = 'Cliente ausente: firma el conductor.';

  void _setAusente(bool v) {
    setState(() {
      _ausente = v;
      if (v) {
        final conductor =
            ref.read(sessionControllerProvider).profile?.employeeName ?? 'Conductor';
        _signer.text = '$conductor (cliente ausente)';
        _dni.clear();
        if (!_obs.text.contains(_notaAusente)) {
          _obs.text = _obs.text.trim().isEmpty ? _notaAusente : '$_notaAusente ${_obs.text.trim()}';
        }
      } else {
        _signer.clear();
        _obs.text = _obs.text.replaceAll(_notaAusente, '').trim();
      }
    });
  }

  bool _dniValido(String s) {
    final t = s.trim().toUpperCase();
    if (!RegExp(r'^\d{8}[A-Z]$').hasMatch(t)) return false;
    const letras = 'TRWAGMYFPDXBNJZSQVHLCKE';
    final num = int.parse(t.substring(0, 8));
    return letras[num % 23] == t[8];
  }

  Future<void> _firmarYFinalizar() async {
    final hayFirma = !_controller.isEmpty;
    final hayNombre = _signer.text.trim().isNotEmpty;
    final dni = _dni.text.trim();
    final hayDni = dni.isNotEmpty;
    if (_ausente && _controller.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Con el cliente ausente debe firmar el conductor.')));
      return;
    }
    // Mínimo 2 de 3: firma / nombre / DNI.
    final n = [hayFirma, hayNombre, hayDni].where((b) => b).length;
    if (n < 2) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Indica al menos dos datos: firma, nombre o DNI.')));
      return;
    }

    // DNI mal formado: avisamos pero permitimos (puede ser NIE/extranjero).
    if (hayDni && !_dniValido(dni)) {
      final seguir = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('DNI no estándar'),
          content: const Text('El DNI introducido no tiene el formato español habitual '
              '(8 cifras + letra). Si es un documento extranjero (NIE/pasaporte) es normal. '
              '¿Continuar de todos modos?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Revisar')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Continuar')),
          ],
        ),
      );
      if (seguir != true) return;
    }

    // #4 — confirmación simple
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Confirmar firma'),
        content: const Text('¿Confirma los datos introducidos?\n\n'
            'Una tarea finalizada ya no es modificable.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Revisar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Confirmar')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      final bytes = await _controller.toPngBytes();
      if (bytes == null) throw Exception('No se pudo generar la imagen.');
      final (lat, lng) = await bestEffortLocation();
      final repo = ref.read(tasksRepoProvider);
      await repo.saveSignature(
        widget.task.id,
        base64Encode(bytes),
        signerName: _signer.text.trim().isEmpty ? null : _signer.text.trim(),
        dni: _dni.text.trim(),
        obsCliente: _obs.text.trim(),
        lat: lat, lng: lng,
      );
      await repo.finalize(widget.task.id, lat: lat, lng: lng); // mueve la madre a Finalizada
      ref.invalidate(taskDetailProvider(widget.task.id));
      ref.invalidate(tasksListProvider);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Madre fresca: refleja las ediciones de recursos hechas aquí.
    final t = ref.watch(taskDetailProvider(widget.task.id)).valueOrNull ?? widget.task;
    if (t.hasSignature) return _vistaFirmada(t);

    return Scaffold(
      appBar: AppBar(title: const Text('Firmar servicio')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Resumen del servicio', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          for (final r in t.recursos) _filaResumen(r),
          const Divider(height: 24),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Cliente ausente'),
            subtitle: const Text('Firma el conductor y queda anotado en observaciones'),
            value: _ausente,
            onChanged: _busy ? null : _setAusente,
          ),
          TextField(controller: _obs, maxLines: 2,
              decoration: const InputDecoration(labelText: 'Observaciones del cliente')),
          const SizedBox(height: 12),
          TextField(controller: _signer,
              decoration: const InputDecoration(labelText: 'Nombre de quien firma')),
          const SizedBox(height: 12),
          TextField(controller: _dni, textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'DNI de quien firma')),
          const SizedBox(height: 16),
          Row(children: [
            const Text('Firma:', style: TextStyle(color: Colors.black54)),
            const Spacer(),
            TextButton.icon(
              onPressed: () => _controller.clear(),
              icon: const Icon(Icons.delete_outline),
              label: const Text('Borrar'),
            ),
          ]),
          const SizedBox(height: 6),
          Container(
            height: 170,                              // antes 220
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: Colors.black26),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Signature(controller: _controller, backgroundColor: Colors.white),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : _firmarYFinalizar,
            icon: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.check),
            label: const Text('Confirmar y firmar'),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 24),  // ← aire bajo la barra del móvil
        ],
      ),
    );
  }

    Widget _filaResumen(Recurso r) {
    final res = r.resumenAlbaran;
    return InkWell(
      onTap: r.esMio ? () => _editarRecurso(r) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(r.recurso, style: const TextStyle(fontWeight: FontWeight.w600))),
            if (r.esMio) const Icon(Icons.edit, size: 16, color: Colors.black38),
          ]),
          if (res != null)
            ResumenAlbaranView(resumen: res)
          else
            Text(r.cerrada ? 'Cerrado' : 'Sin cerrar',
                style: const TextStyle(color: Colors.black54)),
        ]),
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 110, child: Text(k, style: const TextStyle(color: Colors.black54))),
          Expanded(child: Text(v)),
        ]),
      );

  Widget _vistaFirmada(TaskDetail t) {
    final w = t.worksheet;
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
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Row(children: [
          Icon(Icons.verified, color: Colors.green.shade700),
          const SizedBox(width: 8),
          const Text('Servicio firmado', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 16),
        if ((w.identificacionSig ?? '').isNotEmpty) _kv('Firmante', w.identificacionSig!),
        if ((w.dniSig ?? '').isNotEmpty) _kv('DNI', w.dniSig!),
        if (w.firmaHora != null) _kv('Fecha/Hora', w.firmaHora!.toLocal().toString().substring(0, 16)),
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
          child: img ?? const Padding(padding: EdgeInsets.all(24),
              child: Center(child: Text('Firma no disponible.'))),
        ),
      ]),
    );
  }
}