import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Cola de operaciones de asistencia realizadas sin red.
/// Cada operación lleva un offline_uuid para idempotencia en el backend.
class OfflineOp {
  final String offlineUuid;
  final String type; // check_in | check_out | break_start | break_end
  final String timestamp; // ISO8601
  final Map<String, dynamic> data;

  OfflineOp({
    required this.offlineUuid,
    required this.type,
    required this.timestamp,
    required this.data,
  });

  Map<String, dynamic> toJson() =>
      {'offline_uuid': offlineUuid, 'type': type, 'timestamp': timestamp, 'data': data};

  factory OfflineOp.fromJson(Map<String, dynamic> j) => OfflineOp(
        offlineUuid: j['offline_uuid'].toString(),
        type: j['type'].toString(),
        timestamp: j['timestamp'].toString(),
        data: (j['data'] ?? {}) as Map<String, dynamic>,
      );
}

class OfflineQueue {
  OfflineQueue(this._storage);
  final FlutterSecureStorage _storage;
  static const _key = 'attendance_offline_queue';

  Future<List<OfflineOp>> _read() async {
    final raw = await _storage.read(key: _key);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List;
    return list.map((e) => OfflineOp.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> _write(List<OfflineOp> ops) =>
      _storage.write(key: _key, value: jsonEncode(ops.map((e) => e.toJson()).toList()));

  Future<void> enqueue(OfflineOp op) async {
    final ops = await _read();
    ops.add(op);
    await _write(ops);
  }

  Future<List<OfflineOp>> pending() => _read();
  Future<bool> get hasPending async => (await _read()).isNotEmpty;

  /// Elimina las operaciones confirmadas por el servidor (por offline_uuid).
  Future<void> ack(Iterable<String> uuids) async {
    final set = uuids.toSet();
    final ops = await _read();
    ops.removeWhere((o) => set.contains(o.offlineUuid));
    await _write(ops);
  }
}
