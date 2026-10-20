import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../shared/accion_tarea.dart';
import '../../../shared/widgets/upgrade_required.dart' show mostrarErrorAccion;
import '../task_models.dart';
import '../tasks_providers.dart';
import 'signature_screen.dart' show fmtMovil;

/// Envío del enlace de firma por WhatsApp (CONTRATO §6.6) para UNA tarea madre
/// pendiente de firma. Lo usan "Firmar más tarde" y "Enviar enlace de firma".
///
/// 1. Destinatario: firmante de la obra (si no tiene móvil se pide) u "Otra
///    persona" (móvil obligatorio; con documento se da de alta como firmante).
/// 2. POST /firma/solicitudes [ONLINE].
/// 3. Abre WhatsApp con el mensaje del servidor. Si no se puede abrir, ofrece
///    copiar el enlace.
///
/// Devuelve true si se creó la solicitud.
Future<bool> enviarEnlaceFirma(BuildContext context, WidgetRef ref, int taskId) async {
  final dest = await Navigator.push<_Destinatario>(
    context,
    MaterialPageRoute(builder: (_) => _DestinatarioScreen(taskId: taskId)),
  );
  if (dest == null || !context.mounted) return false;

  final SolicitudCreada? sol;
  try {
    sol = await ejecutarAccionTarea(
      context,
      ref,
      taskId,
      () => ref.read(tasksRepoProvider).crearSolicitudFirma(
            [taskId],
            firmanteId: dest.firmanteId,
            movil: dest.movil,
          ),
    );
  } catch (e) {
    if (context.mounted) await mostrarErrorAccion(context, e);
    return false;
  }
  if (sol == null || !context.mounted) return false;

  ref.invalidate(taskDetailProvider(taskId));
  ref.invalidate(tasksListProvider);

  final numero = numeroWhatsApp(dest.movil);
  final uri = Uri.parse(
      'https://wa.me/$numero?text=${Uri.encodeComponent(sol.mensaje ?? sol.url)}');
  var abierto = false;
  try {
    // Sin canLaunchUrl: en Android 11+ exigiría <queries> en el manifest.
    abierto = await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    abierto = false;
  }
  if (!abierto && context.mounted) await _copiarEnlace(context, sol.url);
  return true;
}

/// Móvil → número para wa.me: solo dígitos con prefijo de país, sin '+'.
/// E.164 ("+34600111222") → "34600111222". "0034…" → "34…". 9 dígitos → "34…".
String numeroWhatsApp(String movil) {
  var d = movil.replaceAll(RegExp(r'\D'), '');
  if (d.startsWith('00')) d = d.substring(2);
  if (!movil.trim().startsWith('+') && d.length == 9) d = '34$d';
  return d;
}

Future<void> _copiarEnlace(BuildContext context, String url) => showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('No se pudo abrir WhatsApp'),
        content: SelectableText('El enlace de firma se ha creado:\n\n$url'),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: url));
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Copiar enlace'),
          ),
          FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar')),
        ],
      ),
    );

class _Destinatario {
  final int? firmanteId;
  final String movil;
  const _Destinatario(this.firmanteId, this.movil);
}

final _firmantesEnlaceProvider =
    FutureProvider.autoDispose.family<List<Firmante>, int>((ref, taskId) {
  return ref.read(tasksRepoProvider).firmantes(taskId);
});

class _DestinatarioScreen extends ConsumerStatefulWidget {
  const _DestinatarioScreen({required this.taskId});
  final int taskId;
  @override
  ConsumerState<_DestinatarioScreen> createState() => _DestinatarioScreenState();
}

