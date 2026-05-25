import 'package:latlong2/latlong.dart';
import '../../map/data/nominatim_service.dart';

enum MapStatus { idle, locating, locationDenied, locationPermanentlyDenied, ready }

class MapState {
  final MapStatus status;
  final LatLng? userLocation;
  final SearchResult? destination;
  final String? errorMessage;
  final double heading;   // degrees, 0–360
  final double speedKmh;

  const MapState({
    this.status = MapStatus.idle,
    this.userLocation,
    this.destination,
    this.errorMessage,
    this.heading = 0.0,
    this.speedKmh = 0.0,
  });

  MapState copyWith({
    MapStatus? status,
    LatLng? userLocation,
    SearchResult? destination,
    String? errorMessage,
    double? heading,
    double? speedKmh,
    bool clearDestination = false,
    bool clearError = false,
  }) {
    return MapState(
      status: status ?? this.status,
      userLocation: userLocation ?? this.userLocation,
      destination: clearDestination ? null : (destination ?? this.destination),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      heading: heading ?? this.heading,
      speedKmh: speedKmh ?? this.speedKmh,
    );
  }
}
