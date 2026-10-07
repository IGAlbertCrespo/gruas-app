import 'package:flutter/material.dart';

import 'horas.dart';
import 'pausa_dialog.dart' show fmtHoras;

/// Horas totales del servicio (modo duración), en pasos de 30 min, y comida
/// opcional (salvo regla `nunca`). Devuelve null si el conductor cancela.
 ///
 /// Si se conoce la [apertura], muestra la hora de fin resultante como ayuda.

Future<({double horas, double comida})?> pickHorasTotales(
   BuildContext context, {
   required double inicial,
   DateTime? apertura,
  ReglaComida regla = ReglaComida.nunca,
 }) {
   return showDialog<({double horas, double comida})>(
     context: context,
     builder: (_) => _HorasTotalesDialog(inicial: inicial, apertura: apertura, regla: regla),
   );
 }

class _HorasTotalesDialog extends StatefulWidget {
  const _HorasTotalesDialog({required this.inicial, this.apertura, required this.regla});

  final double inicial;
  final DateTime? apertura;
  final ReglaComida regla;

  @override
  State<_HorasTotalesDialog> createState() => _HorasTotalesDialogState();
}

class _HorasTotalesDialogState extends State<_HorasTotalesDialog> {
  static const double _paso = 0.5;
  late double _horas;
  static const double _comidaMax = 3.0;
  double _comida = 0; // 0 = sin comida

  void _sumarComida(double delta) => setState(() {
        _comida = (_comida + delta).clamp(0.0, _comidaMax).toDouble();
      });

  @override
  void initState() {
    super.initState();
    _horas = widget.inicial.clamp(horasTotalesMin, horasTotalesMax).toDouble();
  }

  void _sumar(double delta) => setState(() {
        _horas = (_horas + delta).clamp(horasTotalesMin, horasTotalesMax).toDouble();
      });

  String _hm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final ap = widget.apertura?.toLocal();
    final finH = _horas + (widget.regla == ReglaComida.soloHorario ? _comida : 0);
    final fin = ap?.add(Duration(minutes: (finH * 60).round()));
    return AlertDialog(
      title: const Text('Horas totales del servicio'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
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
                onPressed: _horas < horasTotalesMax ? () => _sumar(_paso) : null,
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (ap != null && fin != null)
            Text('Inicio ${_hm(ap)}  ·  Fin ${_hm(fin)}',
                style: const TextStyle(fontSize: 15)),
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
