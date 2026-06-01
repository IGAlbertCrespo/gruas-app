import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/providers.dart';
import '../attendance/attendance_models.dart';
import '../attendance/attendance_repository.dart';
import '../attendance/offline_queue.dart';
import 'task_models.dart';
import 'tasks_repository.dart';

// --- Asistencia ---
final offlineQueueProvider = Provider<OfflineQueue>((ref) {
  return OfflineQueue(const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  ));
});

final attendanceRepoProvider = Provider<AttendanceRepository>((ref) {
  return AttendanceRepository(ref.watch(apiClientProvider), ref.watch(offlineQueueProvider));
});

final attendanceStateProvider = FutureProvider.autoDispose<AttendanceState>((ref) {
  return ref.watch(attendanceRepoProvider).currentState();
});

final breakTypesProvider = FutureProvider.autoDispose<List<BreakType>>((ref) {
  return ref.watch(attendanceRepoProvider).breakTypes();
});

// --- Tareas ---
final tasksRepoProvider = Provider<TasksRepository>((ref) => TasksRepository(ref.watch(apiClientProvider)));

/// Filtro de listado: el jefe puede alternar mine/all.
final taskScopeProvider = StateProvider<String>((ref) => 'mine');

final tasksListProvider =
    FutureProvider.autoDispose<({int count, String scope, List<TaskSummary> tasks})>((ref) {
  final scope = ref.watch(taskScopeProvider);
  return ref.watch(tasksRepoProvider).list(scope: scope);
});

final taskDetailProvider =
    FutureProvider.autoDispose.family<TaskDetail, int>((ref, id) {
  return ref.watch(tasksRepoProvider).detail(id);
});
