import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../task_models.dart';
import '../tasks_providers.dart';

/// Edición de la hoja de trabajo (solo tarea propia; el backend lo verifica).
class WorksheetScreen extends ConsumerStatefulWidget {
  const WorksheetScreen({super.key, required this.task});
  final TaskDetail task;
  @override
  ConsumerState<WorksheetScreen> createState() => _WorksheetScreenState();
}

class _WorksheetScreenState extends ConsumerState<WorksheetScreen> {
  late final TextEditingController _obsAlbaran;
  late final TextEditingController _obsCliente;
  late final TextEditingController _albaran;
  late final TextEditingController _horasReales;
  late final TextEditingController _horasFacturar;
  late final TextEditingController _firmante;
  late bool _cambioProducto;
  late bool _aplicarMinimo;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final w = widget.task.worksheet;
    _obsAlbaran = TextEditingController(text: w.obsAlbaran ?? '');
    _obsCliente = TextEditingController(text: w.obsCliente ?? '');
    _albaran = TextEditingController(text: widget.task.albaran ?? '');
    _horasReales = TextEditingController(text: w.horasReales == 0 ? '' : w.horasReales.toString());
    _horasFacturar = TextEditingController(text: w.horasFacturar == 0 ? '' : w.horasFacturar.toString());
    _firmante = TextEditingController(text: w.identificacionSig ?? '');
    _cambioProducto = w.cambioProducto;
    _aplicarMinimo = w.aplicarMinimo;
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await ref.read(tasksRepoProvider).updateWorksheet(widget.task.id, {
        'x_obs_albaran': _obsAlbaran.text,
        'x_obs_cliente': _obsCliente.text,
        'x_albaran': _albaran.text,
        'x_cambio_producto': _cambioProducto,
        'x_aplicar_minimo': _aplicarMinimo,
        'x_identificacion_sig': _firmante.text,
        if (_horasReales.text.isNotEmpty) 'x_horas_reales': double.tryParse(_horasReales.text) ?? 0,
        if (_horasFacturar.text.isNotEmpty) 'x_horas_facturar': double.tryParse(_horasFacturar.text) ?? 0,
      });
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
    return Scaffold(
      appBar: AppBar(title: const Text('Hoja de trabajo')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(children: [
            Expanded(child: _num(_horasReales, 'Horas reales')),
            const SizedBox(width: 12),
            Expanded(child: _num(_horasFacturar, 'Horas a facturar')),
          ]),
          const SizedBox(height: 12),
          TextField(controller: _albaran, decoration: const InputDecoration(labelText: 'Nº Albarán')),
          const SizedBox(height: 12),
          TextField(controller: _obsAlbaran, maxLines: 2, decoration: const InputDecoration(labelText: 'Observaciones albarán')),
          const SizedBox(height: 12),
          TextField(controller: _obsCliente, maxLines: 2, decoration: const InputDecoration(labelText: 'Observaciones cliente')),
          const SizedBox(height: 12),
          TextField(controller: _firmante, decoration: const InputDecoration(labelText: 'Identificación del firmante')),
          SwitchListTile(
            value: _cambioProducto,
            onChanged: (v) => setState(() => _cambioProducto = v),
            title: const Text('Cambio de producto'),
          ),
          SwitchListTile(
            value: _aplicarMinimo,
            onChanged: (v) => setState(() => _aplicarMinimo = v),
            title: const Text('Aplicar mínimo'),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : _save,
            icon: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save),
            label: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  Widget _num(TextEditingController c, String label) => TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: label),
      );
}
