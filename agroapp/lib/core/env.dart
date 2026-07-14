/// Configuración de entorno. Sobrescribible con --dart-define.
/// Android emulador usa 10.0.2.2 para alcanzar el host; iOS simulador usa localhost.
class Env {
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:5192',
  );

  static const maptilerKey = String.fromEnvironment(
    'MAPTILER_KEY',
    defaultValue: '',
  );
}
