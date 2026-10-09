import 'package:flutter/material.dart';

import 'horas.dart';

/// Selectores de hora con FECHA controlada (v3):
/// - [pickHoraFin]: fin de un servicio con la fecha deducida del inicio.
/// - [pickFechaHoraInicio]: inicio con fecha limitada a [desde, hoy].
///
/// `pickFriendlyTime` (task_detail_screen) se mantiene solo para INICIAR una
/// tarea, donde anclar a "ahora" es lo correcto.

Future<void> _aviso(BuildContext context, String texto) => showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(texto),
        actions: [
          FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Entendido')),
        ],
      ),
    );

/// Atajos habituales. Devuelve 'now' | 'm30' | 'h1' | 'custom' o null (cancelar).
Future<String?> _atajos(BuildContext context, String titulo, String textoOtro) =>
    showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text(titulo, style: const TextStyle(fontWeight: FontWeight.bold))),
            ListTile(
                leading: const Icon(Icons.schedule),
                title: const Text('Ahora'),
                onTap: () => Navigator.pop(ctx, 'now')),
            ListTile(
                leading: const Icon(Icons.history),
                title: const Text('Hace 30 min'),
                onTap: () => Navigator.pop(ctx, 'm30')),
            ListTile(
                leading: const Icon(Icons.history),
                title: const Text('Hace 1 hora'),
                onTap: () => Navigator.pop(ctx, 'h1')),
            ListTile(
                leading: const Icon(Icons.edit_calendar),
                title: Text(textoOtro),
                onTap: () => Navigator.pop(ctx, 'custom')),
          ],
        ),
      ),
    );

DateTime? _deAtajo(String choice) => switch (choice) {
      'now' => DateTime.now(),
      'm30' => DateTime.now().subtract(const Duration(minutes: 30)),
      'h1' => DateTime.now().subtract(const Duration(hours: 1)),
      _ => null,
    };

/// Hora de fin de un servicio que empezó en [inicio].
///
/// - Fecha deducida: primera vez que la hora elegida ocurre tras el inicio
///   (misma regla que `_normalizar_ventana` del servidor, anclada al inicio).
/// - Atajos Ahora/30 min/1 h solo si el inicio es reciente (≤ 16 h).
/// - Nunca futura ni anterior al inicio: avisa y vuelve a pedir.
/// - Si el fin no es de hoy, se confirma mostrando la fecha completa.
///
/// Devuelve null si el conductor cancela.
Future<DateTime?> pickHoraFin(BuildContext context, DateTime inicio) async {
  final reciente = inicioReciente(inicio);
  final cabecera = 'Hora de fin · inicio ${fmtDiaHora(inicio)}';

  while (true) {
    var choice = 'custom';
    if (reciente) {
      final c = await _atajos(context, cabecera, 'Otra hora…');
      if (c == null || !context.mounted) return null;
      choice = c;
    }

    var fin = _deAtajo(choice);
    final elegidaEnReloj = fin == null;
    if (fin == null) {
      final ini = inicio.toLocal();
      final tm = await showTimePicker(
        context: context,
        initialTime: reciente
            ? TimeOfDay.now()
            : TimeOfDay.fromDateTime(ini.add(const Duration(hours: 1))),
        helpText: cabecera,
      );
      if (tm == null || !context.mounted) return null;
      fin = finTrasInicio(inicio, tm.hour, tm.minute);
    }

    if (esFuturo(fin)) {
      await _aviso(context, 'La hora de fin no puede ser posterior a ahora.');
    } else if (!fin.isAfter(inicio)) {
      await _aviso(context, 'La hora de fin debe ser posterior al inicio (${fmtDiaHora(inicio)}).');
    } else if (elegidaEnReloj && soloDia(fin) != soloDia(DateTime.now())) {
      final resuelto = fin;
      final ok = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Fin del servicio'),
          content: Text('${fmtDiaHora(inicio)} → ${fmtDiaHora(resuelto)}'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cambiar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Aceptar')),
          ],
        ),
      );
      if (ok == true) return fin;
    } else {
      return fin;
    }
    if (!context.mounted) return null;
  }
}

/// Inicio con fecha entre [desde] y hoy (por días) y hora no futura.
///
/// Si [desde] es posterior a hoy (tarea programada para otro día), avisa y
/// devuelve null: no se puede informar antes de la fecha programada.
/// Con [atajos], ofrece antes Ahora/30 min/1 h.
Future<DateTime?> pickFechaHoraInicio(
  BuildContext context, {
  required DateTime desde,
  DateTime? inicial,
  bool atajos = true,
  String titulo = 'Hora de inicio',
}) async {
  final primerDia = soloDia(desde);

  while (true) {
    final hoy = soloDia(DateTime.now());
    if (primerDia.isAfter(hoy)) {
      await _aviso(context,
          'Esta tarea está programada para el ${fmtDia(primerDia)}. No se puede informar antes de esa fecha.');
      return null;
    }

    var choice = 'custom';
    if (atajos) {
      final c = await _atajos(context, titulo, 'Otro día y hora…');
      if (c == null || !context.mounted) return null;
      choice = c;
    }

    var ini = _deAtajo(choice);
    if (ini == null) {
      var dia = hoy;
      if (primerDia.isBefore(hoy)) {
        final base = inicial != null ? soloDia(inicial) : hoy;
        final init = base.isBefore(primerDia) ? primerDia : (base.isAfter(hoy) ? hoy : base);
        final d = await showDatePicker(
          context: context,
          initialDate: init,
          firstDate: primerDia,
          lastDate: hoy,
          helpText: titulo,
        );
        if (d == null || !context.mounted) return null;
        dia = d;
      }
      final tm = await showTimePicker(
        context: context,
        initialTime:
            inicial != null ? TimeOfDay.fromDateTime(inicial.toLocal()) : TimeOfDay.now(),
        helpText: titulo,
      );
      if (tm == null || !context.mounted) return null;
      ini = DateTime(dia.year, dia.month, dia.day, tm.hour, tm.minute);
    }

    if (esFuturo(ini)) {
      await _aviso(context, 'La hora de inicio no puede ser posterior a ahora.');
    } else if (soloDia(ini).isBefore(primerDia)) {
      await _aviso(context, 'El inicio no puede ser anterior al ${fmtDia(primerDia)}.');
    } else {
      return ini;
    }
    if (!context.mounted) return null;
  }
}