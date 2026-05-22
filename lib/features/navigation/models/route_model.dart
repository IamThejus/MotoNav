import 'package:latlong2/latlong.dart';

class RouteStep {
  final String instruction;
  final double distanceMeters;
  final LatLng point;
  final int sign; // 0=straight, 2=right, -2=left, 4=arrive

  const RouteStep({
    required this.instruction,
    required this.distanceMeters,
    required this.point,
    required this.sign,
  });

  factory RouteStep.fromJson(Map<String, dynamic> json) {
    final lat = (json['lat'] as num?)?.toDouble() ?? 0.0;
    final lon = (json['lon'] as num?)?.toDouble() ?? 0.0;

    return RouteStep(
      instruction: json['text'] as String? ?? '',
      distanceMeters: (json['distance'] as num?)?.toDouble() ?? 0.0,
      point: LatLng(lat, lon),
      sign: json['sign'] as int? ?? 0,
    );
  }
}

class RouteResult {
  final List<LatLng> polyline;
  final double distanceMeters;
  final int durationMs;
  final List<RouteStep> steps;

  const RouteResult({
    required this.polyline,
    required this.distanceMeters,
    required this.durationMs,
    required this.steps,
  });

  String get distanceLabel {
    if (distanceMeters >= 1000) {
      return '${(distanceMeters / 1000).toStringAsFixed(1)} km';
    }
    return '${distanceMeters.round()} m';
  }

  String get durationLabel {
    final minutes = (durationMs / 60000).round();
    if (minutes >= 60) {
      final h = minutes ~/ 60;
      final m = minutes % 60;
      return m == 0 ? '${h}h' : '${h}h ${m}m';
    }
    return '$minutes min';
  }
}
