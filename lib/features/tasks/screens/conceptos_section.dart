import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/accion_tarea.dart';
import '../../../shared/widgets/upgrade_required.dart' show mostrarErrorAccion;
import '../task_models.dart';
import '../tasks_providers.dart';

/// Conceptos de la tarea MADRE (CONTRATO v3.1 §3 y §5): servicio principal,
/// recargo y salida. En la fase 4 se añaden el cambio de servicio y los
/// complementos (cargos).
///
/// En las hijas esos bloques llegan a null y la sección no se pinta.
/// Con [soloLectura] (pantalla de firma) no se ofrece ninguna edición.
class ConceptosSection extends ConsumerStatefulWidget {
  const ConceptosSection({super.key, required this.task, this.soloLectura = false});

  static const titulo = 'Conceptos del servicio';

  final TaskDetail task;
  final bool soloLectura;

  @override
  ConsumerState<ConceptosSection> createState() => _ConceptosSectionState();
}

class _ConceptosSectionState extends ConsumerState<ConceptosSection> {
  /// Campo que se está enviando ('recargo' | 'salida'); bloquea otras ediciones.
  String? _enviando;

  Future<void> _cambiar(String campo, String titulo, Seleccion sel) async {
    final elegido = await _elegirOpcion(context, titulo, sel);
    if (elegido == null || elegido == sel.value || !mounted) return;

    setState(() => _enviando = campo);
    final id = widget.task.id;
    final repo = ref.read(tasksRepoProvider);
    try {
      final res = await ejecutarAccionTarea(
        context,
        ref,
        id,
        () => campo == 'recargo' ? repo.setRecargo(id, elegido) : repo.setSalida(id, elegido),
      );
      if (res != null) {
        ref.invalidate(taskDetailProvider(id));
        ref.invalidate(tasksListProvider);
      }
    } catch (e) {
      if (mounted) await mostrarErrorAccion(context, e);
    } finally {
      if (mounted) setState(() => _enviando = null);
    }
  }

  VoidCallback? _accion(String campo, String titulo, Seleccion? sel) {
    if (widget.soloLectura || sel == null || !sel.puedeCambiar || _enviando != null) return null;
    return () => _cambiar(campo, titulo, sel);
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.task;
    final rec = t.recargoSel;
    final sal = t.salidaSel;
    if (t.servicio == null && rec == null && sal == null) return const SizedBox.shrink();

    final color = Theme.of(context).colorScheme.primary;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.receipt_long, size: 18, color: color),
            const SizedBox(width: 8),
            Text(ConceptosSection.titulo,
                style: TextStyle(fontWeight: FontWeight.bold, color: color)),
          ]),
          const SizedBox(height: 8),
          if (t.servicio != null) _fila('Servicio', t.servicio!.producto),
          if (rec != null)
            _fila('Recargo', rec.label,
                onEdit: _accion('recargo', 'Recargo', rec),
                cargando: _enviando == 'recargo'),
          if (sal != null)
            _fila('Salida', sal.label,
                onEdit: _accion('salida', 'Salida', sal),
                cargando: _enviando == 'salida'),
        ]),
      ),
    );
  }

  Widget _fila(String k, String v, {VoidCallback? onEdit, bool cargando = false}) => InkWell(
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            SizedBox(width: 120, child: Text(k, style: const TextStyle(color: Colors.black54))),
            Expanded(child: Text(v)),
            if (cargando)
              const SizedBox(
                  width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
            else if (onEdit != null)
              const Icon(Icons.edit, size: 18, color: Colors.black38),
          ]),
        ),
      );
}

/// Bottom sheet con las opciones que envía el servidor; la actual, marcada.
/// Devuelve el `value` elegido o null si se cierra sin elegir.
Future<String?> _elegirOpcion(BuildContext context, String titulo, Seleccion sel) =>
    showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(titulo,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            for (final o in sel.opciones)
              ListTile(
                leading: Icon(
                  o.value == sel.value ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                  color: o.value == sel.value ? Theme.of(ctx).colorScheme.primary : null,
                ),
                title: Text(o.label),
                onTap: () => Navigator.pop(ctx, o.value),
              ),
          ],
        ),
      ),
    );