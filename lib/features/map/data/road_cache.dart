import 'package:latlong2/latlong.dart';
import '../models/road_segment.dart';

class RoadCache {
  final Duration ttl;

  List<RoadSegment>? _data;
  DateTime? _fetchedAt;
  LatLng? _fetchLocation;

  RoadCache({this.ttl = const Duration(minutes: 3)});

  List<RoadSegment>? get data => _data;

  bool needsRefresh(LatLng currentLocation) {
    if (_data == null || _fetchedAt == null || _fetchLocation == null) {
      return true;
    }
    if (DateTime.now().difference(_fetchedAt!) > ttl) return true;
    final distM = const Distance().as(
      LengthUnit.Meter,
      currentLocation,
      _fetchLocation!,
    );
    return distM > 100;
  }

  void update(List<RoadSegment> data, LatLng location) {
    _data = data;
    _fetchedAt = DateTime.now();
    _fetchLocation = location;
  }

  void clear() {
    _data = null;
    _fetchedAt = null;
    _fetchLocation = null;
  }
}
