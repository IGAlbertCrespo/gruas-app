import '../../core/network/api_client.dart';
import 'task_models.dart';

class TasksRepository {
  TasksRepository(this.api);
  final ApiClient api;

  /// scope: 'mine' (conductor) o 'all' (solo jefe; el backend lo valida).
  Future<({int count, String scope, List<TaskSummary> tasks})> list({
    String scope = 'mine',
    String? stage,
    int limit = 80,
    int offset = 0,
  }) async {
    final res = await api.getJson('/tasks', query: {
      'scope': scope,
      if (stage != null) 'stage': stage,
      'limit': limit,
      'offset': offset,
    });
    final list = (res['tasks'] ?? []) as List;
    return (
      count: (res['count'] ?? 0) as int,
      scope: res['scope']?.toString() ?? scope,
      tasks: list.map((e) => TaskSummary.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }

  Future<TaskDetail> detail(int id) async {
    final res = await api.getJson('/tasks/$id');
    return TaskDetail.fromJson(res);
  }

  Future<TaskDetail> updateWorksheet(int id, Map<String, dynamic> fields) async {
    final res = await api.postJson('/tasks/$id/worksheet', data: fields);
    return TaskDetail.fromJson(res);
  }

  /// signatureBase64: PNG en base64 (sin cabecera data:).
  Future<void> saveSignature(int id, String signatureBase64, {String? signerName}) async {
    await api.postJson('/tasks/$id/signature', data: {
      'signature': signatureBase64,
      if (signerName != null) 'signer_name': signerName,
    });
  }

  /// target: planificado | revisado | finalizada | cancelado | no_facturable
  Future<TaskStage> changeStage(int id, String target) async {
    final res = await api.postJson('/tasks/$id/stage', data: {'target': target});
    return TaskStage.fromJson((res['stage'] ?? {}) as Map<String, dynamic>);
  }
}
