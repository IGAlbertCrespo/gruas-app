import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'env/connection_profile.dart';
import 'network/api_client.dart';
import 'network/auth_interceptor.dart';
import 'storage/secure_store.dart';
import '../features/identity/device_identity_service.dart';
import '../features/identity/secp256r1_identity_service.dart';
import '../features/auth/auth_repository.dart';

/// Almacenamiento seguro.
final secureStoreProvider = Provider<SecureStore>((ref) {
  return SecureStore(const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  ));
});

/// Identidad criptográfica del dispositivo (P-256 en hardware).
final identityProvider = Provider<DeviceIdentityService>((ref) {
  return Secp256r1IdentityService();
});

/// Perfil de conexión activo (base_url + db). Se carga del almacén seguro.
final connectionProfileProvider = StateProvider<ConnectionProfile?>((ref) => null);

BaseOptions _baseOptions(ConnectionProfile? profile) => BaseOptions(
      baseUrl: profile?.baseUrl ?? '',
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'Content-Type': 'application/json'},
    );

/// Dio "plano" SIN interceptor, para el handshake de autenticación
/// (endpoints públicos: enroll/challenge/token). Romper aquí la dependencia
/// evita el ciclo dio -> authRepository -> apiClient -> dio.
final authDioProvider = Provider<Dio>((ref) {
  return Dio(_baseOptions(ref.watch(connectionProfileProvider)));
});

/// Dio autenticado, con interceptor de Bearer + refresco silencioso en 401.
final dioProvider = Provider<Dio>((ref) {
  final store = ref.watch(secureStoreProvider);
  final dio = Dio(_baseOptions(ref.watch(connectionProfileProvider)));

  dio.interceptors.add(AuthInterceptor(
    dio: dio,
    getToken: () => store.readToken(),
    // Refresco silencioso: reto-respuesta con la clave hardware, usando el Dio
    // plano (sin interceptor) para no recursar ni crear ciclo de providers.
    refreshToken: () async {
      final deviceId = await store.readDeviceId();
      if (deviceId == null) return null;
      final authDio = ref.read(authDioProvider);
      final ch = await authDio.post(
        '${ApiClient.apiPrefix}/auth/challenge',
        data: {'device_id': deviceId},
      );
      final nonce = (ch.data as Map)['nonce']?.toString();
      if (nonce == null) return null;
      final signature = await ref.read(identityProvider).signNonce(nonce);
      final tk = await authDio.post(
        '${ApiClient.apiPrefix}/auth/token',
        data: {'device_id': deviceId, 'nonce': nonce, 'signature': signature},
      );
      final data = tk.data as Map;
      final token = data['token']?.toString();
      final expiresAt = DateTime.tryParse(data['expires_at']?.toString() ?? '') ??
          DateTime.now().add(const Duration(hours: 1));
      if (token != null) await store.saveToken(token, expiresAt);
      return token;
    },
    onSessionLost: () => store.clearSession(),
  ));
  return dio;
});

/// Cliente autenticado (para /me, asistencia, tareas).
final apiClientProvider = Provider<ApiClient>((ref) => ApiClient(ref.watch(dioProvider)));

/// Cliente plano para el handshake (enroll/challenge/token).
final authApiClientProvider = Provider<ApiClient>((ref) => ApiClient(ref.watch(authDioProvider)));

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
    api: ref.watch(apiClientProvider),          // /me (autenticado)
    authApi: ref.watch(authApiClientProvider),  // enroll/challenge/token (plano)
    identity: ref.watch(identityProvider),
    store: ref.watch(secureStoreProvider),
  );
});
