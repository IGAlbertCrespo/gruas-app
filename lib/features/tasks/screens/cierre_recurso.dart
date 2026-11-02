import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../shared/duracion_sospechosa.dart';
import '../../../shared/formulario_tiempo.dart';
import '../../../shared/horas.dart';
import '../../../shared/location.dart';
import '../../auth/session_controller.dart';
import '../../auth/session_models.dart';
import '../task_models.dart';
import '../tasks_providers.dart';
import '../tasks_repository.dart' show JornadaStart;
import 'jornada_aviso.dart';


/// Cierre de UN recurso (CONTRATO v3.10 §4). Devuelve true si el servidor lo cerró.
///
/// 1. Pantalla única de tiempo ([pedirTiempo]) con los formatos de la compañía:
///    sin solo horas, con el inicio real (corregible); con solo horas, con la
///    hora planificada propuesta y el día planificado.
/// 2. Si el facturable provisional (§4.2, redondeo de la compañía) queda bajo el
///    mínimo: pregunta por incidencia SIN cifras. Sí → observaciones obligatorias.
/// 3. POST /close. El servidor es la autoridad (redondeo, mínimo, 16 h).
///
/// `409 tarea_firmada` / `409 no_editable` (v3.3): se muestra el `detail`, se
/// refresca la madre ([madreId]) y devuelve false. El resto de errores de API
/// se propagan: los llamantes ya los muestran.
Future<bool> cerrarRecursoDialog(BuildContext context, WidgetRef ref, Recurso r,
    {int? madreId}) async {
  final cfg = ref.read(sessionControllerProvider).profile?.config ?? SessionConfig.fallback;
  final regla = reglaComidaDe(cfg.comida);
  // Hora planificada (propuesta de inicio con solo horas): la del servicio en
  // pantalla. El conductor la puede cambiar; con formato "horas" la pone el servidor.
  final planificada = ref.read(taskDetailProvider(madreId ?? r.id)).valueOrNull?.fechaServicio;
  final inicioReal = cfg.soloHoras ? null : r.aperturaInformada;

  // Bucle: "Revisar horas" o "revisar" ante duración sospechosa reabren la pantalla.
  while (true) {
    if (!context.mounted) return false;
    final tiempo = await pedirTiempo(
      context,
      formatos: cfg.formatosCierre,
      cfg: cfg,
      inicioReal: inicioReal,
      inicioPropuesto: cfg.soloHoras ? planificada : null,
      dia: cfg.soloHoras ? planificada : null,
      horasPrevistas: r.horasPrevistas,
      titulo: 'Fin del servicio',
      subtitulo: r.recurso,
    );
    if (tiempo == null || !context.mounted) return false;

    // Provisional SOLO para decidir si se pregunta por incidencia (§4.2–4.3).
    var incidencia = false;
    String? obs;
    final provisional = facturableTiempo(
      tiempo.bruto,
      tiempo.comidaHoras,
      regla,
      esInicioFin: tiempo.formato == FormatoCierre.inicioFin,
      unidadMin: cfg.tiempo.redondeoMin,
      toleranciaMin: cfg.tiempo.toleranciaMin,
    );
    if (r.servicioMinimo > 0 && provisional < r.servicioMinimo) {
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
    final ({TaskDetail task, JornadaStart? jornada})? res;
    try {
      res = await conConfirmacionDuracion(
        context,
        (confirmar) => ref.read(tasksRepoProvider).close(
              r.id,
              tiempo: tiempo,
              enviarInicio: cfg.soloHoras || tiempo.inicioCambiado,
              incidencia: incidencia,
              obsAlbaran: obs,
              confirmar: confirmar,
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

    // Comida al libro de jornada (se concilia al fichar salida), salvo que la
    // jornada la construya el servidor a partir de las tareas (v3.8 §6.4).
    if (!cfg.jornadaDesdeTareas) {
      await ref.read(journeyLedgerProvider).setDeclared(r.id, tiempo.comidaHoras);
    }
    if (context.mounted) await tratarJornada(context, ref, res.jornada);
    return true;
  }
}

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

