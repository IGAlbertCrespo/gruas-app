import 'package:geolocator/geolocator.dart';

/// Ubicación "best-effort": devuelve (null, null) si no hay permiso, servicio,
/// o si tarda más de 5 s. Nunca lanza ni bloquea al llamante.
Future<(double?, double?)> bestEffortLocation() async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return (null, null);
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
      return (null, null);
    }
    final pos = await Geolocator.getCurrentPosition().timeout(const Duration(seconds: 5));
    return (pos.latitude, pos.longitude);
  } catch (_) {
    return (null, null);
  }
}

/// v3.13: como [bestEffortLocation] pero SIN pedir permiso. Se puede lanzar en
/// paralelo mientras el conductor rellena un formulario: nunca abre el diálogo
/// del sistema encima. Sin permiso concedido devuelve (null, null).
Future<(double?, double?)> ubicacionSiHayPermiso() async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return (null, null);
    final perm = await Geolocator.checkPermission();
    if (perm != LocationPermission.always && perm != LocationPermission.whileInUse) {
      return (null, null);
    }
    final pos = await Geolocator.getCurrentPosition().timeout(const Duration(seconds: 5));
    return (pos.latitude, pos.longitude);
  } catch (_) {
    return (null, null);
  }
}
