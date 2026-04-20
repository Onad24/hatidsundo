/// Environment configuration
/// These values should be set via --dart-define during build
class EnvConfig {
  EnvConfig._();

  // Supabase
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://dwogrvalyrbubwsaunyo.supabase.co',
  );

  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_pp5lrF1nJOZuD4wi68HUyg_K0UBSlTF',
  );

  // OSRM
  static const String osrmBaseUrl = String.fromEnvironment(
    'OSRM_BASE_URL',
    defaultValue: 'https://router.project-osrm.org',
  );

  // Google OAuth
  static const String googleWebClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
    defaultValue:
        '891809439038-81j0g7sdq69dl4brgehi04crj2ru591h.apps.googleusercontent.com',
  );

  // App Flavor (client, rider, admin)
  static const String appFlavor = String.fromEnvironment(
    'FLAVOR',
    defaultValue: 'client',
  );

  // Map Tiles
  static const String mapTileUrl = String.fromEnvironment(
    'MAP_TILE_URL',
    defaultValue: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
  );

  // MapLibre Style URL (OpenFreeMap provides free OSM-based vector tiles)
  static const String mapStyleUrl = String.fromEnvironment(
    'MAP_STYLE_URL',
    defaultValue: 'https://tiles.openfreemap.org/styles/liberty',
  );

  // Debug Mode
  static const bool isDebug = bool.fromEnvironment('DEBUG', defaultValue: true);

  // Feature Flags
  static const bool enableOfflineMode = bool.fromEnvironment(
    'ENABLE_OFFLINE',
    defaultValue: true,
  );

  static const bool enableAnalytics = bool.fromEnvironment(
    'ENABLE_ANALYTICS',
    defaultValue: false,
  );

  // Validation
  static bool get isConfigured {
    return supabaseUrl.isNotEmpty &&
        !supabaseUrl.contains('hatid-sundo') &&
        supabaseAnonKey.isNotEmpty;
  }

  static void validate() {
    if (!isConfigured) {
      throw Exception(
        'Supabase not configured. Please set SUPABASE_URL and SUPABASE_ANON_KEY '
        'via --dart-define or environment variables.',
      );
    }
  }
}
