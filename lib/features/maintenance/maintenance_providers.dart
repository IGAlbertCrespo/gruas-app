import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/providers.dart';
import '../attendance/offline_queue.dart';
import 'maintenance_models.dart';
import 'maintenance_repository.dart';

/// Cola offline propia de averías (clave distinta a la de asistencia).
final maintenanceQueueProvider = Provider<OfflineQueue>((ref) {
  return OfflineQueue(
    const FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
    ),
    key: 'maintenance_offline_queue',
  );
});

final maintenanceRepoProvider = Provider<MaintenanceRepository>((ref) {
  return MaintenanceRepository(ref.watch(apiClientProvider), ref.watch(maintenanceQueueProvider));
});

/// Catálogo cacheado durante la sesión (permisos + vehículos + tipos).
/// NO autoDispose: se reutiliza para gatear la pestaña y para el formulario,
/// sin re-llamar al endpoint. Se refresca con `ref.invalidate`.
final maintenanceCatalogProvider = FutureProvider<MaintenanceCatalog>((ref) {
  return ref.watch(maintenanceRepoProvider).catalog();
});

/// Filtro del histórico: el jefe puede alternar mine/all.
final maintenanceScopeProvider = StateProvider<String>((ref) => 'mine');

final maintenanceHistoryProvider = FutureProvider.autoDispose<
    ({int count, String scope, List<MaintenanceRequestSummary> requests})>((ref) {
  final scope = ref.watch(maintenanceScopeProvider);
  return ref.watch(maintenanceRepoProvider).history(scope: scope);
});