import 'dart:math';

import 'package:latlong2/latlong.dart';

import '../../../core/config/api_config.dart';
import '../../../core/constants/app_constants.dart';

class CoordinateNormalizer {
  // 120 px / 400 m = 0.3 px per metre
  static const double _pixelsPerMeter =
      AppConstants.displayCenter / ApiConfig.overpassQueryRadiusMeters;

  /// Convert [point] to a signed pixel offset (cx=0, cy=0) relative to
  /// [userLocation], with heading-up rotation applied so [headingDeg] points
  /// toward the top of the display.
  ///
  /// Returns Point(ox, oy) where:
  ///   ox > 0 → right of rider   ox < 0 → left
  ///   oy > 0 → below rider      oy < 0 → above (ahead when heading-up)
  /// Values are clamped to [-120, 119].
  static Point<int> normalize(
    LatLng point,
    LatLng userLocation,
    double headingDeg,
  ) {
    const metersPerDegLat = 111000.0;
    final metersPerDegLon =
        111000.0 * cos(userLocation.latitude * pi / 180.0);

    // Geographic displacements (east / north)
    final dx = (point.longitude - userLocation.longitude) * metersPerDegLon;
    final dy = (point.latitude - userLocation.latitude) * metersPerDegLat;

    // Rotate so heading direction → display up
    // right-of-heading = dx·cos(H) − dy·sin(H)
    // ahead-of-heading = dx·sin(H) + dy·cos(H)
    final h = headingDeg * pi / 180.0;
    final cosH = cos(h);
    final sinH = sin(h);
    final rotRight = dx * cosH - dy * sinH;
    final rotAhead = dx * sinH + dy * cosH;

    // Screen coords: right → +x, ahead → −y (screen y increases downward)
    final ox = (rotRight * _pixelsPerMeter).round().clamp(-120, 119);
    final oy = (-rotAhead * _pixelsPerMeter).round().clamp(-120, 119);

    return Point(ox, oy);
  }

  static List<Point<int>> normalizeAll(
    List<LatLng> points,
    LatLng userLocation,
    double headingDeg,
  ) =>
      points.map((p) => normalize(p, userLocation, headingDeg)).toList();
}
