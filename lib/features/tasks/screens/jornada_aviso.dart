import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/odoo_dt.dart';
import '../tasks_providers.dart';
import '../tasks_repository.dart';
import '../../auth/session_controller.dart';
/// Reacciona al bloque `jornada` que devuelve el servidor en /start, /close y
/// /complete. Compartido por el detalle de servicios y el de no facturables.
///
/// - Respaldo de /start (sin salida): jornada abierta → libro de pausas limpio,
///   refresca Asistencia y avisa con la hora de entrada.
/// - "Solo horas" + control de jornada (con salida): jornada registrada a partir
///   de las tareas → aviso breve con entrada y salida.
/// - Error: avisa (la tarea sí se guardó).
Future<void> tratarJornada(BuildContext context, WidgetRef ref, JornadaStart? j) async {
  if (j == null || !context.mounted) return;
  final desdeTareas =
      ref.read(sessionControllerProvider).profile?.config.jornadaDesdeTareas ?? false;

  String hm(String? s) {
    final h = parseOdooDt(s)?.toLocal();
    return h == null
        ? ''
        : '${h.hour.toString().padLeft(2, '0')}:${h.minute.toString().padLeft(2, '0')}';
  }

  if (j.abiertaAutomaticamente) {
    ref.invalidate(attendanceStateProvider);
    final entrada = hm(j.checkIn);
    final salida = hm(j.checkOut);

    if (salida.isNotEmpty) {
      // Jornada calculada de las tareas: se recalcula en cada cierre → aviso breve.
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('Jornada registrada: $entrada – $salida')));
      return;
    }

    if (!desdeTareas) await ref.read(journeyLedgerProvider).clear();
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Jornada abierta'),
        content: Text('No tenías la jornada fichada. Se ha abierto automáticamente'
            '${entrada.isEmpty ? '' : ' a las $entrada'}.'),
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
        content: Text(desdeTareas
            ? 'No se ha podido registrar tu jornada automáticamente. Avisa a oficina.\n\n${j.error}'
            : 'No se ha podido abrir tu jornada automáticamente. '
                'Ficha la entrada en Asistencia.\n\n${j.error}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar')),
        ],
      ),
    );
  }
}