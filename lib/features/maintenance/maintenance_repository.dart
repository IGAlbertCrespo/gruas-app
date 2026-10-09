import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../shared/offline_id.dart';
import '../attendance/offline_queue.dart';
import 'maintenance_models.dart';

String _two(int n) => n.toString().padLeft(2, '0');

/// Fecha de hoy (local) en 'YYYY-MM-DD'. La detección es una fecha, no instante.
String _today() {
  final d = DateTime.now();
  return '${d.year.toString().padLeft(4, '0')}-${_two(d.month)}-${_two(d.day)}';
}

/// Marca temporal local para la cola (solo metadato; el /sync no la envía).
String _nowUtc() {
  final u = DateTime.now().toUtc();
  return '${u.year.toString().padLeft(4, '0')}-${_two(u.month)}-${_two(u.day)} '
      '${_two(u.hour)}:${_two(u.minute)}:${_two(u.second)}';
}

/// Foto adjunta a un alta (solo online).
class MaintenancePhoto {
  final String filename;
  final String dataB64;
  const MaintenancePhoto({required this.filename, required this.dataB64});

  Map<String, dynamic> toJson() => {'filename': filename, 'data': dataB64};
}

/// Averías de taller. Online -> endpoint; sin red -> encola (sin foto) con
/// offline_uuid. Mismo patrón que AttendanceRepository.
class MaintenanceRepository {
  MaintenanceRepository(this.api, this.queue);
  final ApiClient api;
  final OfflineQueue queue;

  static const _opType = 'create_maintenance_request';

  /// Precarga del formulario (permisos + vehículos + tipos).
  Future<MaintenanceCatalog> catalog() async {
    final res = await api.getJson('/maintenance/catalog');
    return MaintenanceCatalog.fromJson(res);
  }

  /// Alta de avería. Si falla por red, encola SIN foto y la marca como diferida.
  ///
  /// Devuelve el dict del backend en éxito online
  /// ({success, already_existed, id, name, stage, precisa_inmovilizacion}),
  /// o {success: true, queued: true, offline_uuid} si quedó en la cola.
  Future<Map<String, dynamic>> create({
    required int vehicleId,
    required int tipoAveriaId,
    required String descripcion,
    int? km,
    double? horasGrua,
    bool precisaInmovilizacion = false,
    String? fechaDeteccion, // 'YYYY-MM-DD'; por defecto, hoy
    List<MaintenancePhoto> photos = const [],
  }) async {
    final uuid = genOfflineUuid();

    // `data` = lo que viaja también en la cola offline (sin fotos).
    final data = <String, dynamic>{
      'vehicle_id': vehicleId,
      'tipo_averia_id': tipoAveriaId,
      'descripcion': descripcion,
      if (km != null) 'km': km,
      if (horasGrua != null) 'horas_grua': horasGrua,
      'precisa_inmovilizacion': precisaInmovilizacion,
      'fecha_deteccion': fechaDeteccion ?? _today(),
    };

    final payload = <String, dynamic>{
      'offline_uuid': uuid,
      ...data,
      if (photos.isNotEmpty) 'photos': photos.map((p) => p.toJson()).toList(),
    };

    try {
      return await api.postJson('/maintenance/requests', data: payload);
    } on ApiException catch (e) {
      // Solo se encola ante fallo de red, nunca ante errores de negocio.
      if (e.code == 'network_error') {
        await queue.enqueue(OfflineOp(
          offlineUuid: uuid,
          type: _opType,
          timestamp: _nowUtc(),
          data: data, // sin fotos: el md prohíbe foto en la cola
        ));
        return {'success': true, 'queued': true, 'offline_uuid': uuid};
      }
      rethrow;
    }
  }

  /// Histórico del chófer. `scope=all` solo lo respeta el backend si es manager.
  Future<({int count, String scope, List<MaintenanceRequestSummary> requests})> history(
      {String scope = 'mine'}) async {
    final res = await api.getJson('/maintenance/requests', query: {'scope': scope});
    final list = (res['requests'] ?? []) as List;
    return (
      count: (res['count'] ?? list.length) as int,
      scope: (res['scope'] ?? scope).toString(),
      requests:
          list.map((e) => MaintenanceRequestSummary.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }

  /// Sube las altas pendientes y confirma (ack) las aceptadas. Reenviar es
  /// seguro: el backend deduplica por offline_uuid.
  Future<int> syncPending() async {
    final pending = await queue.pending();
    if (pending.isEmpty) return 0;
    // El /maintenance/sync solo espera {offline_uuid, data} por operación.
    final res = await api.postJson('/maintenance/sync', data: {
      'operations': pending
          .map((o) => {'offline_uuid': o.offlineUuid, 'data': o.data})
          .toList(),
    });
    final results = (res['results'] ?? []) as List;
    final okUuids = results
        .where((r) => (r as Map)['success'] == true)
        .map((r) => (r as Map)['offline_uuid'].toString());
    await queue.ack(okUuids);
    return okUuids.length;
  }

  Future<bool> get hasPending => queue.hasPending;
}