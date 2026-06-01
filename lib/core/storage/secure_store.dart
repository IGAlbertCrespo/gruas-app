import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Almacenamiento seguro: token de sesión y perfil de conexión.
/// La clave PRIVADA del dispositivo NO se guarda aquí: vive en el almacén
/// hardware (Keystore/Secure Enclave) gestionado por DeviceIdentityService.
class SecureStore {
  SecureStore(this._storage);
  final FlutterSecureStorage _storage;

  static const _kToken = 'session_token';
  static const _kTokenExpiry = 'session_token_expiry';
  static const _kProfile = 'connection_profile';
  static const _kDeviceId = 'device_fingerprint';

  Future<void> saveToken(String token, DateTime expiresAt) async {
    await _storage.write(key: _kToken, value: token);
    await _storage.write(key: _kTokenExpiry, value: expiresAt.toIso8601String());
  }

  Future<String?> readToken() => _storage.read(key: _kToken);

  Future<DateTime?> readTokenExpiry() async {
    final v = await _storage.read(key: _kTokenExpiry);
    return v == null ? null : DateTime.tryParse(v);
  }

  Future<void> clearSession() async {
    await _storage.delete(key: _kToken);
    await _storage.delete(key: _kTokenExpiry);
  }

  Future<void> saveProfile(String encoded) => _storage.write(key: _kProfile, value: encoded);
  Future<String?> readProfile() => _storage.read(key: _kProfile);

  Future<void> saveDeviceId(String fingerprint) => _storage.write(key: _kDeviceId, value: fingerprint);
  Future<String?> readDeviceId() => _storage.read(key: _kDeviceId);

  /// Borrado total: re-emparejamiento / cierre de sesión completo.
  Future<void> wipe() => _storage.deleteAll();
}
