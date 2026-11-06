import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/observaciones_dialog.dart';
import '../../../shared/widgets/upgrade_required.dart' show mostrarErrorAccion;
import '../tasks_providers.dart';

/// v3.12 §4.9 — Edita las observaciones del albarán de [taskId]
/// (`POST /tasks/<id>/observaciones`) y refresca la tarea y, si se indica, la
/// madre ([madreId]). Devuelve true si el servidor las guardó.
Future<bool> editarObsAlbaran(
  BuildContext context,
  WidgetRef ref, {
  required int taskId,
  String? inicial,
  int? madreId,
  bool avisoCliente = true,
}) async {
  final texto = await pedirObsAlbaran(context, inicial: inicial, avisoCliente: avisoCliente);
  if (texto == null || !context.mounted) return false;
  if (texto == (inicial ?? '').trim()) return false; // sin cambios
  var ok = false;
  try {
    await ref.read(tasksRepoProvider).setObservaciones(taskId, texto);
    ok = true;
  } catch (e) {
    // 409 tarea_firmada / no_editable, 422 incidencia_sin_obs: se muestra el detail.
    if (context.mounted) await mostrarErrorAccion(context, e);
  }
  ref.invalidate(taskDetailProvider(taskId));
  if (madreId != null && madreId != taskId) ref.invalidate(taskDetailProvider(madreId));
  return ok;
}

/// Bloque "Observaciones del albarán": el texto (o "Sin observaciones") y, si
/// [onEditar] no es null, el enlace para añadirlas o editarlas.
class ObsAlbaranTile extends StatelessWidget {
  const ObsAlbaranTile({super.key, required this.texto, this.onEditar});

  final String? texto;
  final VoidCallback? onEditar;

  @override
  Widget build(BuildContext context) {
    final t = (texto ?? '').trim();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Observaciones del albarán',
            style: TextStyle(color: Colors.black54, fontSize: 12)),
        Text(t.isEmpty ? 'Sin observaciones' : t,
            style: t.isEmpty ? const TextStyle(color: Colors.black38) : null),
        if (onEditar != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
              onPressed: onEditar,
              icon: Icon(t.isEmpty ? Icons.add_comment_outlined : Icons.edit_note, size: 18),
              label: Text(t.isEmpty ? 'Añadir observaciones' : 'Editar observaciones'),
            ),
          ),
      ]),
    );
  }
}