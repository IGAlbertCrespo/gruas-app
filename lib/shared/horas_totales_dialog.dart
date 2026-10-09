import 'package:flutter/material.dart';

import 'horas.dart';
import 'pausa_dialog.dart' show fmtHoras;

/// Horas del servicio desde la [apertura], en pasos de 30 min, y comida
/// opcional (salvo regla `nunca`). Devuelve null si el conductor cancela.
///
/// - Muestra el inicio y el fin resultante CON FECHA.
/// - [maximo]: tope (p. ej. tiempo transcurrido hasta ahora, para que el fin
///   nunca sea futuro). Por defecto [horasTotalesMax].
/// - Lo usan el cierre facturable (modo duración) y las no facturables
///   ("¿Cuánto duró?").
Future<({double horas, double comida})?> pickHorasTotales(
  BuildContext context, {
  required double inicial,
  DateTime? apertura,
  ReglaComida regla = ReglaComida.nunca,
  String titulo = 'Horas totales del servicio',
  double? maximo,
}) {
  return showDialog<({double horas, double comida})>(
    context: context,
    builder: (_) => _HorasTotalesDialog(
      inicial: inicial,
      apertura: apertura,
      regla: regla,
      titulo: titulo,
      maximo: maximo,
    ),
  );
}

class _HorasTotalesDialog extends StatefulWidget {
  const _HorasTotalesDialog({
    required this.inicial,
    this.apertura,
    required this.regla,
    required this.titulo,
    this.maximo,
  });

  final double inicial;
  final DateTime? apertura;
  final ReglaComida regla;
  final String titulo;
  final double? maximo;

  @override
  State<_HorasTotalesDialog> createState() => _HorasTotalesDialogState();
}

class _HorasTotalesDialogState extends State<_HorasTotalesDialog> {
  static const double _paso = 0.5;
  static const double _comidaMax = 3.0;

  late final double _max =
      (widget.maximo ?? horasTotalesMax).clamp(horasTotalesMin, horasTotalesMax).toDouble();
  late double _horas = widget.inicial.clamp(horasTotalesMin, _max).toDouble();
  double _comida = 0; // 0 = sin comida

  void _sumar(double delta) => setState(() {
        _horas = (_horas + delta).clamp(horasTotalesMin, _max).toDouble();
      });

  void _sumarComida(double delta) => setState(() {
        _comida = (_comida + delta).clamp(0.0, _comidaMax).toDouble();
      });

  @override
  Widget build(BuildContext context) {
    final ap = widget.apertura;
    // Con `solo_horario` la ventana guardada es H + C.
    final finH = _horas + (widget.regla == ReglaComida.soloHorario ? _comida : 0);
    final fin = ap?.add(Duration(minutes: (finH * 60).round()));

    return AlertDialog(
      title: Text(widget.titulo),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (ap != null) ...[
            Text('Empezó el ${fmtDiaHora(ap)}', style: const TextStyle(fontSize: 15)),
            const SizedBox(height: 12),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton.filledTonal(
                iconSize: 32,
                onPressed: _horas > horasTotalesMin ? () => _sumar(-_paso) : null,
                icon: const Icon(Icons.remove),
              ),
              SizedBox(
                width: 140,
                child: Text(
                  fmtHoras(_horas),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                ),
              ),
              IconButton.filledTonal(
                iconSize: 32,
                onPressed: _horas < _max ? () => _sumar(_paso) : null,
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (fin != null)
            Text('Fin: ${fmtDiaHora(fin)}',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          if (widget.regla != ReglaComida.nunca) ...[
            const SizedBox(height: 4),
            Text(
              widget.regla == ReglaComida.siempre
                  ? 'Incluye el tiempo de comida.'
                  : 'Sin contar el tiempo de comida.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black54, fontSize: 13),
            ),
            const SizedBox(height: 8),
            if (_comida == 0)
              TextButton.icon(
                onPressed: () => _sumarComida(1.0),
                icon: const Icon(Icons.restaurant),
                label: const Text('Añadir comida'),
              )
            else
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.restaurant, size: 20),
                IconButton(onPressed: () => _sumarComida(-_paso), icon: const Icon(Icons.remove)),
                Text('Comida ${fmtHoras(_comida)}', style: const TextStyle(fontSize: 16)),
                IconButton(
                  onPressed: _comida < _comidaMax ? () => _sumarComida(_paso) : null,
                  icon: const Icon(Icons.add),
                ),
              ]),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () => Navigator.pop(context, (horas: _horas, comida: _comida)),
          child: const Text('Continuar'),
        ),
      ],
    );
  }
}