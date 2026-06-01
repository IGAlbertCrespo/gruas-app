/// Excepción uniforme de la capa de red.
class ApiException implements Exception {
  final String code;       // p.ej. 'invalid_token', 'device_not_authorized'
  final int? status;       // HTTP status
  final String? detail;    // mensaje legible (incluye validaciones de negocio)

  ApiException(this.code, {this.status, this.detail});

  bool get isAuth => status == 401;
  bool get isForbidden => status == 403;
  bool get needsReauth => code == 'invalid_token' || code == 'missing_token';
  bool get deviceNotAuthorized => code == 'device_not_authorized';

  @override
  String toString() => detail ?? code;
}
