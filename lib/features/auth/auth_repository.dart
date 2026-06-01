import '../../core/network/api_client.dart';
import '../../core/storage/secure_store.dart';
import '../identity/device_identity_service.dart';
import 'session_models.dart';

/// Orquesta el handshake de identidad por dispositivo.
///
/// Flujo:
///  - enroll(): genera keypair en hardware, envía la pública -> dispositivo PENDIENTE.
///  - login(): pide nonce, lo firma con la clave hardware, obtiene token Bearer.
///  - me(): perfil del operador (empleado, rol, capacidades).
class AuthRepository {
  AuthRepository({
    required this.api,
    required this.identity,
    required this.store,
  });

  final ApiClient api;
  final DeviceIdentityService identity;
  final SecureStore store;

  /// Alta del dispositivo. Devuelve el estado (normalmente 'pending').
  Future<EnrollmentState> enroll({String? name, String? platform}) async {
    final publicKey = await identity.getOrCreatePublicKey();
    final res = await api.postJson('/enroll', data: {
      'public_key': publicKey,
      if (name != null) 'name': name,
      if (platform != null) 'platform': platform,
    });
    final fingerprint = res['device_id']?.toString();
    if (fingerprint != null) await store.saveDeviceId(fingerprint);
    return enrollmentFromString(res['state']?.toString());
  }

  /// Reto-respuesta -> token. Persiste el token y su expiración.
  /// Devuelve el token o null si el dispositivo aún no está autorizado.
  Future<String?> login() async {
    final deviceId = await store.readDeviceId();
    if (deviceId == null) return null;

    final challenge = await api.postJson('/auth/challenge', data: {'device_id': deviceId});
    final nonce = challenge['nonce']?.toString();
    if (nonce == null) return null;

    final signature = await identity.signNonce(nonce);

    final tokenRes = await api.postJson('/auth/token', data: {
      'device_id': deviceId,
      'nonce': nonce,
      'signature': signature,
    });
    final token = tokenRes['token']?.toString();
    final expiresAt = DateTime.tryParse(tokenRes['expires_at']?.toString() ?? '') ??
        DateTime.now().add(const Duration(hours: 1));
    if (token != null) await store.saveToken(token, expiresAt);
    return token;
  }

  Future<OperatorProfile> me() async {
    final res = await api.getJson('/me');
    return OperatorProfile.fromJson(res);
  }
}
