import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../tasks/tasks_providers.dart';
import '../attendance_models.dart';
import '../attendance_repository.dart';
import '../../../shared/pausa_dialog.dart';
import '../../../shared/widgets/brand_logo.dart';


/// Resumen de la última jornada cerrada (se muestra hasta el siguiente fichaje).
class _JourneySummary {
  final DateTime entrada;
  final DateTime salida;
  final Duration bruta;
  final Duration pausas;
  final Duration efectivas;
  final String? obs;
  const _JourneySummary(this.entrada, this.salida, this.bruta, this.pausas, this.efectivas, {this.obs});
}

Duration _fromHours(double h) => Duration(milliseconds: (h * 3600000).round());

/// Umbral para ignorar ruido de redondeo en la reconciliación de pausas (~3 min).
const double _eps = 0.05;

String _hms(Duration d) {
  if (d.isNegative) d = Duration.zero;
  final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
  return '${h}h ${m.toString().padLeft(2, '0')}m ${s.toString().padLeft(2, '0')}s';
}

String _hm(DateTime dt) {
  final l = dt.toLocal();
  return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
}

String _dmy(DateTime dt) {
  final l = dt.toLocal();
  return '${l.day.toString().padLeft(2, '0')}/${l.month.toString().padLeft(2, '0')}/${(l.year % 100).toString().padLeft(2, '0')}';
}

class AttendanceScreen extends ConsumerStatefulWidget {
  const AttendanceScreen({super.key});
  @override
  ConsumerState<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends ConsumerState<AttendanceScreen> with WidgetsBindingObserver {
  bool _busy = false;
  DateTime? _breakStart; // inicio de la pausa en curso (lo conoce la app)
  _JourneySummary? _lastSummary;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _hydrateBreakStart();
  }

  /// Recupera el inicio de la pausa en curso del libro de jornada (persistido),
  /// para que el contador en vivo no se reinicie al cambiar de pestaña o tras
  /// un kill de la app.
  Future<void> _hydrateBreakStart() async {
    final inicio = await ref.read(journeyLedgerProvider).breakStart();
    if (mounted && inicio != null) setState(() => _breakStart = inicio);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Al volver a primer plano, recalculamos (refrescamos el estado).
    if (state == AppLifecycleState.resumed && mounted) {
      ref.invalidate(attendanceStateProvider);
      _hydrateBreakStart();
      setState(() {});
    }
  }

