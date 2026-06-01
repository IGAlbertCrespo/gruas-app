/// Entornos de despliegue. La separación staging/producción se hace por
/// build flavor (entrypoints distintos), NO por un selector en runtime de la
/// app de producción, para evitar fichar/firmar contra la BD equivocada.
enum AppEnvironment { staging, production }

class EnvConfig {
  final AppEnvironment environment;

  /// URL base por defecto del flavor (puede sobrescribirse al aprovisionar por QR).
  final String defaultBaseUrl;

  /// Permite cambiar de entorno/perfil desde dentro de la app.
  /// Solo true en el flavor de staging/QA. NUNCA en producción.
  final bool allowEnvironmentSwitch;

  const EnvConfig({
    required this.environment,
    required this.defaultBaseUrl,
    required this.allowEnvironmentSwitch,
  });

  bool get isProduction => environment == AppEnvironment.production;
  String get label => environment == AppEnvironment.production ? 'PRODUCCIÓN' : 'STAGING';
}

/// Inyectado por el entrypoint del flavor (main_production / main_staging).
class Env {
  static late EnvConfig config;
}
