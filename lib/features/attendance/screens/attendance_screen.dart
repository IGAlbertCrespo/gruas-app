import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../tasks/tasks_providers.dart';
import '../attendance_models.dart';
import '../attendance_repository.dart';
import 'dart:math';

class AttendanceScreen extends ConsumerStatefulWidget {
  const AttendanceScreen({super.key});
  @override
  ConsumerState<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends ConsumerState<AttendanceScreen> {
  bool _busy = false;

  String _uuid() {
    final r = Random();
    return List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  /// Ubicación "best-effort": si no hay permiso, servicio o tarda demasiado,
  /// devuelve (null, null) y el fichaje continúa igualmente sin coordenadas.
  Future<(double?, double?)> _location() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return (null, null);
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        return (null, null);
      }
      final pos = await Geolocator.getCurrentPosition()
          .timeout(const Duration(seconds: 5));
      return (pos.latitude, pos.longitude);
    } catch (_) {
      // Sin GPS, timeout o cualquier error: fichamos sin ubicación.
      return (null, null);
    }
  }

  Future<void> _run(Future<void> Function(AttendanceRepository repo) action) async {
    setState(() => _busy = true);
    try {
      await action(ref.read(attendanceRepoProvider));
      ref.invalidate(attendanceStateProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final stateAsync = ref.watch(attendanceStateProvider);

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(attendanceStateProvider),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          stateAsync.when(
            loading: () => const Padding(
                padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),
            error: (e, _) => _ErrorCard(message: '$e', onRetry: () => ref.invalidate(attendanceStateProvider)),
            data: (st) => _StatusCard(state: st),
          ),
          const SizedBox(height: 8),
          stateAsync.maybeWhen(
            data: (st) => _actions(st),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _actions(AttendanceState st) {
    if (!st.hasOpen) {
      return FilledButton.icon(
        onPressed: _busy ? null : () => _run((repo) async {
          final (lat, lng) = await _location();
          await repo.checkIn(_uuid(), lat: lat, lng: lng);
        }),
        icon: const Icon(Icons.login),
        label: const Text('Fichar entrada'),
      );
    }
    return Column(
      children: [
        if (!st.isOnBreak)
          _BreakStartButton(busy: _busy, onStart: (typeId) => _run((repo) async {
            await repo.breakStart(_uuid(), attendanceId: st.attendanceId, breakTypeId: typeId);
          }))
        else
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Colors.orange.shade700),
            onPressed: _busy ? null : () => _run((repo) async {
              await repo.breakEnd(_uuid(), breakId: st.currentBreakId, attendanceId: st.attendanceId);
            }),
            icon: const Icon(Icons.play_arrow),
            label: Text('Finalizar pausa (${st.currentBreakType ?? ''})'),
          ),
        const SizedBox(height: 10),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
          onPressed: (_busy || st.isOnBreak) ? null : () => _run((repo) async {
            final (lat, lng) = await _location();
            await repo.checkOut(_uuid(), attendanceId: st.attendanceId, lat: lat, lng: lng);
          }),
          icon: const Icon(Icons.logout),
          label: const Text('Fichar salida'),
        ),
        if (st.isOnBreak)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('Finaliza la pausa antes de fichar salida.',
                style: TextStyle(color: Colors.black54)),
          ),
      ],
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.state});
  final AttendanceState state;
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
              _row('Entrada', state.checkIn?.toLocal().toString().substring(11, 16) ?? '—'),
              _row('Horas trabajadas', state.workedHours.toStringAsFixed(2)),
              _row('Pausas', state.totalBreakTime.toStringAsFixed(2)),
              _row('Efectivas', state.effectiveWorkedHours.toStringAsFixed(2)),
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
