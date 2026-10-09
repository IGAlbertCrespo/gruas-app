import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/accion_tarea.dart';
import '../../../shared/widgets/upgrade_required.dart' show mostrarErrorAccion;
import '../../auth/session_controller.dart';
import '../task_models.dart';
import '../tasks_providers.dart';

/// Conceptos de la tarea MADRE (CONTRATO v3.3 §3 y §5): servicio principal,
/// recargo, salida y complementos (cargos).
///
/// - En las hijas esos bloques llegan a null y la sección no se pinta.
/// - Con [soloLectura] (pantalla de firma) no se ofrece ninguna edición.
/// - Ninguna acción pide confirmación (decisión de negocio): elegir en la
///   lista ya es explícito, y el conductor no debe ver avisos de mínimos.
/// - Sin cantidades: un complemento es siempre una unidad.
class ConceptosSection extends ConsumerStatefulWidget {
  const ConceptosSection({super.key, required this.task, this.soloLectura = false});

  static const titulo = 'Conceptos del servicio';

  final TaskDetail task;
  final bool soloLectura;

  @override
  ConsumerState<ConceptosSection> createState() => _ConceptosSectionState();
}

class _ConceptosSectionState extends ConsumerState<ConceptosSection> {
  /// Acción en curso: 'servicio' | 'recargo' | 'salida' | 'anadir' | 'cargo:<id>'.
  /// Mientras hay una, el resto de ediciones quedan bloqueadas.
  String? _enviando;

  int get _id => widget.task.id;

