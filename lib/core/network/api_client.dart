import 'package:dio/dio.dart';

import 'api_exception.dart';

/// Cliente REST contra el módulo gruas_mobile_api.
/// Centraliza el prefijo /api/v1/mobile y la traducción de errores a ApiException.
class ApiClient {
  ApiClient(this._dio);
  final Dio _dio;

  static const apiPrefix = '/api/v1/mobile';

  Dio get raw => _dio;

  Future<Map<String, dynamic>> getJson(String path, {Map<String, dynamic>? query}) async {
    return _wrap(() => _dio.get('$apiPrefix$path', queryParameters: query));
  }

  Future<Map<String, dynamic>> postJson(String path, {Object? data}) async {
    return _wrap(() => _dio.post('$apiPrefix$path', data: data));
  }

  Future<Map<String, dynamic>> _wrap(Future<Response> Function() call) async {
    try {
      final res = await call();
      final body = res.data;
      if (body is Map<String, dynamic>) {
        if (body.containsKey('error')) {
          throw ApiException(body['error'].toString(),
              status: res.statusCode, detail: body['detail']?.toString());
        }
        return body;
      }
      // Respuestas que no son objeto JSON (lista, etc.) se envuelven.
      return {'data': body};
    } on DioException catch (e) {
      final data = e.response?.data;
      if (data is Map && data['error'] != null) {
        throw ApiException(data['error'].toString(),
            status: e.response?.statusCode, detail: data['detail']?.toString());
      }
      throw ApiException('network_error', status: e.response?.statusCode, detail: e.message);
    }
  }
}
