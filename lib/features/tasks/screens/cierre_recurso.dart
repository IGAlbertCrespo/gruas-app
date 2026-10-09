import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../shared/duracion_sospechosa.dart';
import '../../../shared/horas.dart';
import '../../../shared/horas_totales_dialog.dart';
import '../../../shared/location.dart';
import '../../../shared/pausa_dialog.dart' show fmtHoras;
import '../../../shared/selector_hora.dart';
import '../../auth/session_controller.dart';
import '../../auth/session_models.dart';
import '../task_models.dart';
import '../tasks_providers.dart';
import 'task_detail_screen.dart' show pickFriendlyTime;

/// Cierre de UN recurso (CONTRATO v3.1 §4). Devuelve true si el servidor lo cerró.
///
/// 1. Modo (si la compañía tiene `elegir`): horario u horas totales.
/// 2. Horario: hora de fin con la FECHA DEDUCIDA del inicio + franja de comida.
///    Si la ventana supera 16 h: corregir fin / corregir inicio / es correcto.
///    Horas totales: "empezó tal día, ¿cuántas horas?" + comida opcional; el
///    máximo es el tiempo transcurrido (el fin nunca es futuro).
/// 3. Si el facturable provisional (§4.2) queda bajo el mínimo: pregunta por
///    incidencia SIN cifras. Sí → observaciones del conductor obligatorias.
/// 4. POST /close. El mínimo lo decide el servidor. `apertura_informada` solo
///    viaja si el conductor ha corregido el inicio.
///
/// `409 tarea_firmada` / `409 no_editable` (v3.3): se muestra el `detail`, se
/// refresca la madre ([madreId]) y devuelve false. El resto de errores de API
/// se propagan: los llamantes ya los muestran.
Future<bool> cerrarRecursoDialog(BuildContext context, WidgetRef ref, Recurso r,
    {int? madreId}) async {
  final cfg = ref.read(sessionControllerProvider).profile?.config ?? SessionConfig.fallback;
  final regla = reglaComidaDe(cfg.comida);

  final bool porDuracion;
  if (cfg.cierreElegir) {
    final m = await _pickModoCierre(context);
    if (m == null || !context.mounted) return false;
    porDuracion = m;
  } else {
    porDuracion = cfg.cierrePorDuracion;
  }

  DateTime? aperturaCorregida; // "Corregir inicio" → apertura_informada

  // Bucle: "Revisar horas", "Corregir fin/inicio" o duración sospechosa
  // vuelven a pedir las horas.
  while (true) {
    if (!context.mounted) return false;
    final apertura = aperturaCorregida ?? r.aperturaInformada;

    DateTime? cierre;
    double? horasTotales;
    FranjaComida? franja;
    double comida = 0;
    var confirmado = false; // "Es correcto" ante ventana > 16 h

    if (porDuracion) {
      final res = await pickHorasTotales(
        context,
        inicial: horasTotalesIniciales(apertura: apertura), // sin mínimo: nunca se insinúa la cifra
        apertura: apertura,
        regla: regla,
        maximo: apertura != null ? horasMaxHasta(apertura) : null,
      );
      if (res == null || !context.mounted) return false;
      horasTotales = res.horas;
      comida = res.comida;
    } else {
      cierre = apertura != null
          ? await pickHoraFin(context, apertura)
          : await pickFriendlyTime(context); // sin apertura (anómalo): comportamiento v2
      if (cierre == null || !context.mounted) return false;

      if (apertura != null && horasEntre(apertura, cierre) > umbralOlvidoHoras) {
        final resp = await _avisoServicioLargo(context, apertura, cierre);
        if (resp == null || !context.mounted) return false;
        if (resp == _RespLargo.corregirFin) continue;
        if (resp == _RespLargo.corregirInicio) {
          final ni = await pickFechaHoraInicio(
            context,
            desde: r.aperturaInformada ?? apertura,
            inicial: apertura,
            atajos: false,
          );
          if (ni != null) aperturaCorregida = ni;
          continue;
        }
        confirmado = true;
      }

      if (regla != ReglaComida.nunca && apertura != null) {
        final res = await pickFranjaComida(
          context,
          inicio: apertura,
          fin: cierre,
          minutoDefecto: cfg.comidaHoraDefectoMin,
        );
        if (res == null || !context.mounted) return false;
        franja = res.franja;
        comida = franja?.horas ?? 0;
      }
    }

    // Provisional SOLO para decidir si se pregunta por incidencia (§4.2–4.3).
    var incidencia = false;
    String? obs;
    final double? provisional = porDuracion
        ? facturableDuracion(horasTotales!, comida, regla)
        : (apertura != null ? facturableHorario(apertura, cierre!, comida, regla) : null);
    if (r.servicioMinimo > 0 && provisional != null && provisional < r.servicioMinimo) {
      final resp = await _preguntarIncidencia(context);
      if (resp == null || !context.mounted) return false;
      if (resp == _RespIncidencia.revisar) continue;
      if (resp == _RespIncidencia.si) {
        obs = await _pedirObsConductor(context, inicial: r.resumenAlbaran?.obsConductor);
        if (obs == null || !context.mounted) return false;
        incidencia = true;
      }
    }

    final (lat, lng) = await bestEffortLocation();
    if (!context.mounted) return false;
    final TaskDetail? res;
    try {
      res = await conConfirmacionDuracion(
        context,
        (confirmar) => ref.read(tasksRepoProvider).close(
              r.id,
              modoCierre: porDuracion ? 'duracion' : 'hora',
              aperturaInformada: aperturaCorregida,
              cierreInformada: cierre,
              horasTotales: horasTotales,
              comidaInicio: franja?.inicio,
              comidaFin: franja?.fin,
              comidaDuracion: porDuracion && comida > 0 ? comida : null,
              incidencia: incidencia,
              obsAlbaran: obs,
              confirmar: confirmar || confirmado,
              lat: lat,
              lng: lng,
            ),
      );
    } on ApiException catch (e) {
      if (!(e.tareaFirmada || e.noEditable)) rethrow;
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e.detail ?? 'Este servicio ya no se puede modificar desde la APP.')));
      }
      ref.invalidate(taskDetailProvider(madreId ?? r.id));
      ref.invalidate(tasksListProvider);
      return false;
    }
    if (res == null) continue; // eligió revisar: el servidor no ha guardado nada

    // Comida declarada al libro de jornada (clave = recurso: re-cerrar
    // sobrescribe). Se concilia al fichar salida.
    await ref.read(journeyLedgerProvider).setDeclared(r.id, comida);
    return true;
  }
}

