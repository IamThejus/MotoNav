/// MotoNav API Configuration
///
/// Replace GRAPH_HOPPER_API_KEY with your actual key.
/// In production, load from dart-define or environment:
///   flutter run --dart-define=GRAPH_HOPPER_API_KEY=your_key_here
class ApiConfig {
  ApiConfig._();

  // ---------------------------------------------------------------------------
  // GraphHopper
  // ---------------------------------------------------------------------------
  static const String graphHopperApiKey = String.fromEnvironment(
    'GRAPH_HOPPER_API_KEY',
    defaultValue: '5e1a4535-a0ce-4811-84aa-f055bace2fa8',
  );

  static const String graphHopperBaseUrl =
      'https://graphhopper.com/api/1';

  // ---------------------------------------------------------------------------
  // Nominatim (OpenStreetMap geocoding — no key required)
  // ---------------------------------------------------------------------------
  static const String nominatimBaseUrl =
      'https://nominatim.openstreetmap.org';

  /// User-Agent required by Nominatim usage policy.
  static const String nominatimUserAgent = 'MotoNav/1.0 (com.thejus.motonav)';

  // ---------------------------------------------------------------------------
  // Overpass (road geometry — no key required)
  // ---------------------------------------------------------------------------
  static const String overpassBaseUrl = 'https://overpass-api.de/api/interpreter';

  /// Radius in meters for road queries around user location.
  static const int overpassQueryRadiusMeters = 400;

  // ---------------------------------------------------------------------------
  // OSM Tile Server
  // ---------------------------------------------------------------------------
  static const String osmTileUrl =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
}
