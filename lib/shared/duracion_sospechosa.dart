import 'package:flutter/material.dart';

import '../core/network/api_exception.dart';

/// Ejecuta [enviar] y, si el servidor responde 422 `duracion_sospechosa`
/// (ventana de más de 16 h), muestra el `detail` y, si el conductor confirma,
/// reenvía con `confirmar = true`.
///
/// Devuelve `null` si el conductor elige revisar (no se ha guardado nada: el
/// servidor valida ANTES de escribir). Cualquier otro error se propaga.
///
/// Uso: cierre de facturables (/close) y completar no facturables (/complete).
Future<T?> conConfirmacionDuracion<T>(
  BuildContext context,
  Future<T> Function(bool confirmar) enviar,
) async {
  try {
    return await enviar(false);
  } on ApiException catch (e) {
    if (e.code != 'duracion_sospechosa' || !context.mounted) rethrow;
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Duración inusual'),
        content: Text(e.detail ?? 'La duración indicada supera las 16 horas.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Revisar horas')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Es correcto')),
        ],
      ),
    );
    if (ok != true) return null;
    return enviar(true);
  }
}