enum _RespLargo { corregirFin, corregirInicio, esCorrecto }

/// Ventana > 16 h: casi siempre es un error de hora (fin o inicio).
Future<_RespLargo?> _avisoServicioLargo(BuildContext context, DateTime inicio, DateTime fin) =>
    showDialog<_RespLargo>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Servicio muy largo'),
        content: Text('${fmtDiaHora(inicio)} → ${fmtDiaHora(fin)}\n'
            'Duración: ${fmtHoras(horasEntre(inicio, fin))}\n\n¿Es correcto?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, _RespLargo.corregirInicio),
            child: const Text('Corregir inicio'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, _RespLargo.corregirFin),
            child: const Text('Corregir fin'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, _RespLargo.esCorrecto),
            child: const Text('Es correcto'),
          ),
        ],
      ),
    );

/// true = horas totales · false = horario · null = cancelar.
Future<bool?> _pickModoCierre(BuildContext context) => showDialog<bool>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('¿Cómo indicas el servicio?'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, false),
            child: const ListTile(
              leading: Icon(Icons.schedule),
              title: Text('Horario'),
              subtitle: Text('Hora de fin y franja de comida'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, true),
            child: const ListTile(
              leading: Icon(Icons.timelapse),
              title: Text('Horas totales'),
              subtitle: Text('Número de horas del servicio'),
            ),
          ),
        ],
      ),
    );

enum _RespIncidencia { revisar, no, si }

/// Diálogo SIN cifras (regla de negocio 1: la APP nunca muestra el mínimo).
Future<_RespIncidencia?> _preguntarIncidencia(BuildContext context) =>
    showDialog<_RespIncidencia>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Servicio mínimo'),
        content: const Text('Las horas indicadas no llegan al servicio mínimo. '
            '¿Ha habido alguna incidencia en el servicio?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, _RespIncidencia.revisar),
            child: const Text('Revisar horas'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx, _RespIncidencia.no),
            child: const Text('No'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, _RespIncidencia.si),
            child: const Text('Sí'),
          ),
        ],
      ),
    );

/// Observaciones del conductor obligatorias (un "." vale). null = cancelar.
Future<String?> _pedirObsConductor(BuildContext context, {String? inicial}) =>
    showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ObsConductorDialog(inicial: inicial),
    );

