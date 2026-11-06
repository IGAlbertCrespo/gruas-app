import 'package:flutter/material.dart';

/// v3.12 §4.9 — Observaciones del albarán (`obs_albaran`): las ve el cliente.
/// Longitud máxima (la limita la APP; el servidor no la valida).
const int obsAlbaranMax = 500;

const String _avisoCliente = 'Lo que escribas aparecerá en el albarán y lo verá el cliente.';

/// Diálogo de observaciones del albarán. Devuelve el texto (sin espacios a los
/// lados) o null si el conductor cancela.
///
/// - [obligatoria] (incidencia, §4.3): el botón se deshabilita si está vacío.
/// - Si no es obligatoria, guardar vacío = borrar.
/// - [avisoCliente]: en facturables, recuerda que lo verá el cliente.
Future<String?> pedirObsAlbaran(
  BuildContext context, {
  String? inicial,
  bool obligatoria = false,
  bool avisoCliente = true,
  String titulo = 'Observaciones del albarán',
  String accion = 'Guardar',
  String? hint,
}) =>
    showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ObsAlbaranDialog(
        inicial: inicial,
        obligatoria: obligatoria,
        avisoCliente: avisoCliente,
        titulo: titulo,
        accion: accion,
        hint: hint,
      ),
    );

class _ObsAlbaranDialog extends StatefulWidget {
  const _ObsAlbaranDialog({
    this.inicial,
    required this.obligatoria,
    required this.avisoCliente,
    required this.titulo,
    required this.accion,
    this.hint,
  });

  final String? inicial;
  final bool obligatoria;
  final bool avisoCliente;
  final String titulo;
  final String accion;
  final String? hint;

  @override
  State<_ObsAlbaranDialog> createState() => _ObsAlbaranDialogState();
}

class _ObsAlbaranDialogState extends State<_ObsAlbaranDialog> {
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
      title: Text(widget.titulo),
      content: TextField(
        controller: _ctrl,
        minLines: 3,
        maxLines: 6,
        maxLength: obsAlbaranMax,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
          labelText: 'Observaciones del conductor',
          hintText: widget.hint,
          helperText: widget.avisoCliente ? _avisoCliente : null,
          helperMaxLines: 2,
          border: const OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(onPressed: () => _close(), child: const Text('Cancelar')),
        FilledButton(
          onPressed: widget.obligatoria && texto.isEmpty ? null : () => _close(texto),
          child: Text(widget.accion),
        ),
      ],
    );
  }
}