import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/api_exception.dart';
import '../features/tasks/tasks_providers.dart';

/// Envuelve cualquier acción v3 sobre una tarea (recargo, salida, servicio,
/// cargos, firmantes, firma, solicitudes) con el tratamiento común de errores:
///
/// - `403 sin_permiso` / `409 tarea_firmada` / `409 no_editable` /
///   `422 no_es_madre` / lista desactualizada (`cargo_duplicado`,
///   `cargo_no_anulable`, `linea_no_valida`): muestra el `detail` del servidor
///   y refresca la tarea y la lista. Devuelve `null`.
/// - Sin conexión: avisa de que la acción requiere conexión. Devuelve `null`.
/// - Cualquier otro error se propaga para que la pantalla lo trate.
Future<T?> ejecutarAccionTarea<T>(
  BuildContext context,
  WidgetRef ref,
  int taskId,
  Future<T> Function() accion,
) async {
  try {
    return await accion();
  } on ApiException catch (e) {
    if (!context.mounted) return null;
    if (e.sinPermiso || e.tareaFirmada || e.noEditable || e.noEsMadre || e.listaDesactualizada) {
      _aviso(context, e.detail ?? _textoPorDefecto(e));
      ref.invalidate(taskDetailProvider(taskId));
      ref.invalidate(tasksListProvider);
      return null;
    }
    if (e.sinConexion) {
      _aviso(context, 'Esta acción requiere conexión. Inténtalo cuando tengas cobertura.');
      return null;
    }
    rethrow;
  }
}

String _textoPorDefecto(ApiException e) {
  if (e.sinPermiso) return 'No tienes permiso para esta acción.';
  if (e.tareaFirmada) return 'La tarea ya está firmada y no se puede modificar.';
  if (e.noEditable) return 'Este servicio ya no se puede modificar desde la APP.';
  if (e.listaDesactualizada) return 'Los datos han cambiado. Se ha actualizado la tarea.';
  return 'Esta acción no se puede hacer sobre esta tarea.';
}

void _aviso(BuildContext context, String texto) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(texto)));
}