class _DestinatarioScreenState extends ConsumerState<_DestinatarioScreen> {
  final _nombre = TextEditingController();
  final _documento = TextEditingController();
  final _movil = TextEditingController();
  bool _otraPersona = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _movil.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nombre.dispose();
    _documento.dispose();
    _movil.dispose();
    super.dispose();
  }

  static bool _movilValido(String s) => s.replaceAll(RegExp(r'\D'), '').length >= 9;

  /// Firmante de la lista: con móvil se usa; sin móvil se pide (el servidor lo
  /// guarda en su ficha al crear la solicitud).
  Future<void> _elegir(Firmante f) async {
    var movil = f.movil;
    if (movil == null || movil.isEmpty) {
      movil = await _pedirMovil(f.nombre);
      if (movil == null || !mounted) return;
    }
    Navigator.pop(context, _Destinatario(f.id, movil));
  }

  Future<String?> _pedirMovil(String nombre) {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text('Móvil de $nombre'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: TextInputType.phone,
            onChanged: (_) => setD(() {}),
            decoration: const InputDecoration(labelText: 'Móvil', hintText: '600 111 222'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            FilledButton(
              onPressed: _movilValido(ctrl.text) ? () => Navigator.pop(ctx, ctrl.text.trim()) : null,
              child: const Text('Continuar'),
            ),
          ],
        ),
      ),
    );
  }

  /// Otra persona: con documento → alta/vinculación como firmante (con su
  /// móvil); sin documento → el enlace sale solo con el móvil.
  Future<void> _continuarOtra() async {
    final movil = _movil.text.trim();
    final doc = _documento.text.toUpperCase().replaceAll(RegExp(r'[\s\-]'), '');
    if (doc.isEmpty || _nombre.text.trim().isEmpty) {
      Navigator.pop(context, _Destinatario(null, movil));
      return;
    }
    setState(() => _busy = true);
    try {
      final f = await ejecutarAccionTarea(
        context,
        ref,
        widget.taskId,
        () => ref.read(tasksRepoProvider).crearFirmante(
              widget.taskId,
              nombre: _nombre.text.trim(),
              documento: doc,
              movil: movil,
            ),
      );
      if (f != null && mounted) Navigator.pop(context, _Destinatario(f.id, f.movil ?? movil));
    } catch (e) {
      if (mounted) await mostrarErrorAccion(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Enviar enlace de firma')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: _otraPersona ? _formOtra() : _lista(),
      ),
    );
  }

  List<Widget> _lista() {
    final async = ref.watch(_firmantesEnlaceProvider(widget.taskId));
    return [
      const Text('¿A quién se lo envías?',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      const SizedBox(height: 8),
      async.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(12),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => const Text('No se pudo cargar la lista de firmantes.',
            style: TextStyle(color: Colors.black54)),
        data: (lista) => lista.isEmpty
            ? const Text('No hay firmantes guardados para esta obra.',
                style: TextStyle(color: Colors.black54))
            : Card(
                child: Column(children: [
                  for (final f in lista)
                    ListTile(
                      leading: const Icon(Icons.person_outline),
                      title: Text(f.nombre),
                      subtitle: Text((f.movil ?? '').isNotEmpty
                          ? fmtMovil(f.movil!)
                          : 'Sin móvil (se pedirá)'),
                      onTap: () => _elegir(f),
                    ),
                ]),
              ),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: () => setState(() => _otraPersona = true),
        icon: const Icon(Icons.person_add_alt),
        label: const Text('Otra persona'),
      ),
    ];
  }

  List<Widget> _formOtra() => [
        Row(children: [
          const Text('Otra persona', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const Spacer(),
          TextButton(
            onPressed: _busy ? null : () => setState(() => _otraPersona = false),
            child: const Text('Elegir de la lista'),
          ),
        ]),
        TextField(
          controller: _movil,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(labelText: 'Móvil (obligatorio)'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _nombre,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Nombre (opcional)'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _documento,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            labelText: 'Documento (opcional)',
            helperText: 'Con nombre y documento queda guardado como firmante de la obra',
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _busy || !_movilValido(_movil.text) ? null : _continuarOtra,
          icon: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.send),
          label: const Text('Continuar'),
        ),
      ];
}