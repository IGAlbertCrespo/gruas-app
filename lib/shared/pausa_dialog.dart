import 'package:flutter/material.dart';

/// Formatea horas decimales como texto humano: 0.5 -> "30 min", 1.0 -> "1 h",
/// 1.5 -> "1 h 30 min".
String fmtHoras(double horas) {
  final totalMin = (horas * 60).round();
  final h = totalMin ~/ 60;
  final m = totalMin % 60;
  if (h == 0) return '$m min';
  if (m == 0) return '$h h';
  return '$h h $m min';
}

/// Pausa/comida (obligatorio elegir). Se reutiliza tanto al cerrar una tarea
/// (imputación al cliente) como al fichar salida cuando no se detectó pausa
/// ("Ninguna" = no comió). No tiene Cancelar: siempre devuelve un valor.
Future<double?> pickPausa(BuildContext context) {
  return showDialog<double>(
    context: context,
    barrierDismissible: false,
    builder: (_) => SimpleDialog(
      title: const Text('Tiempo de pausa / comida'),
      children: [
        for (final opt in const [
          ('Ninguna', 0.0), ('30 min', 0.5), ('1 hora', 1.0),
          ('1 h 30 min', 1.5), ('2 horas', 2.0),
        ])
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, opt.$2),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(opt.$1, style: const TextStyle(fontSize: 16)),
            ),
          ),
      ],
    ),
  );
}

/// Confirmación para incorporar una pausa de comida a la jornada al fichar
/// salida (cuando ya se imputó al cliente pero no se fichó a mano). Propone una
/// hora de inicio. Devuelve true si el chófer acepta.
Future<bool> confirmIncorporarPausa(
    BuildContext context, double horas, DateTime inicio) async {
  final hh = inicio.hour.toString().padLeft(2, '0');
  final mm = inicio.minute.toString().padLeft(2, '0');
  final res = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      title: const Text('Incorporar pausa a tu jornada'),
      content: Text(
        'Registramos ${fmtHoras(horas)} de pausa para comer en tu jornada, '
        'a las $hh:$mm.\n\n¿La incorporamos?',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('No')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Sí')),
      ],
    ),
  );
  return res ?? false;
}

/// Diálogo final de cierre de jornada: captura observaciones (opcional) y
/// confirma el cierre. Devuelve el texto (puede ir vacío) si el chófer pulsa
/// "Finalizar jornada", o null si cancela (en cuyo caso NO se debe cerrar).
Future<String?> pedirObservaciones(BuildContext context) async {
  final ctrl = TextEditingController();
  final res = await showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Text('Finalizar jornada'),
      content: TextField(
        controller: ctrl,
        minLines: 2,
        maxLines: 4,
        autofocus: false,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          labelText: 'Observaciones (opcional)',
          hintText: 'Notas sobre la jornada…',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
          child: const Text('Finalizar jornada'),
        ),
      ],
    ),
  );
  ctrl.dispose();
  return res; // null = canceló; '' o texto = confirmó
}