class _ObsConductorDialog extends StatefulWidget {
  const _ObsConductorDialog({this.inicial});
  final String? inicial;
  @override
  State<_ObsConductorDialog> createState() => _ObsConductorDialogState();
}

class _ObsConductorDialogState extends State<_ObsConductorDialog> {
  late final _ctrl = TextEditingController(text: widget.inicial ?? '');

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _close([String? value]) {
    FocusScope.of(context).unfocus(); // suelta el teclado antes del pop
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final texto = _ctrl.text.trim();
    return AlertDialog(
      title: const Text('Incidencia'),
      content: TextField(
        controller: _ctrl,
        minLines: 3,
        maxLines: 6,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          labelText: 'Observaciones del conductor',
          hintText: 'Describe la incidencia…',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(onPressed: () => _close(), child: const Text('Cancelar')),
        FilledButton(
          onPressed: texto.isEmpty ? null : () => _close(texto),
          child: const Text('Continuar'),
        ),
      ],
    );
  }
}

/// Franja de comida (hora local). `horas` en múltiplos de 0,5.
class FranjaComida {
  final DateTime inicio;
  final DateTime fin;
  const FranjaComida(this.inicio, this.fin);
  double get horas => fin.difference(inicio).inMinutes / 60.0;
}

/// Selector de franja limitado a la ventana [inicio, fin] del horario, en pasos
/// de 30 min alineados al reloj. Devuelve null si cancela; `(franja: null)` si
/// elige "Sin comida" (o si en la ventana no cabe una franja de 30 min).
Future<({FranjaComida? franja})?> pickFranjaComida(
  BuildContext context, {
  required DateTime inicio,
  required DateTime fin,
  required int minutoDefecto,
}) {
  final rejilla = rejillaComida(inicio, fin);
  if (rejilla.length < 2) return Future.value((franja: null));
  final (i, f) = franjaPorDefecto(rejilla, minutoDefecto);
  return showDialog<({FranjaComida? franja})>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _FranjaComidaDialog(
      rejilla: rejilla,
      iInicial: i,
      fInicial: f,
      ventana: '${fmtDiaHora(inicio)} → ${fmtDiaHora(normalizarFin(inicio, fin))}',
    ),
  );
}

class _FranjaComidaDialog extends StatefulWidget {
  const _FranjaComidaDialog({
    required this.rejilla,
    required this.iInicial,
    required this.fInicial,
    required this.ventana,
  });
  final List<DateTime> rejilla;
  final String ventana; // servicio completo, con fechas
  final int iInicial;
  final int fInicial;
  @override
  State<_FranjaComidaDialog> createState() => _FranjaComidaDialogState();
}

class _FranjaComidaDialogState extends State<_FranjaComidaDialog> {
  late int _i = widget.iInicial; // índice inicio comida
  late int _f = widget.fInicial; // índice fin comida (siempre > _i)

  int get _ultimo => widget.rejilla.length - 1;

  static String _hm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  Widget _paso(String titulo, int idx, VoidCallback? menos, VoidCallback? mas) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(width: 56, child: Text(titulo, style: const TextStyle(color: Colors.black54))),
          IconButton.filledTonal(onPressed: menos, icon: const Icon(Icons.remove)),
          SizedBox(
            width: 90,
            child: Text(_hm(widget.rejilla[idx]),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          ),
          IconButton.filledTonal(onPressed: mas, icon: const Icon(Icons.add)),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final r = widget.rejilla;
    final franja = FranjaComida(r[_i], r[_f]);
    return AlertDialog(
      title: const Text('Franja de comida'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.ventana, style: const TextStyle(color: Colors.black54)),
          const SizedBox(height: 12),
          _paso('Inicio', _i,
              _i > 0 ? () => setState(() => _i--) : null,
              _i < _f - 1 ? () => setState(() => _i++) : null),
          const SizedBox(height: 12),
          _paso('Fin', _f,
              _f > _i + 1 ? () => setState(() => _f--) : null,
              _f < _ultimo ? () => setState(() => _f++) : null),
          const SizedBox(height: 12),
          Text('Comida: ${fmtHoras(franja.horas)}', style: const TextStyle(fontSize: 15)),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        OutlinedButton(
          onPressed: () => Navigator.pop(context, (franja: null)),
          child: const Text('Sin comida'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, (franja: franja)),
          child: const Text('Aceptar'),
        ),
      ],
    );
  }
}