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

/// Dio configurado con el baseUrl del perfil + interceptor de auth.
final dioProvider = Provider<Dio>((ref) {
  final store = ref.watch(secureStoreProvider);
  final profile = ref.watch(connectionProfileProvider);

  final dio = Dio(BaseOptions(
    baseUrl: profile?.baseUrl ?? '',
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
    headers: {'Content-Type': 'application/json'},
  ));

  dio.interceptors.add(AuthInterceptor(
    dio: dio,
    getToken: () => store.readToken(),
    refreshToken: () async {
      // Re-login silencioso con la clave hardware.
      return ref.read(authRepositoryProvider).login();
    },
    onSessionLost: () {
      // El controlador de sesión observará el token ausente.
      store.clearSession();
    },
  ));
  return dio;
});

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient(ref.watch(dioProvider)));

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
    api: ref.watch(apiClientProvider),
    identity: ref.watch(identityProvider),
    store: ref.watch(secureStoreProvider),
  );
});
