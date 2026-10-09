import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/session_controller.dart';
import '../../../shared/widgets/brand_logo.dart';
import '../maintenance_models.dart';
import '../maintenance_providers.dart';
import 'maintenance_report_screen.dart';

/// Pestaña "Averías": histórico del chófer + acceso al parte de avería.
/// Es una página dentro de HomeShell (sin Scaffold propio), igual que Asistencia.
class MaintenanceScreen extends ConsumerStatefulWidget {
  const MaintenanceScreen({super.key});
  @override
  ConsumerState<MaintenanceScreen> createState() => _MaintenanceScreenState();
}

class _MaintenanceScreenState extends ConsumerState<MaintenanceScreen> {
  @override
  void initState() {
    super.initState();
    // Best-effort: subir partes que quedaron en la cola offline.
    Future.microtask(_trySync);
  }

  Future<void> _trySync() async {
    try {
      final n = await ref.read(maintenanceRepoProvider).syncPending();
      if (n > 0 && mounted) {
        ref.invalidate(maintenanceHistoryProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Se enviaron $n parte(s) pendiente(s).')),
        );
      }
    } catch (_) {
      // Sin red u otro fallo: se reintentará la próxima vez.
    }
  }

  Future<void> _openReport() async {
    final cat = ref.read(maintenanceCatalogProvider).valueOrNull;
    if (cat == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cargando catálogo, inténtalo de nuevo en un momento.')),
      );
      ref.invalidate(maintenanceCatalogProvider);
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => MaintenanceReportScreen(catalog: cat)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isManager = ref.watch(sessionControllerProvider).profile?.isManager ?? false;
    final scope = ref.watch(maintenanceScopeProvider);
    final histAsync = ref.watch(maintenanceHistoryProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: FilledButton.icon(
            onPressed: _openReport,
            icon: const Icon(Icons.report_problem),
            label: const Text('Reportar avería'),
          ),
        ),
        if (isManager)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'mine', label: Text('Mías')),
                ButtonSegment(value: 'all', label: Text('Todas')),
              ],
              selected: {scope},
              onSelectionChanged: (s) => ref.read(maintenanceScopeProvider.notifier).state = s.first,
            ),
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async => ref.invalidate(maintenanceHistoryProvider),
            child: histAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => ListView(children: [
                Padding(padding: const EdgeInsets.all(24), child: Center(child: Text('$e'))),
              ]),
              data: (res) {
                if (res.requests.isEmpty) {
                  return ListView(children: [
                    const SizedBox(height: 48),
                    const Center(child: BrandLogo(size: 64, opacity: 0.5)),
                    const SizedBox(height: 12),
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: Text('No hay averías reportadas.')),
                    ),
                  ]);
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: res.requests.length,
                  itemBuilder: (_, i) => _AveriaCard(item: res.requests[i]),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _AveriaCard extends StatelessWidget {
  const _AveriaCard({required this.item});
  final MaintenanceRequestSummary item;

  @override
  Widget build(BuildContext context) {
    final titulo = [
      if (item.vehiculo != null) item.vehiculo,
      if (item.matricula != null && item.matricula!.isNotEmpty) item.matricula,
    ].whereType<String>().join(' · ');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    titulo.isEmpty ? (item.name ?? 'Avería') : titulo,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                _StageChip(etapa: item.etapa, cerrada: item.cerrada),
              ],
            ),
            if (item.tipo != null) ...[
              const SizedBox(height: 4),
              Text(item.tipo!, style: TextStyle(color: Colors.grey.shade700)),
            ],
            if (item.descripcion.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(item.descripcion),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                if (item.fecha != null) _meta(Icons.event, item.fecha!),
                if (item.km != null) _meta(Icons.speed, '${item.km} km'),
                if (item.horasGrua != null)
                  _meta(Icons.timer_outlined,
                      '${item.horasGrua! % 1 == 0 ? item.horasGrua!.toInt() : item.horasGrua} h grúa'),
                if (item.precisaInmovilizacion)
                  _meta(Icons.block, 'Inmoviliza', color: Colors.red.shade700),
                if (item.offlineUuid != null && item.id == null)
                  _meta(Icons.cloud_upload, 'Pendiente de envío', color: Colors.orange.shade800),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _meta(IconData icon, String text, {Color? color}) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color ?? Colors.grey.shade600),
          const SizedBox(width: 4),
          Text(text, style: TextStyle(fontSize: 13, color: color ?? Colors.grey.shade700)),
        ],
      );
}

class _StageChip extends StatelessWidget {
  const _StageChip({required this.etapa, required this.cerrada});
  final String? etapa;
  final bool cerrada;

  @override
  Widget build(BuildContext context) {
    final color = cerrada ? Colors.green.shade700 : Colors.blue.shade700;
    final label = etapa ?? (cerrada ? 'Cerrada' : 'Abierta');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}