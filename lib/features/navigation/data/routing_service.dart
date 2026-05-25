import 'package:latlong2/latlong.dart';
import '../models/route_model.dart';

abstract class RoutingService {
  Future<RouteResult> getRoute({
    required LatLng origin,
    required LatLng destination,
    String profile = 'car',
  });
}