  void _snack(String texto) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(texto)));

  /// Ejecuta [accion] con spinner en [clave] y el tratamiento común de errores.
  /// Devuelve el resultado, o null si falló o se trató el error.
  Future<T?> _ejecutar<T>(String clave, Future<T> Function() accion) async {
    setState(() => _enviando = clave);
    try {
      return await ejecutarAccionTarea(context, ref, _id, accion);
    } catch (e) {
      if (mounted) await mostrarErrorAccion(context, e);
      return null;
    } finally {
      if (mounted) setState(() => _enviando = null);
    }
  }

  /// Tras un cambio con éxito: refresca detalle y lista.
  void _refrescar() {
    ref.invalidate(taskDetailProvider(_id));
    ref.invalidate(tasksListProvider);
  }

  // ─────────────────────────── Recargo / salida ───────────────────────────

  Future<void> _cambiarSeleccion(String campo, String titulo, Seleccion sel) async {
    final elegido = await _elegir<String>(
      context,
      titulo,
      [for (final o in sel.opciones) (o.value, o.label, o.value == sel.value)],
    );
    if (elegido == null || elegido == sel.value || !mounted) return;
    final repo = ref.read(tasksRepoProvider);
    final res = await _ejecutar(
      campo,
      () => campo == 'recargo' ? repo.setRecargo(_id, elegido) : repo.setSalida(_id, elegido),
    );
    if (res != null) _refrescar();
  }

  // ─────────────────────────── Servicio principal ───────────────────────────

  Future<void> _cambiarServicio() async {
    final repo = ref.read(tasksRepoProvider);
    final candidatos = await _ejecutar('servicio', () => repo.servicios(_id));
    if (candidatos == null || !mounted) return;
    if (candidatos.isEmpty) {
      _snack('No hay otros servicios disponibles en este pedido.');
      return;
    }
    final elegido = await _elegir<int>(
      context,
      'Cambiar servicio',
      [for (final c in candidatos) (c.lineId, c.producto, false)],
    );
    if (elegido == null || !mounted) return;
    // Siempre confirmar: true. El conductor no recibe avisos de mínimos;
    // el cambio queda marcado en la tarea para Tráfico (T2).
    final res = await _ejecutar(
      'servicio',
      () => repo.cambiarServicio(_id, elegido, confirmar: true),
    );
    if (res != null) _refrescar();
  }

  // ─────────────────────────── Complementos ───────────────────────────

  Future<void> _anadirComplemento() async {
    final repo = ref.read(tasksRepoProvider);
    final disponibles = await _ejecutar('anadir', () => repo.complementos(_id));
    if (disponibles == null || !mounted) return;
    if (disponibles.isEmpty) {
      _snack('No hay complementos disponibles.');
      return;
    }
    final elegido = await _elegir<int>(
      context,
      'Añadir complemento',
      [for (final c in disponibles) (c.productId, c.producto, false)],
    );
    if (elegido == null || !mounted) return;
    final res = await _ejecutar('anadir', () => repo.anadirCargo(_id, elegido));
    if (res != null) _refrescar();
  }

  Future<void> _anular(Cargo c) async {
    final res = await _ejecutar(
      'cargo:${c.id}',
      () => ref.read(tasksRepoProvider).anularCargo(_id, c.id),
    );
    if (res != null) _refrescar();
  }

  // ─────────────────────────── UI ───────────────────────────

  bool get _bloqueado => widget.soloLectura || _enviando != null;

  @override
  Widget build(BuildContext context) {
    final t = widget.task;
    final serv = t.servicio;
    final rec = t.recargoSel;
    final sal = t.salidaSel;

    final permisos = ref.watch(sessionControllerProvider).profile?.config.permisos;
    // Las tareas que ve el móvil están informadas (aún editables): basta el permiso.
    final puedeAnadir = !widget.soloLectura && serv != null && (permisos?.anadirCargos ?? false);

    if (serv == null && rec == null && sal == null && t.cargos.isEmpty) {
      return const SizedBox.shrink();
    }

    final color = Theme.of(context).colorScheme.primary;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.receipt_long, size: 18, color: color),
            const SizedBox(width: 8),
            Text(ConceptosSection.titulo,
                style: TextStyle(fontWeight: FontWeight.bold, color: color)),
          ]),
          const SizedBox(height: 8),
          if (serv != null)
            _fila('Servicio', serv.producto,
                onEdit: !_bloqueado && serv.editable ? _cambiarServicio : null,
                cargando: _enviando == 'servicio'),
          if (rec != null)
            _fila('Recargo', rec.label,
                onEdit: !_bloqueado && rec.puedeCambiar
                    ? () => _cambiarSeleccion('recargo', 'Recargo', rec)
                    : null,
                cargando: _enviando == 'recargo'),
          if (sal != null)
            _fila('Salida', sal.label,
                onEdit: !_bloqueado && sal.puedeCambiar
                    ? () => _cambiarSeleccion('salida', 'Salida', sal)
                    : null,
                cargando: _enviando == 'salida'),
          if (t.cargos.isNotEmpty || puedeAnadir) ...[
            const Divider(height: 20),
            const Text('Complementos', style: TextStyle(color: Colors.black54)),
            const SizedBox(height: 4),
            for (final c in t.cargos) _filaCargo(c),
            if (t.cargos.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: Text('Sin complementos', style: TextStyle(color: Colors.black38)),
              ),
            if (puedeAnadir)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _enviando == null ? _anadirComplemento : null,
                  icon: _enviando == 'anadir'
                      ? const SizedBox(
                          width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.add),
                  label: const Text('Añadir complemento'),
                ),
              ),
          ],
        ]),
      ),
    );
  }

  Widget _fila(String k, String v, {VoidCallback? onEdit, bool cargando = false}) => InkWell(
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            SizedBox(width: 120, child: Text(k, style: const TextStyle(color: Colors.black54))),
            Expanded(child: Text(v)),
            if (cargando)
              const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
            else if (onEdit != null)
              const Icon(Icons.edit, size: 18, color: Colors.black38),
          ]),
        ),
      );

  Widget _filaCargo(Cargo c) {
    final cargando = _enviando == 'cargo:${c.id}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        Expanded(
          child: Text(
            c.producto,
            style: c.anulado
                ? const TextStyle(color: Colors.black38, decoration: TextDecoration.lineThrough)
                : null,
          ),
        ),
        if (c.anulado) _chip('Anulado', Colors.grey) else if (c.deApp) _chip('APP', Colors.blue),
        if (cargando)
          const Padding(
            padding: EdgeInsets.all(12),
            child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else if (!widget.soloLectura && c.anulable && !c.anulado)
          IconButton(
            tooltip: 'Anular',
            onPressed: _enviando == null ? () => _anular(c) : null,
            icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent),
          ),
      ]),
    );
  }

  Widget _chip(String texto, MaterialColor color) => Container(
        margin: const EdgeInsets.only(left: 6),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: color.shade50, borderRadius: BorderRadius.circular(6)),
        child: Text(texto, style: TextStyle(color: color.shade700, fontSize: 11)),
      );
}

/// Bottom sheet de selección simple. [opciones]: (valor, etiqueta, actual).
/// Devuelve el valor elegido o null si se cierra sin elegir.
Future<T?> _elegir<T>(BuildContext context, String titulo, List<(T, String, bool)> opciones) =>
    showModalBottomSheet<T>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(titulo,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final (valor, etiqueta, actual) in opciones)
                      ListTile(
                        leading: Icon(
                          actual ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                          color: actual ? Theme.of(ctx).colorScheme.primary : null,
                        ),
                        title: Text(etiqueta),
                        onTap: () => Navigator.pop(ctx, valor),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );