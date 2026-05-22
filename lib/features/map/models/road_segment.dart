import 'package:latlong2/latlong.dart';

enum RoadClass { main, minor }

class RoadSegment {
  final List<LatLng> points;
  final RoadClass roadClass;

  const RoadSegment({required this.points, required this.roadClass});
}
