import 'package:dio/dio.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/services/logger_service.dart';
import '../models/route_model.dart';
import 'routing_service.dart';

// OSRM maneuver type+modifier → GraphHopper sign mapping
const _signMap = {
  'depart':                  0,
  'arrive':                  4,
  'straight':                0,
  'slight left':            -1,
  'slight right':            1,
  'left':                   -2,
  'right':                   2,
  'sharp left':             -3,
  'sharp right':             3,
  'uturn':                  -4,
  'roundabout':              6,
  'rotary':                  6,
};

int _toSign(String type, String? modifier) {
  if (type == 'arrive') return 4;
  if (type == 'depart') return 0;
  if (type == 'roundabout' || type == 'rotary') return 6;
  return _signMap[modifier ?? 'straight'] ?? 0;
}

class OsrmService implements RoutingService {
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
    ),
  );

  @override
  Future<RouteResult> getRoute({
    required LatLng origin,
    required LatLng destination,
    String profile = 'car',
  }) async {
    final coords =
        '${origin.longitude},${origin.latitude};'
        '${destination.longitude},${destination.latitude}';

    final url =
        'https://router.project-osrm.org/route/v1/driving/$coords'
        '?overview=full&geometries=geojson&steps=true';

    try {
      final response = await _dio.get<Map<String, dynamic>>(url);
      final data = response.data;

      if (data == null || data['code'] != 'Ok') {
        throw Exception('OSRM returned no route');
      }

      final routes = data['routes'] as List<dynamic>;
      if (routes.isEmpty) throw Exception('No route found');

      final route = routes[0] as Map<String, dynamic>;

      // Parse full polyline from route geometry
      final geom   = route['geometry'] as Map<String, dynamic>;
      final coords_ = geom['coordinates'] as List<dynamic>;
      final polyline = coords_
          .cast<List<dynamic>>()
          .where((c) => c.length >= 2 && c[0] != null && c[1] != null)
          .map((c) => LatLng(
                (c[1] as num).toDouble(),
                (c[0] as num).toDouble(), // GeoJSON [lon, lat]
              ))
          .toList();

      // Parse steps from the first (and only) leg
      final legs  = route['legs'] as List<dynamic>;
      final steps = <RouteStep>[];

      if (legs.isNotEmpty) {
        final leg       = legs[0] as Map<String, dynamic>;
        final stepsList = leg['steps'] as List<dynamic>;

        for (final s in stepsList.cast<Map<String, dynamic>>()) {
          final maneuver = s['maneuver'] as Map<String, dynamic>;
          final loc      = maneuver['location'] as List<dynamic>;
          final type     = maneuver['type']     as String? ?? 'straight';
          final modifier = maneuver['modifier'] as String?;

          steps.add(RouteStep(
            instruction: s['name'] as String? ?? '',
            distanceMeters: (s['distance'] as num?)?.toDouble() ?? 0.0,
            point: LatLng(
              (loc[1] as num).toDouble(),
              (loc[0] as num).toDouble(),
            ),
            sign: _toSign(type, modifier),
          ));
        }
      }

      final totalDist = (route['distance'] as num?)?.toDouble() ?? 0.0;
      final totalTime = ((route['duration'] as num?)?.toDouble() ?? 0.0) * 1000;

      appLogger.i(
        'OSRM route: ${(totalDist / 1000).toStringAsFixed(1)} km, '
        '${(totalTime / 60000).round()} min, ${steps.length} steps',
      );

      return RouteResult(
        polyline: polyline,
        distanceMeters: totalDist,
        durationMs: totalTime.round(),
        steps: steps,
      );
    } on DioException catch (e) {
      appLogger.e('OSRM route error', error: e);
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        throw Exception('Routing request timed out. Check your connection.');
      }
      throw Exception('Routing request failed. Check your connection.');
    } catch (e) {
      appLogger.e('OSRM unexpected error', error: e);
      rethrow;
    }
  }
}
