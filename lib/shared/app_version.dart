import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Información de versión de la app, leída del propio binario.
///
/// Fuente única (NO hardcodear): `version` y `buildNumber` salen del
/// `version: X.Y.Z+N` del `pubspec.yaml` en el momento de compilar el flavor.
/// Así el número que ve el chófer es exactamente el del APK instalado, lo que
/// es clave para soporte ("¿qué versión tienes?").
class AppVersion {
  const AppVersion({required this.version, required this.buildNumber});

  final String version; // X.Y.Z  (de pubspec)
  final String buildNumber; // N    (lo de detrás del '+')

  /// Cargada en cada `main_*` **antes** de `runApp`. El interceptor de red la
  /// lee de forma síncrona en todas las peticiones (`X-App-Version` / `X-App-Build`).
  static late final AppVersion current;

  /// Formato corto para mostrar al usuario, p. ej. "v1.0.0 (1)".
  /// Si por lo que sea no hubiera build number, cae a "v1.0.0".
  String get short =>
      buildNumber.isEmpty ? 'v$version' : 'v$version ($buildNumber)';

    /// Debe llamarse tras `WidgetsFlutterBinding.ensureInitialized()` y antes de `runApp`.
  /// Falla en voz alta si el build no es un entero > 0: sin cabecera válida el
  /// servidor nos trataría como v1 sin que nadie lo notara.
    /// Debe llamarse tras `WidgetsFlutterBinding.ensureInitialized()` y antes de `runApp`.
  /// Falla en voz alta si el build no es un entero > 0: sin cabecera válida el
  /// servidor nos trataría como v1 sin que nadie lo notara.
  ///
  /// Con `flutter build apk --split-per-abi`, Android recibe versionCode =
  /// ABI × 1000 + build (1010, 2010, 4010…). Se normaliza al build real del
  /// pubspec para que `X-App-Build` sea el mismo en todas las arquitecturas.
  static Future<void> load() async {
    final info = await PackageInfo.fromPlatform();
    final raw = int.tryParse(info.buildNumber) ?? 0;
    final build = raw >= 1000 ? raw % 1000 : raw;
    if (build <= 0) {
      throw StateError(
          'Build inválido ("${info.buildNumber}"): revisa version: X.Y.Z+N en pubspec.yaml');
    }
    current = AppVersion(version: info.version, buildNumber: '$build');
  }

  /// Cabeceras de convivencia v1/v2. Sin ellas el servidor trata al cliente como v1.
  static void applyHeaders(RequestOptions options) {
    options.headers['X-App-Version'] = current.version;
    options.headers['X-App-Build'] = current.buildNumber; // ya validado en load()
  }
}

/// Versión ya cargada en `main_*` antes de `runApp`.
final appVersionProvider = Provider<AppVersion>((ref) => AppVersion.current);
