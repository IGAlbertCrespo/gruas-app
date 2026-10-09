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
  /// Forzar actualización. Nunca es 401: un 401 dispara re-login.
  bool get upgradeRequired => status == 426 || code == 'upgrade_required';
  bool get sinPermiso => code == 'sin_permiso';
  bool get tareaFirmada => code == 'tarea_firmada';
  bool get noEditable => code == 'no_editable';
  /// Lo que la APP mostraba ya no es así (lista desactualizada): refrescar.
  bool get listaDesactualizada =>
      code == 'cargo_duplicado' || code == 'cargo_no_anulable' || code == 'linea_no_valida';
  bool get noEsMadre => code == 'no_es_madre';
  /// Sin respuesta del servidor (sin cobertura, timeout…): ApiClient lo
  /// traduce a 'network_error' sin status HTTP.
  bool get sinConexion => code == 'network_error' && status == null;

  @override
  String toString() => detail ?? code;
}
