import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:signature/signature.dart';

import '../../../core/network/api_exception.dart';
import '../../../shared/accion_tarea.dart';
import '../../../shared/location.dart';
import '../../../shared/widgets/upgrade_required.dart' show mostrarErrorAccion;
import '../../auth/session_controller.dart';
import '../task_models.dart';
import '../tasks_providers.dart';
import '../../../shared/horas.dart' show fmtDia;
import 'cierre_recurso.dart';
import 'conceptos_section.dart';
import 'enlace_firma.dart';
import 'resumen_albaran_view.dart';

/// Firmantes de la obra de la tarea (CONTRATO §6.1). Requiere conexión.
final _firmantesProvider =
    FutureProvider.autoDispose.family<List<Firmante>, int>((ref, taskId) {
  return ref.read(tasksRepoProvider).firmantes(taskId);
});

/// Otros albaranes de la misma obra pendientes de firma (§6.4). Sin conexión
/// o con error, simplemente no se ofrece la firma en lote.
final _pendientesProvider =
    FutureProvider.autoDispose.family<List<PendienteFirma>, int>((ref, taskId) {
  return ref.read(tasksRepoProvider).pendientesFirma(taskId);
});

/// Firma del servicio (v3, fases 5 y 6).
///
/// - Resumen: recursos (re-cerrables mientras no esté finalizada) y conceptos
///   en solo lectura.
/// - Otros albaranes pendientes de la obra: si se marcan, se firma en lote
///   (POST /firma/lote) con el mismo firmante, observaciones y firma.
/// - Quién firma: un firmante de la obra (firma dibujada obligatoria) u
///   "Otra persona" (nombre, documento, móvil opcional; regla dos de tres).
///   Con documento se da de alta como firmante al firmar (POST /firmantes).
/// - "Confirmar y firmar": /signature (+ /finalize si aún no está finalizada),
///   o /firma/lote si hay otros albaranes marcados.
/// - "Firmar más tarde" (permiso firma_diferida): /finalize diferido y
///   ofrecimiento de enviar el enlace por WhatsApp.
/// Una vez firmada, solo lectura.
class SignatureScreen extends ConsumerStatefulWidget {
  const SignatureScreen({super.key, required this.task});
  final TaskDetail task;
  @override
  ConsumerState<SignatureScreen> createState() => _SignatureScreenState();
}

class _SignatureScreenState extends ConsumerState<SignatureScreen> {
  final _controller = SignatureController(penStrokeWidth: 3, penColor: Colors.black);
  final _nombre = TextEditingController();
  final _documento = TextEditingController();
  final _movil = TextEditingController();
  late final _obs = TextEditingController(text: widget.task.worksheet.obsCliente ?? '');
  bool _busy = false;

  /// Firmante elegido de la lista; null = "Otra persona" (o aún sin elegir).
  Firmante? _firmante;

  /// true cuando el conductor ha elegido "Otra persona" (o no hay lista).
  bool _otraPersona = false;

  /// Otros albaranes pendientes marcados para firmar en lote.
  final Set<int> _lote = {};
    /// Contacto de carga del servicio: solo como sugerencia de nombre (quien pidió
  /// el servicio no tiene por qué ser quien firma).
  String? get _sugerencia {
    final c = widget.task.carga.contacto?.trim();
    return (c == null || c.isEmpty) ? null : c;
  }

  @override
  void initState() {
    super.initState();
    _nombre.addListener(() => setState(() {}));
  }

  int get _id => widget.task.id;

  /// Madre fresca (refleja ediciones de recursos y el estado de firma).
  TaskDetail get _tarea => ref.read(taskDetailProvider(_id)).valueOrNull ?? widget.task;

  @override
  void dispose() {
    _controller.dispose();
    _nombre.dispose();
    _documento.dispose();
    _movil.dispose();
    _obs.dispose();
    super.dispose();
  }

