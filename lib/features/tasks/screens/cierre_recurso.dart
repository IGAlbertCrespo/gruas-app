import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../shared/accion_tarea.dart';
import '../../../shared/duracion_sospechosa.dart';
import '../../../shared/formulario_tiempo.dart';
import '../../../shared/horas.dart';
import '../../../shared/location.dart';
import '../../../shared/observaciones_dialog.dart';
import '../../../shared/widgets/upgrade_required.dart' show mostrarErrorAccion;
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
///
/// v3.13:
/// - El formulario se abre con lo ya declarado ([Recurso.declarado]) al editar.
/// - [alEnviar] se llama justo antes de la parte de red (tras el formulario y
///   los diálogos), para que el llamante tape la pantalla con `EsperaRelax`.
/// - La ubicación se pide en paralelo mientras se rellenan las horas (sin
///   pedir permiso: si no lo hay, se pide como siempre al final).
Future<bool> cerrarRecursoDialog(BuildContext context, WidgetRef ref, Recurso r,
    {int? madreId, VoidCallback? alEnviar}) async {
  final cfg = ref.read(sessionControllerProvider).profile?.config ?? SessionConfig.fallback;
  final ubicacionPrevia = ubicacionSiHayPermiso();
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
      conObservaciones: true, // v3.12: observaciones siempre en el formulario de horas
      obsInicial: r.obsAlbaran,
      avisoCliente: true,
      inicial: r.declarado, // v3.13: al editar, lo ya declarado
    );
    if (tiempo == null || !context.mounted) return false;

    // Provisional SOLO para decidir si se pregunta por incidencia (§4.2–4.3).
    var incidencia = false;
    // v3.12: las del formulario; null = se conservan las guardadas en el servidor.
    String? obs = tiempo.obs;
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
        // v3.12: precargadas con las ya escritas (el resumen es null antes del cierre).
        obs = await pedirObsAlbaran(
          context,
          inicial: tiempo.obs ?? r.obsAlbaran ?? r.resumenAlbaran?.obsConductor,
          obligatoria: true,
          titulo: 'Incidencia',
          accion: 'Continuar',
          hint: 'Describe la incidencia…',
        );
        if (obs == null || !context.mounted) return false;
        incidencia = true;
      }
    }
    alEnviar?.call();
    var (lat, lng) = await ubicacionPrevia;
    if (lat == null) {
      (lat, lng) = await bestEffortLocation(); // sin permiso concedido aún: se pide ahora
    }
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

// ---------------------------------------------------------------------------
// v3.13 §4.9 — Borrar horas
// ---------------------------------------------------------------------------

/// "Borrar horas" solo existe con solo horas y sin control de jornada (a nivel
/// de compañía): es el único caso sin apertura previa en que pueden quedar
/// tareas de días anteriores a medias. El resto de condiciones (recurso propio,
/// cerrado, no iniciado, tarea sin finalizar ni firmar) las mira el llamante.
bool puedeBorrarHoras(SessionConfig? cfg) =>
    (cfg?.soloHoras ?? false) && !(cfg?.controlJornada ?? false);

/// Pregunta y borra las horas de [taskId] (recurso o no facturable).
///
/// 1. Confirmación.
/// 2. Solo si hay [obs] (observaciones del albarán): pregunta explícita de si
///    se borran también.
/// 3. `POST /borrar-horas` ([alEnviar] justo antes, para la capa de espera).
///
/// Devuelve true si el servidor las borró. Errores `409` y sin conexión los
/// trata [ejecutarAccionTarea]; el resto se muestran aquí.
Future<bool> borrarHorasDialog(
  BuildContext context,
  WidgetRef ref, {
  required int taskId,
  required String nombre,
  String? obs,
  int? madreId,
  VoidCallback? alEnviar,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Borrar horas'),
      content: Text('¿Borrar las horas de $nombre?\n\nLa tarea volverá a «Para hacer».'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Borrar'),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return false;

  var borrarObs = false;
  final texto = (obs ?? '').trim();
  if (texto.isNotEmpty) {
    final r = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Observaciones del albarán'),
        content: Text('¿Borrar también las observaciones del albarán?\n\n«$texto»'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Conservar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Borrar')),
        ],
      ),
    );
    if (r == null || !context.mounted) return false;
    borrarObs = r;
  }

  alEnviar?.call();
  try {
    final res = await ejecutarAccionTarea(
      context,
      ref,
      madreId ?? taskId,
      () => ref.read(tasksRepoProvider).borrarHoras(taskId, borrarObs: borrarObs),
    );
    if (res == null) return false; // 409 / sin conexión: ya avisado y refrescado
  } catch (e) {
    if (context.mounted) await mostrarErrorAccion(context, e, prefijo: 'No se pudieron borrar: ');
    return false;
  }
  // La comida declarada de ese recurso deja de contar para la jornada.
  await ref.read(journeyLedgerProvider).setDeclared(taskId, 0);
  ref.invalidate(taskDetailProvider(taskId));
  if (madreId != null && madreId != taskId) ref.invalidate(taskDetailProvider(madreId));
  ref.invalidate(tasksListProvider);
  return true;
}

enum _RespIncidencia { revisar, no, si }

/// Diálogo SIN cifras (regla de negocio 1: la APP nunca muestra el mínimo).
/// Horas por debajo del mínimo. Lo habitual es que NO haya incidencia: la
/// respuesta destacada (y con el foco) es "Sin incidencias" → servicio mínimo.
/// "Hubo una incidencia" pide el motivo (obligatorio). Sin cifras (regla 1).
Future<_RespIncidencia?> _preguntarIncidencia(BuildContext context) =>
    showDialog<_RespIncidencia>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Todo normal en el servicio?'),
        content: const Text('Las horas indicadas no llegan al mínimo del servicio. '
            'Si no ha habido ninguna incidencia, se facturará el servicio mínimo.'),
        actionsOverflowButtonSpacing: 4,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, _RespIncidencia.revisar),
            child: const Text('Revisar horas'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx, _RespIncidencia.si),
            child: const Text('Hubo una incidencia'),
          ),
          FilledButton(
            autofocus: true,
            onPressed: () => Navigator.pop(ctx, _RespIncidencia.no),
            child: const Text('Sin incidencias'),
          ),
        ],
      ),
    );