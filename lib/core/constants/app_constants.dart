import 'package:latlong2/latlong.dart';

class AppConstants {
  AppConstants._();

  // ---------------------------------------------------------------------------
  // Fallback location: Kochi, Kerala
  // ---------------------------------------------------------------------------
  static const LatLng fallbackLocation = LatLng(9.9312, 76.2673);

  // ---------------------------------------------------------------------------
  // Map zoom
  // ---------------------------------------------------------------------------
  static const double defaultZoom = 15.0;
  static const double navigationZoom = 17.0;
  static const double searchResultZoom = 14.0;

  // ---------------------------------------------------------------------------
  // BLE
  // ---------------------------------------------------------------------------
  static const String bleDeviceName = 'MotoNav';
  static const String bleServiceUuid = '12345678-1234-1234-1234-123456789abc';
  static const String bleCharUuid = 'abcd1234-5678-90ab-cdef-123456789abc';

  // ---------------------------------------------------------------------------
  // ESP32 display
  // ---------------------------------------------------------------------------
  static const int displaySize = 240;
  static const int displayCenter = 120;

  // ---------------------------------------------------------------------------
  // Overpass cache
  // ---------------------------------------------------------------------------
  static const Duration overpassCacheDuration = Duration(minutes: 3);

  // ---------------------------------------------------------------------------
  // GPS
  // ---------------------------------------------------------------------------
  static const int gpsFastIntervalMs = 2000;
  static const int gpsNavigationIntervalMs = 1000;

  // ---------------------------------------------------------------------------
  // Nominatim search
  // ---------------------------------------------------------------------------
  static const int nominatimDebounceMs = 400;
  static const int nominatimMaxResults = 7;
}
