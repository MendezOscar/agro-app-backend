import 'package:geolocator/geolocator.dart';

/// Captura la posición GPS actual para geolocalizar una observación.
///
/// Devuelve `[lng, lat]` (orden GeoJSON, igual que el resto del pipeline) o
/// `null` si no hay permiso, el servicio está apagado o falla la lectura.
/// Nunca lanza: geolocalizar es "best-effort" y no debe bloquear el registro.
Future<List<double>?> currentLngLat() async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return null;

    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      return null;
    }

    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 12),
      ),
    );
    return [pos.longitude, pos.latitude];
  } catch (_) {
    return null;
  }
}
