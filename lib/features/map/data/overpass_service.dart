import 'package:dio/dio.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/config/api_config.dart';
import '../../../core/services/logger_service.dart';
import '../models/road_segment.dart';

class OverpassService {
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
    ),
  );

  static const _mainHighways = <String>{'motorway', 'trunk', 'primary'};

  Future<List<RoadSegment>> getRoads(LatLng center) async {
    const radius = ApiConfig.overpassQueryRadiusMeters;
    final lat = center.latitude;
    final lon = center.longitude;

    // \$ escapes the dollar sign so Dart doesn't treat it as interpolation
    final query =
        '[out:json][timeout:10];'
        '(way["highway"~"^(motorway|trunk|primary|secondary|tertiary|residential|unclassified)\$"]'
        '(around:$radius,$lat,$lon););'
        'out geom;';

    try {
      final response = await _dio.post<Map<String, dynamic>>(
        ApiConfig.overpassBaseUrl,
        data: 'data=${Uri.encodeComponent(query)}',
        options: Options(
          contentType: 'application/x-www-form-urlencoded',
        ),
      );

      final data = response.data;
      if (data == null) return [];

      final elements = data['elements'] as List<dynamic>? ?? [];
      final segments = <RoadSegment>[];

      for (final element in elements) {
        final map = element as Map<String, dynamic>;
        if (map['type'] != 'way') continue;

        final tags = map['tags'] as Map<String, dynamic>? ?? {};
        final highway = tags['highway'] as String? ?? '';
        final geom = map['geometry'] as List<dynamic>? ?? [];
        if (geom.length < 2) continue;

        final points = geom
            .cast<Map<String, dynamic>>()
            .map((g) => LatLng(
                  (g['lat'] as num).toDouble(),
                  (g['lon'] as num).toDouble(),
                ))
            .toList();

        segments.add(RoadSegment(
          points: points,
          roadClass:
              _mainHighways.contains(highway) ? RoadClass.main : RoadClass.minor,
        ));
      }

      appLogger.i('Overpass: ${segments.length} road segments around $lat,$lon');
      return segments;
    } catch (e) {
      appLogger.e('Overpass query failed', error: e);
      return [];
    }
  }
}
