import 'package:dio/dio.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/config/api_config.dart';
import '../../../core/services/logger_service.dart';
import '../models/route_model.dart';
import 'routing_service.dart';

class GraphHopperService implements RoutingService {
  final Dio _dio = Dio(
    BaseOptions(
      baseUrl: ApiConfig.graphHopperBaseUrl,
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
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/route',
        queryParameters: {
          'point': [
            '${origin.latitude},${origin.longitude}',
            '${destination.latitude},${destination.longitude}',
          ],
          'vehicle': profile,
          'locale': 'en',
          'calc_points': true,
          'points_encoded': false,
          'instructions': true,
          'key': ApiConfig.graphHopperApiKey,
        },
      );

      final data = response.data;
      if (data == null) throw Exception('Empty response from GraphHopper');

      final paths = data['paths'] as List<dynamic>;
      if (paths.isEmpty) throw Exception('No route found');

      final path = paths[0] as Map<String, dynamic>;

      // Parse polyline
      final pointsMap = path['points'] as Map<String, dynamic>;
      final coords = pointsMap['coordinates'] as List<dynamic>;
      final polyline = coords
          .map((c) => c as List<dynamic>)
          .where((pair) => pair.length >= 2 && pair[0] != null && pair[1] != null)
          .map((pair) => LatLng(
                (pair[1] as num).toDouble(),
                (pair[0] as num).toDouble(), // GeoJSON is [lon, lat]
              ))
          .toList();

      // Parse instructions — position comes from polyline[interval[0]],
      // NOT from lat/lon fields (GraphHopper instructions have no lat/lon).
      final instructions = path['instructions'] as List<dynamic>? ?? [];
      final steps = <RouteStep>[];
      for (final instr in instructions.cast<Map<String, dynamic>>()) {
        final interval = instr['interval'] as List<dynamic>?;
        LatLng point;
        if (interval != null && interval.isNotEmpty) {
          final ptIdx = (interval[0] as num).toInt().clamp(0, polyline.length - 1);
          point = polyline[ptIdx];
        } else {
          point = polyline.isNotEmpty ? polyline.last : const LatLng(0, 0);
        }
        steps.add(RouteStep(
          instruction: instr['text'] as String? ?? '',
          distanceMeters: (instr['distance'] as num?)?.toDouble() ?? 0.0,
          point: point,
          sign: instr['sign'] as int? ?? 0,
        ));
      }

      return RouteResult(
        polyline: polyline,
        distanceMeters: (path['distance'] as num?)?.toDouble() ?? 0.0,
        durationMs: (path['time'] as num?)?.toInt() ?? 0,
        steps: steps,
      );
    } on DioException catch (e) {
      appLogger.e('GraphHopper route error', error: e);
      final statusCode = e.response?.statusCode;
      if (statusCode == 400) {
        throw Exception('Route not found between these points.');
      } else if (statusCode == 401 || statusCode == 403) {
        throw Exception('Invalid GraphHopper API key.');
      }
      throw Exception('Routing request failed. Check your connection.');
    } catch (e) {
      appLogger.e('GraphHopper unexpected error', error: e);
      rethrow;
    }
  }
}