  String _uuid() {
    final r = Random();
    return List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  Future<(double?, double?)> _location() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return (null, null);
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        return (null, null);
      }
      final pos = await Geolocator.getCurrentPosition().timeout(const Duration(seconds: 5));
      return (pos.latitude, pos.longitude);
    } catch (_) {
      return (null, null);
    }
  }

  Future<void> _run(Future<void> Function(AttendanceRepository repo) action) async {
    setState(() => _busy = true);
    try {
      await action(ref.read(attendanceRepoProvider));
      ref.invalidate(attendanceStateProvider);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  ({Duration bruta, Duration pausas, Duration efectivas}) _compute(AttendanceState st) {
    if (!st.hasOpen || st.checkIn == null) {
      return (bruta: Duration.zero, pausas: Duration.zero, efectivas: Duration.zero);
    }
    final now = DateTime.now();
    final bruta = now.difference(st.checkIn!);
    final cerradas = _fromHours(st.totalBreakTime);
    final enCurso = (st.isOnBreak && _breakStart != null) ? now.difference(_breakStart!) : Duration.zero;
    final pausas = cerradas + enCurso;
    return (bruta: bruta, pausas: pausas, efectivas: bruta - pausas);
  }

  Future<void> _checkIn() async {
    setState(() {
      _lastSummary = null;
      _breakStart = null;
    });
    await _run((repo) async {
      final (lat, lng) = await _location();
      await repo.checkIn(_uuid(), lat: lat, lng: lng);
      await ref.read(journeyLedgerProvider).clear(); // jornada nueva: libro limpio
    });
  }

  Future<void> _checkOut(AttendanceState st) async {
    if (st.checkIn == null) return;
    final ledger = ref.read(journeyLedgerProvider);
    final salida = DateTime.now();
    final inicioJornada = st.checkIn!.toLocal();

    // --- Reconciliación de la pausa de comida (100% local, sin red) ---
    final declaradas = await ledger.declaredTotal();
    final fichadas = await ledger.clockedTotal();
    double forzadaHoras = 0;
    DateTime? inicioForzada;

    if (!mounted) return;
    if (declaradas <= _eps && fichadas <= _eps) {
      // Ni imputada al cliente ni fichada a mano: preguntar si comió y cuánto.
      forzadaHoras = await pickPausa(context) ?? 0.0; // "Ninguna" => no comió
    } else {
      final hueco = declaradas - fichadas;
      if (hueco > _eps) {
        final inicio = _proponer1400(inicioJornada, salida, hueco);
        if (inicio == null) {
          _avisoNoCabe();
        } else {
          if (!mounted) return;
          if (await confirmIncorporarPausa(context, hueco, inicio)) {
            forzadaHoras = hueco;
            inicioForzada = inicio;
          }
        }
      }
      // hueco <= 0 => ya estaba fichado a mano: no se pregunta ("salvo manual").
    }

    // Caso 0/0 con "sí comió": proponer también las 14:00.
    if (forzadaHoras > _eps && inicioForzada == null) {
      inicioForzada = _proponer1400(inicioJornada, salida, forzadaHoras);
      if (inicioForzada == null) {
        _avisoNoCabe();
        forzadaHoras = 0;
      }
    }

    // --- Observaciones de jornada + confirmación final ---
    if (!mounted) return;
    final obs = await pedirObservaciones(context);
    if (obs == null) return; // canceló: no se cierra nada (ni pausa forzada).

    setState(() => _busy = true);
    try {
      final (lat, lng) = await _location();
      // 1) Insertar la pausa forzada ANTES del check-out (asistencia abierta).
      if (forzadaHoras > _eps && inicioForzada != null) {
        await ref.read(attendanceRepoProvider).breakForced(
              _uuid(),
              start: inicioForzada,
              durationHours: forzadaHoras,
              attendanceId: st.attendanceId,
            );
      }
      // 2) Check-out (con observaciones).
      await ref.read(attendanceRepoProvider).checkOut(
            _uuid(),
            attendanceId: st.attendanceId,
            lat: lat,
            lng: lng,
            observaciones: obs.isEmpty ? null : obs,
          );

      // 3) Resumen, sumando la pausa forzada (st no la refleja aún).
      final c = _compute(st);
      final pausas = c.pausas + (forzadaHoras > _eps ? _fromHours(forzadaHoras) : Duration.zero);
      final summary = _JourneySummary(
        inicioJornada, salida, c.bruta, pausas, c.bruta - pausas,
        obs: obs.isEmpty ? null : obs,
      );

      await ledger.clear();
      _breakStart = null;
      _lastSummary = summary;
      ref.invalidate(attendanceStateProvider);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _avisoNoCabe() {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('La pausa no cabe en la jornada; revísala en oficina.')));
    }
  }

  /// Propone las 14:00 (local) como inicio de la pausa forzada, ajustando para
  /// que quepa dentro de [entrada, salida]. Devuelve null si la jornada es más
  /// corta que la pausa. El solape con otras pausas lo arbitra el backend.
  DateTime? _proponer1400(DateTime inicio, DateTime salida, double horas) {
    final dur = _fromHours(horas);
    if (salida.difference(inicio) < dur) return null;
    var start = DateTime(salida.year, salida.month, salida.day, 14, 0);
    final maxStart = salida.subtract(dur);
    if (start.isBefore(inicio)) start = inicio;
    if (start.isAfter(maxStart)) start = maxStart;
    return start;
  }

  @override
  Widget build(BuildContext context) {
    final stateAsync = ref.watch(attendanceStateProvider);
    return Stack(
      children: [
        // Marca de agua tenue de fondo (no intercepta toques).
        Positioned.fill(
          child: IgnorePointer(
            child: Center(child: BrandLogo(size: 260, opacity: 0.06)),
          ),
        ),
        RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(attendanceStateProvider);
          },
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              stateAsync.when(
                loading: () => const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),
                error: (e, _) => _ErrorCard(message: '$e', onRetry: () => ref.invalidate(attendanceStateProvider)),
                data: (st) => _StatusCard(state: st, totals: _compute(st)),
              ),
              if (_lastSummary != null) ...[
                const SizedBox(height: 8),
                _SummaryCard(summary: _lastSummary!),
              ],
              const SizedBox(height: 8),
              stateAsync.maybeWhen(data: (st) => _actions(st), orElse: () => const SizedBox.shrink()),
              // Logo nítido bajo el detalle.
              const SizedBox(height: 32),
              const Center(child: BrandLogo(size: 72)),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ],
    );
  }

  Widget _actions(AttendanceState st) {
    if (!st.hasOpen) {
      return FilledButton.icon(
        onPressed: _busy ? null : _checkIn,
        icon: const Icon(Icons.login),
        label: const Text('Fichar entrada'),
      );
    }
    return Column(
      children: [
        if (!st.isOnBreak)
          _BreakStartButton(busy: _busy, onStart: (typeId) {
            final ahora = DateTime.now();
            _breakStart = ahora;
            _run((repo) async {
              await ref.read(journeyLedgerProvider).setBreakStart(ahora);
              await repo.breakStart(_uuid(), attendanceId: st.attendanceId, breakTypeId: typeId);
            });
          })
        else
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Colors.orange.shade700),
            onPressed: _busy ? null : () {
              _breakStart = null;
              _run((repo) async {
                // Pausa fichada => acumula su duración (restará del hueco al cerrar).
                final ledger = ref.read(journeyLedgerProvider);
                final inicio = await ledger.breakStart();
                if (inicio != null) {
                  final dur = DateTime.now().difference(inicio).inMilliseconds / 3600000.0;
                  await ledger.addClocked(dur);
                }
                await ledger.clearBreakStart();
                await repo.breakEnd(_uuid(), breakId: st.currentBreakId, attendanceId: st.attendanceId);
              });
            },
            icon: const Icon(Icons.play_arrow),
            label: Text('Finalizar pausa (${st.currentBreakType ?? ''})'),
          ),
        const SizedBox(height: 10),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
          onPressed: (_busy || st.isOnBreak) ? null : () => _checkOut(st),
          icon: const Icon(Icons.logout),
          label: const Text('Fichar salida'),
        ),
        if (st.isOnBreak)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('Finaliza la pausa antes de fichar salida.', style: TextStyle(color: Colors.black54)),
          ),
      ],
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.state, required this.totals});
  final AttendanceState state;
  final ({Duration bruta, Duration pausas, Duration efectivas}) totals;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (label, color, icon) = !state.hasOpen
        ? ('Sin fichar', Colors.grey, Icons.timer_off)
        : state.isOnBreak
            ? ('En pausa', Colors.orange.shade700, Icons.pause_circle)
            : ('Trabajando', scheme.primary, Icons.work);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(children: [
              Icon(icon, color: color, size: 32),
              const SizedBox(width: 12),
              Text(label, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
            ]),
            if (state.hasOpen) ...[
              const Divider(height: 28),
              _row('Entrada', state.checkIn != null ? _hm(state.checkIn!) : '—'),
              _row('Jornada', _hms(totals.bruta)),
              _row('Pausas', _hms(totals.pausas)),
              _row('Efectivas', _hms(totals.efectivas)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(k, style: const TextStyle(color: Colors.black54)),
          Text(v, style: const TextStyle(fontWeight: FontWeight.w600)),
        ]),
      );
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary});
  final _JourneySummary summary;
  @override
  Widget build(BuildContext context) => Card(
        color: Colors.green.shade50,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.check_circle, color: Colors.green.shade700),
                const SizedBox(width: 8),
                Text('Última jornada  (${_dmy(summary.entrada)})',
                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green.shade800)),
              ]),
              const Divider(height: 24),
              _row('Entrada', _hm(summary.entrada)),
              _row('Salida', _hm(summary.salida)),
              _row('Jornada', _hms(summary.bruta)),
              _row('Pausas', _hms(summary.pausas)),
              _row('Efectivas', _hms(summary.efectivas)),
              if (summary.obs != null && summary.obs!.isNotEmpty) ...[
                const Divider(height: 24),
                const Text('Observaciones',
                    style: TextStyle(color: Colors.black54)),
                const SizedBox(height: 4),
                Text(summary.obs!,
                    style: const TextStyle(fontWeight: FontWeight.w500)),
              ],
            ],
          ),
        ),
      );

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(k, style: const TextStyle(color: Colors.black54)),
          Text(v, style: const TextStyle(fontWeight: FontWeight.w600)),
        ]),
      );
}

class _BreakStartButton extends ConsumerWidget {
  const _BreakStartButton({required this.busy, required this.onStart});
  final bool busy;
  final void Function(int? typeId) onStart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final types = ref.watch(breakTypesProvider);
    return FilledButton.icon(
      style: FilledButton.styleFrom(backgroundColor: Colors.orange.shade700),
      onPressed: busy
          ? null
          : () async {
              final list = types.asData?.value ?? const [];
              if (list.length <= 1) {
                onStart(list.isEmpty ? null : list.first.id);
                return;
              }
              final picked = await showModalBottomSheet<BreakType>(
                context: context,
                builder: (_) => SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final t in list)
                        ListTile(title: Text(t.name), onTap: () => Navigator.pop(context, t)),
                    ],
                  ),
                ),
              );
              if (picked != null) onStart(picked.id);
            },
      icon: const Icon(Icons.pause),
      label: const Text('Iniciar pausa'),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 32),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            TextButton(onPressed: onRetry, child: const Text('Reintentar')),
          ]),
        ),
      );
}