import 'package:flutter/material.dart';

import '../../../shared/pausa_dialog.dart' show fmtHoras;
import '../task_models.dart';

/// Pinta `resumen_albaran` tal como lo resuelve el servidor (CONTRATO §4.4).
/// No recalcula nada. Nunca muestra la cifra del servicio mínimo.
class ResumenAlbaranView extends StatelessWidget {
  const ResumenAlbaranView({super.key, required this.resumen, this.mostrarObs = true});

  final ResumenAlbaran resumen;
  final bool mostrarObs;

  static String _two(int n) => n.toString().padLeft(2, '0');
  static String _hm(DateTime d) {
    final l = d.toLocal();
    return '${_two(l.hour)}:${_two(l.minute)}';
  }

  static String _fh(DateTime d) {
    final l = d.toLocal();
    return '${_two(l.day)}/${_two(l.month)} ${_hm(l)}';
  }
  static String _dmy(DateTime d) => '${_two(d.day)}/${_two(d.month)}/${d.year}';

  @override
  Widget build(BuildContext context) {
    final r = resumen;
    // 'horas' no muestra fin; en 'minimo' el servidor solo lo envía si
    // minimo_mostrar_fin está activo.
    final verFin = r.fin != null && r.modo != 'horas';

    String? comida;
    final c = r.esMinimo ? null : r.comida;
    if (c != null) {
      if (c.inicio != null && c.fin != null) {
        comida = '${_hm(c.inicio!)} – ${_hm(c.fin!)}';
      } else if ((c.duracion ?? 0) > 0) {
        comida = fmtHoras(c.duracion!);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (r.esIncidencia) _chip('Incidencia', Colors.red),
        if (r.inicio == null && r.fecha != null) _fila('Fecha', _dmy(r.fecha!)),
        if (r.inicio != null) _fila('Inicio', _fh(r.inicio!)),
        if (verFin) _fila('Fin', _fh(r.fin!)),
        if (comida != null) _fila('Comida', comida),
        if (r.esMinimo)
          _fila('Facturación', 'Servicio mínimo')
        else if (r.horas != null)
          _fila('Horas', fmtHoras(r.horas!)),
        if (mostrarObs && r.obsConductor != null)
          _obs('Observaciones del conductor', r.obsConductor!),
        if (mostrarObs && r.obsCliente != null)
          _obs('Observaciones del cliente', r.obsCliente!),
      ],
    );
  }

  Widget _fila(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 110, child: Text(k, style: const TextStyle(color: Colors.black54))),
          Expanded(child: Text(v)),
        ]),
      );

  Widget _obs(String k, String v) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(k, style: const TextStyle(color: Colors.black54, fontSize: 12)),
          Text(v),
        ]),
      );

  Widget _chip(String texto, MaterialColor color) => Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: color.shade50, borderRadius: BorderRadius.circular(6)),
        child: Text(texto, style: TextStyle(color: color.shade700, fontSize: 11)),
      );
}