  void _snack(String texto) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(texto)));

  Future<void> _editarRecurso(Recurso r) async {
    try {
      final ok = await cerrarRecursoDialog(context, ref, r, madreId: _id);
      if (ok) ref.invalidate(taskDetailProvider(_id));
    } catch (e) {
      if (mounted) await mostrarErrorAccion(context, e, prefijo: 'No se pudo editar: ');
    }
  }

  // ─────────────────────────── Documento ───────────────────────────

  /// Mayúsculas, sin espacios ni guiones (igual que el servidor).
  static String _normalizarDoc(String s) => s.toUpperCase().replaceAll(RegExp(r'[\s\-]'), '');

  /// null = no tiene forma de DNI/NIE (se acepta como pasaporte);
  /// true/false = letra de control correcta o no.
  static bool? _letraControlOk(String doc) {
    const letras = 'TRWAGMYFPDXBNJZSQVHLCKE';
    String? numero;
    if (RegExp(r'^\d{8}[A-Z]$').hasMatch(doc)) {
      numero = doc.substring(0, 8);
    } else if (RegExp(r'^[XYZ]\d{7}[A-Z]$').hasMatch(doc)) {
      numero = '${'XYZ'.indexOf(doc[0])}${doc.substring(1, 8)}';
    }
    if (numero == null) return null;
    return letras[int.parse(numero) % 23] == doc[doc.length - 1];
  }

  // ─────────────────────────── Firmar ───────────────────────────

  Future<void> _firmarYFinalizar() async {
    final hayFirma = _controller.isNotEmpty;
    var firmante = _firmante;
    final nombre = _nombre.text.trim();
    final doc = _normalizarDoc(_documento.text);
    final movil = _movil.text.trim();

    if (firmante == null && !_otraPersona) {
      _snack('Elige quién firma.');
      return;
    }
    if (firmante != null) {
      // Firmante de la lista: la firma dibujada es obligatoria (§6.2).
      if (!hayFirma) {
        _snack('Falta la firma de ${firmante.nombre}.');
        return;
      }
    } else {
      // Regla dos de tres: firma / nombre / documento.
      final n = [hayFirma, nombre.isNotEmpty, doc.isNotEmpty].where((b) => b).length;
      if (n < 2) {
        _snack('Indica al menos dos datos: firma, nombre o documento.');
        return;
      }
      if (doc.isNotEmpty && _letraControlOk(doc) == false) {
        final seguir = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Documento'),
            content: const Text('La letra del documento no es correcta. ¿Continuar de todos modos?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Revisar')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Continuar')),
            ],
          ),
        );
        if (seguir != true || !mounted) return;
      }

      // Alta como firmante de la obra solo con nombre + documento + firma
      // (con firmante_id la firma es obligatoria). Si el documento ya existía,
      // el servidor devuelve el nombre guardado en Odoo: se muestra en la
      // tarjeta del firmante (no editable) y en la confirmación.
      if (hayFirma && nombre.isNotEmpty && doc.isNotEmpty) {
        setState(() => _busy = true);
        try {
          final f = await ejecutarAccionTarea(
            context,
            ref,
            _id,
            () => ref.read(tasksRepoProvider).crearFirmante(
                  _id,
                  nombre: nombre,
                  documento: doc,
                  movil: movil.isEmpty ? null : movil,
                ),
          );
          if (f == null || !mounted) return; // error ya mostrado (incl. sin conexión)
          firmante = f;
          setState(() {
            _firmante = f;
            _otraPersona = false;
          });
        } catch (e) {
          if (mounted) await mostrarErrorAccion(context, e);
          return;
        } finally {
          if (mounted) setState(() => _busy = false);
        }
      }
    }

    final quien = firmante != null
        ? [firmante.nombre, if ((firmante.documento ?? '').isNotEmpty) firmante.documento!]
            .join(' · ')
        : [if (nombre.isNotEmpty) nombre, if (doc.isNotEmpty) doc].join(' · ');
    final n = _lote.length + 1;
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar firma'),
        content: Text('Firma: ${quien.isEmpty ? '(solo firma)' : quien}\n\n'
            '${n > 1 ? 'Se firmarán $n albaranes con la misma firma. ' : ''}'
            'Un servicio finalizado ya no es modificable.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Revisar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirmar')),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final yaFinalizada = _tarea.firma?.faltaFirma == true;
    final otros = _lote.toList();
    final firmanteId = firmante?.id;
    // Sin firmante: nombre y/o documento sueltos (sin alta).
    final signer = firmanteId == null && nombre.isNotEmpty ? nombre : null;
    final dni = firmanteId == null && doc.isNotEmpty ? doc : null;

    setState(() => _busy = true);
    try {
      final bytes = hayFirma ? await _controller.toPngBytes() : null;
      final (lat, lng) = await bestEffortLocation();
      if (!mounted) return;
      final repo = ref.read(tasksRepoProvider);
      final firma = bytes == null ? null : base64Encode(bytes);

      final lote = await ejecutarAccionTarea(context, ref, _id, () async {
        if (otros.isNotEmpty) {
          // Lote: el servidor firma todas y finaliza la actual si solo está cerrada.
          return repo.firmarLote(
            [_id, ...otros],
            firma,
            firmanteId: firmanteId,
            signerName: signer,
            dni: dni,
            obsCliente: _obs.text.trim(),
            lat: lat,
            lng: lng,
          );
        }
        await repo.saveSignature(
          _id,
          firma,
          firmanteId: firmanteId,
          signerName: signer,
          dni: dni,
          obsCliente: _obs.text.trim(),
          lat: lat,
          lng: lng,
        );
        if (!yaFinalizada) await repo.finalize(_id, lat: lat, lng: lng);
        return '';
      });

      if (lote != null) {
        ref.invalidate(taskDetailProvider(_id));
        for (final o in otros) {
          ref.invalidate(taskDetailProvider(o));
        }
        ref.invalidate(tasksListProvider);
        if (!mounted) return;
        if (lote.isNotEmpty) _snack('Firmados $n albaranes · $lote');
        Navigator.pop(context);
      }
    } catch (e) {
      // Lote no válido (algún albarán ya no está pendiente): se refresca la
      // lista de pendientes y se desmarcan para que el conductor vuelva a elegir.
      if (e is ApiException && e.code == 'lote_invalido') {
        ref.invalidate(_pendientesProvider(_id));
        if (mounted) setState(() => _lote.clear());
      }
      if (mounted) await mostrarErrorAccion(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Finaliza sin firma (genera el enlace) y ofrece enviarlo por WhatsApp.
  Future<void> _firmarMasTarde() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Firmar más tarde'),
        content: const Text('El servicio se finalizará sin firma y quedará pendiente de firma.\n\n'
            'Una tarea finalizada ya no es modificable.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Revisar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Finalizar')),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final (lat, lng) = await bestEffortLocation();
      if (!mounted) return;
      final res = await ejecutarAccionTarea(
        context,
        ref,
        _id,
        () => ref.read(tasksRepoProvider).finalize(_id, firmaDiferida: true, lat: lat, lng: lng),
      );
      if (res == null || !mounted) return;
      ref.invalidate(taskDetailProvider(_id));
      ref.invalidate(tasksListProvider);

      final enviar = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Pendiente de firma'),
          content: const Text('¿Enviar el enlace de firma por WhatsApp?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sí')),
          ],
        ),
      );
      if (enviar == true && mounted) await enviarEnlaceFirma(context, ref, _id);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) await mostrarErrorAccion(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ─────────────────────────── UI ───────────────────────────

  @override
  Widget build(BuildContext context) {
    // Madre fresca: refleja las ediciones de recursos hechas aquí.
    final t = ref.watch(taskDetailProvider(_id)).valueOrNull ?? widget.task;
    if (t.hasSignature) return _vistaFirmada(t);
    final permisos = ref.watch(sessionControllerProvider).profile?.config.permisos;
    // Solo antes de finalizar: una tarea ya pendiente de firma se firma o se le
    // envía el enlace desde el detalle.
    final puedeDiferir = (permisos?.firmaDiferida ?? false) && t.firma?.faltaFirma != true;

    return Scaffold(
      appBar: AppBar(title: const Text('Firmar servicio')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Resumen del servicio',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          for (final r in t.recursos) _filaResumen(r, editable: t.firma?.faltaFirma != true),
          const SizedBox(height: 8),
          ConceptosSection(task: t, soloLectura: true),
          _otrosPendientes(),
          const Divider(height: 24),
          TextField(
            controller: _obs,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Observaciones del cliente'),
          ),
          const SizedBox(height: 16),
          _quienFirma(),
          const SizedBox(height: 16),
          Row(children: [
            Text(_firmante != null ? 'Firma (obligatoria):' : 'Firma:',
                style: const TextStyle(color: Colors.black54)),
            const Spacer(),
            TextButton.icon(
              onPressed: () => _controller.clear(),
              icon: const Icon(Icons.delete_outline),
              label: const Text('Borrar'),
            ),
          ]),
          const SizedBox(height: 6),
          Container(
            height: 170,
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: Colors.black26),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Signature(controller: _controller, backgroundColor: Colors.white),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : _firmarYFinalizar,
            icon: _busy
                ? const SizedBox(
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.check),
            label: Text(_lote.isEmpty ? 'Confirmar y firmar' : 'Firmar seleccionados (${_lote.length + 1})'),
          ),
          if (puedeDiferir) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _busy ? null : _firmarMasTarde,
              icon: const Icon(Icons.schedule_send),
              label: const Text('Firmar más tarde'),
            ),
          ],
          SizedBox(height: MediaQuery.of(context).padding.bottom + 24),
        ],
      ),
    );
  }

  /// Bloque "Quién firma": firmante elegido (visible durante toda la firma),
  /// lista de firmantes de la obra, o formulario "Otra persona".
  Widget _quienFirma() {
    const titulo = Text('Quién firma', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16));

    // Firmante elegido: se muestra fijo con sus datos.
    final f = _firmante;
    if (f != null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        titulo,
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: const Icon(Icons.person),
            title: Text(f.nombre, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(_datosFirmante(f)),
            trailing: TextButton(
              onPressed: _busy ? null : () => setState(() => _firmante = null),
              child: const Text('Cambiar'),
            ),
          ),
        ),
      ]);
    }

    if (_otraPersona) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          titulo,
          const Spacer(),
          TextButton(
            onPressed: _busy ? null : () => setState(() => _otraPersona = false),
            child: const Text('Elegir de la lista'),
          ),
        ]),
        TextField(
          controller: _nombre,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Nombre de quien firma'),
        ),
        if (_sugerencia != null && _nombre.text.trim().isEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: ActionChip(
              avatar: const Icon(Icons.person_pin_outlined, size: 18),
              label: Text('Contacto de carga: $_sugerencia'),
              onPressed: () => _nombre.text = _sugerencia!,
            ),
          ),
        const SizedBox(height: 12),
        TextField(
          controller: _documento,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(labelText: 'Documento (DNI, NIE o pasaporte)'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _movil,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'Móvil (opcional)',
            helperText: 'Con nombre, documento y firma queda guardado como firmante',
          ),
        ),
      ]);
    }

    // Lista de firmantes de la obra.
    final async = ref.watch(_firmantesProvider(_id));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      titulo,
      const SizedBox(height: 8),
      async.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(12),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => Text(
          e is ApiException && e.sinConexion
              ? 'Sin conexión: no se puede cargar la lista de firmantes.'
              : 'No se pudo cargar la lista de firmantes.',
          style: const TextStyle(color: Colors.black54),
        ),
        data: (lista) => lista.isEmpty
            ? const Text('No hay firmantes guardados para esta obra.',
                style: TextStyle(color: Colors.black54))
            : Card(
                child: Column(children: [
                  for (final x in lista)
                    ListTile(
                      leading: const Icon(Icons.person_outline),
                      title: Text(x.nombre),
                      subtitle: Text(_datosFirmante(x)),
                      onTap: _busy ? null : () => setState(() => _firmante = x),
                    ),
                ]),
              ),
      ),
      const SizedBox(height: 4),
      OutlinedButton.icon(
        onPressed: _busy ? null : () => setState(() => _otraPersona = true),
        icon: const Icon(Icons.person_add_alt),
        label: const Text('Otra persona'),
      ),
    ]);
  }

  /// Bloque "Otros albaranes pendientes de esta obra": casilla por albarán,
  /// desplegable con su resumen. El actual va siempre incluido.
  Widget _otrosPendientes() {
    final async = ref.watch(_pendientesProvider(_id));
    final otros = (async.valueOrNull ?? const <PendienteFirma>[])
        .where((p) => p.id != _id)
        .toList();
    if (otros.isEmpty) return const SizedBox.shrink();
    final todos = otros.every((p) => _lote.contains(p.id));

    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: ExpansionTile(
        initiallyExpanded: true,
        title: Text('Otros albaranes pendientes de esta obra (${otros.length})',
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: const Text('Márcalos para firmarlos a la vez'),
        children: [
          CheckboxListTile(
            dense: true,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('Seleccionar todos'),
            value: todos,
            onChanged: _busy
                ? null
                : (v) => setState(() {
                      if (v == true) {
                        _lote.addAll(otros.map((p) => p.id));
                      } else {
                        _lote.clear();
                      }
                    }),
          ),
          for (final p in otros) _filaPendiente(p),
        ],
      ),
    );
  }

  Widget _filaPendiente(PendienteFirma p) {
    final marcado = _lote.contains(p.id);
    final titulo = [
      if (p.fecha != null) fmtDia(p.fecha!),
      p.albaran ?? 'Albarán ${p.id}',
    ].join(' · ');
    return ExpansionTile(
      leading: Checkbox(
        value: marcado,
        onChanged: _busy
            ? null
            : (v) => setState(() {
                  if (v == true) {
                    _lote.add(p.id);
                  } else {
                    _lote.remove(p.id);
                  }
                }),
      ),
      title: Text(titulo),
      subtitle: p.servicio == null ? null : Text(p.servicio!),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (p.resumenAlbaran != null) ResumenAlbaranView(resumen: p.resumenAlbaran!),
        if (p.recargo != null) _kv('Recargo', p.recargo!),
        if (p.salida != null) _kv('Salida', p.salida!),
        if (p.cargos.isNotEmpty)
          _kv('Complementos', p.cargos.where((c) => !c.anulado).map((c) => c.producto).join(', ')),
      ],
    );
  }

  /// "****567X · 600 111 222"
  static String _datosFirmante(Firmante f) => [
        if ((f.documento ?? '').isNotEmpty) f.documento!,
        if ((f.movil ?? '').isNotEmpty) fmtMovil(f.movil!),
      ].join(' · ');

  Widget _filaResumen(Recurso r, {bool editable = true}) {
    final res = r.resumenAlbaran;
    final editar = editable && r.esMio;
    return InkWell(
      onTap: editar ? () => _editarRecurso(r) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(r.recurso, style: const TextStyle(fontWeight: FontWeight.w600))),
            if (editar) const Icon(Icons.edit, size: 16, color: Colors.black38),
          ]),
          if (res != null)
            ResumenAlbaranView(resumen: res)
          else
            Text(r.cerrada ? 'Cerrado' : 'Sin cerrar', style: const TextStyle(color: Colors.black54)),
        ]),
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 110, child: Text(k, style: const TextStyle(color: Colors.black54))),
          Expanded(child: Text(v)),
        ]),
      );

  Widget _vistaFirmada(TaskDetail t) {
    final w = t.worksheet;
    Widget? img;
    final b64 = w.signatureBase64;
    if (b64 != null && b64.isNotEmpty) {
      try {
        img = Image.memory(base64Decode(b64), height: 160, fit: BoxFit.contain);
      } catch (_) {
        img = null;
      }
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Firma del cliente')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Row(children: [
          Icon(Icons.verified, color: Colors.green.shade700),
          const SizedBox(width: 8),
          const Text('Servicio firmado', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 16),
        if ((w.identificacionSig ?? '').isNotEmpty) _kv('Firmante', w.identificacionSig!),
        if ((w.dniSig ?? '').isNotEmpty) _kv('Documento', w.dniSig!),
        if (w.firmaHora != null) _kv('Fecha/Hora', w.firmaHora!.toLocal().toString().substring(0, 16)),
        if ((w.obsCliente ?? '').isNotEmpty) _kv('Obs. cliente', w.obsCliente!),
        const SizedBox(height: 16),
        const Text('Firma:', style: TextStyle(color: Colors.black54)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: Colors.black26),
            borderRadius: BorderRadius.circular(12),
          ),
          child: img ??
              const Padding(
                  padding: EdgeInsets.all(24), child: Center(child: Text('Firma no disponible.'))),
        ),
      ]),
    );
  }
}

/// E.164 → lectura humana: "+34600111222" → "600 111 222"; otros países tal cual.
String fmtMovil(String e164) {
  final m = RegExp(r'^\+34(\d{3})(\d{3})(\d{3})$').firstMatch(e164);
  return m == null ? e164 : '${m[1]} ${m[2]} ${m[3]}';
}