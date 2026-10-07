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
