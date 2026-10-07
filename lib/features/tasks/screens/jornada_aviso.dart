import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/odoo_dt.dart';
import '../tasks_providers.dart';
import '../tasks_repository.dart';

/// Reacciona al respaldo de jornada que devuelve el servidor en /start y
/// /complete. Compartido por el detalle de servicios y el de no facturables.
///
/// - Jornada abierta automáticamente: libro de pausas limpio (jornada nueva),
///   refresca Asistencia y avisa con la hora de entrada.
/// - Error al abrirla: avisa para que fiche a mano (la tarea sí se guardó).
Future<void> tratarJornada(BuildContext context, WidgetRef ref, JornadaStart? j) async {
  if (j == null || !context.mounted) return;

  if (j.abiertaAutomaticamente) {
    await ref.read(journeyLedgerProvider).clear();
    ref.invalidate(attendanceStateProvider);
    if (!context.mounted) return;
    final h = parseOdooDt(j.checkIn)?.toLocal();
    final hm = h == null
        ? ''
        : ' a las ${h.hour.toString().padLeft(2, '0')}:${h.minute.toString().padLeft(2, '0')}';
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Jornada abierta'),
        content: Text('No tenías la jornada fichada. Se ha abierto automáticamente$hm.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Entendido')),
        ],
      ),
    );
    return;
  }

  if ((j.error ?? '').isNotEmpty) {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Jornada'),
        content: Text('No se ha podido abrir tu jornada automáticamente. '
            'Ficha la entrada en Asistencia.\n\n${j.error}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar')),
        ],
      ),
    );
  }
}