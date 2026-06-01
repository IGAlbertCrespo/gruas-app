import 'dart:async';
import 'package:dio/dio.dart';

/// Inyecta el Bearer token y, ante un 401, intenta un re-login silencioso
/// (reto-respuesta con la clave hardware) una sola vez y reintenta la petición.
///
/// El re-login real lo provee un callback para no acoplar el interceptor a las
/// dependencias de auth (evita ciclos): [getToken] y [refreshToken].
class AuthInterceptor extends QueuedInterceptor {
  AuthInterceptor({
    required this.dio,
    required this.getToken,
    required this.refreshToken,
    required this.onSessionLost,
  });

  final Dio dio;
  final Future<String?> Function() getToken;
  final Future<String?> Function() refreshToken; // devuelve nuevo token o null
  final void Function() onSessionLost;

  bool _refreshing = false;

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    // Los endpoints públicos no llevan token.
    final isPublic = options.path.contains('/auth/') || options.path.endsWith('/enroll');
    if (!isPublic) {
      final token = await getToken();
      if (token != null) options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final res = err.response;
    final path = err.requestOptions.path;
    final isPublic = path.contains('/auth/') || path.endsWith('/enroll');
    final shouldTryRefresh = res?.statusCode == 401 &&
        !isPublic &&
        !_refreshing &&
        !(err.requestOptions.extra['retried'] == true);

    if (!shouldTryRefresh) return handler.next(err);

    _refreshing = true;
    try {
      final newToken = await refreshToken();
      if (newToken == null) {
        onSessionLost();
        return handler.next(err);
      }
      final req = err.requestOptions;
      req.headers['Authorization'] = 'Bearer $newToken';
      req.extra['retried'] = true;
      final clone = await dio.fetch(req);
      return handler.resolve(clone);
    } catch (_) {
      onSessionLost();
      return handler.next(err);
    } finally {
      _refreshing = false;
    }
  }
}
