import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Libro de jornada local. Acumula, **sin red**, los datos necesarios para
/// reconciliar la pausa de comida al fichar salida:
///
/// - `declared`: pausa que el chófer imputa al cliente al cerrar cada recurso.
///   Clave = recursoId (no se suma, se fija), para que reabrir/re-cerrar una
///   tarea sobrescriba en vez de duplicar.
/// - `clocked`: suma de las duraciones de las pausas reales que la propia app
///   inicia y cierra (las fichadas a mano).
/// - `break_start`: inicio de la pausa en curso, persistido para que sobreviva
///   a un cambio de pestaña o a que el sistema mate la app a media pausa.
///
/// Se limpia al fichar entrada (jornada nueva) y se consume al fichar salida.
class JourneyLedger {
  JourneyLedger(this._storage);
  final FlutterSecureStorage _storage;
  static const _key = 'journey_ledger';

  Future<Map<String, dynamic>> _read() async {
    final raw = await _storage.read(key: _key);
    if (raw == null) {
      return {'declared': <String, dynamic>{}, 'clocked': 0.0, 'break_start': null};
    }
    final m = jsonDecode(raw) as Map<String, dynamic>;
    m['declared'] ??= <String, dynamic>{};
    m['clocked'] ??= 0.0;
    return m;
  }

  Future<void> _write(Map<String, dynamic> m) =>
      _storage.write(key: _key, value: jsonEncode(m));

  /// Fija (no suma) la pausa declarada al cerrar un recurso. 0 => borra la
  /// entrada (p. ej. si se cierra sin pausa tras una reapertura).
  Future<void> setDeclared(int recursoId, double horas) async {
    final m = await _read();
    final dec = Map<String, dynamic>.from(m['declared'] as Map);
    if (horas <= 0) {
      dec.remove(recursoId.toString());
    } else {
      dec[recursoId.toString()] = horas;
    }
    m['declared'] = dec;
    await _write(m);
  }

  /// Elimina la pausa declarada de un recurso (al reabrirlo).
  Future<void> removeDeclared(int recursoId) async {
    final m = await _read();
    final dec = Map<String, dynamic>.from(m['declared'] as Map);
    dec.remove(recursoId.toString());
    m['declared'] = dec;
    await _write(m);
  }

  /// Suma la duración (horas) de una pausa real fichada.
  Future<void> addClocked(double horas) async {
    if (horas <= 0) return;
    final m = await _read();
    m['clocked'] = ((m['clocked'] as num?)?.toDouble() ?? 0.0) + horas;
    await _write(m);
  }

  Future<void> setBreakStart(DateTime when) async {
    final m = await _read();
    m['break_start'] = when.toUtc().toIso8601String();
    await _write(m);
  }

  Future<void> clearBreakStart() async {
    final m = await _read();
    m['break_start'] = null;
    await _write(m);
  }

  Future<DateTime?> breakStart() async {
    final m = await _read();
    final s = m['break_start'];
    return s == null ? null : DateTime.tryParse(s as String)?.toLocal();
  }

  /// Suma de las pausas imputadas al cliente en la jornada.
  Future<double> declaredTotal() async {
    final m = await _read();
    final dec = m['declared'] as Map;
    var t = 0.0;
    for (final v in dec.values) {
      t += (v as num).toDouble();
    }
    return t;
  }

  /// Suma de las pausas reales fichadas en la jornada.
  Future<double> clockedTotal() async {
    final m = await _read();
    return (m['clocked'] as num?)?.toDouble() ?? 0.0;
  }

  /// Borra el libro entero (al fichar entrada o tras consumirlo en salida).
  Future<void> clear() => _storage.delete(key: _key);
}