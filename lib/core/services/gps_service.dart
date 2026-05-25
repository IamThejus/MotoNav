import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../services/logger_service.dart';

class GpsService {
  StreamSubscription<Position>? _subscription;
  final _locationController = StreamController<LatLng>.broadcast();
  final _positionController = StreamController<Position>.broadcast();
  LatLng? _lastKnownLocation;

  Stream<LatLng> get locationStream => _locationController.stream;
  Stream<Position> get positionStream => _positionController.stream;
  LatLng? get lastKnownLocation => _lastKnownLocation;

  /// Start streaming GPS updates.
  /// [fastMode] uses higher frequency — for active navigation.
  void startTracking({bool fastMode = false}) {
    _subscription?.cancel();

    final settings = AndroidSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: fastMode ? 0 : 10, // 0 = time-only in nav mode
      intervalDuration: Duration(
        milliseconds: fastMode ? 1000 : 2000,
      ),
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationText: 'MotoNav is tracking your location',
        notificationTitle: 'MotoNav Active',
        enableWakeLock: true,
      ),
    );

    _subscription = Geolocator.getPositionStream(
      locationSettings: settings,
    ).listen(
      (position) {
        final loc = LatLng(position.latitude, position.longitude);
        _lastKnownLocation = loc;
        _locationController.add(loc);
        _positionController.add(position);
        appLogger.d(
          'GPS: ${loc.latitude.toStringAsFixed(6)}, '
          '${loc.longitude.toStringAsFixed(6)} | '
          'accuracy: ${position.accuracy.toStringAsFixed(1)}m | '
          'heading: ${position.heading.toStringAsFixed(1)}°',
        );
      },
      onError: (Object e) {
        appLogger.e('GPS stream error', error: e);
      },
    );

    appLogger.i('GPS tracking started (fastMode: $fastMode)');
  }

  void stopTracking() {
    _subscription?.cancel();
    _subscription = null;
    appLogger.i('GPS tracking stopped');
  }

  /// Get a single position update — used at startup before stream begins.
  Future<LatLng?> getCurrentLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
      final loc = LatLng(position.latitude, position.longitude);
      _lastKnownLocation = loc;
      appLogger.i('Initial GPS fix: ${loc.latitude}, ${loc.longitude}');
      return loc;
    } catch (e) {
      appLogger.w('Could not get initial GPS fix: $e');
      return null;
    }
  }

  void dispose() {
    _subscription?.cancel();
    _locationController.close();
    _positionController.close();
  }
}
