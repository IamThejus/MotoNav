import 'dart:async';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/services/gps_service.dart';
import '../../../core/services/logger_service.dart';
import '../../../core/services/permission_service.dart';
import '../data/nominatim_service.dart';
import '../models/map_state.dart';

// ---------------------------------------------------------------------------
// Service providers
// ---------------------------------------------------------------------------

final gpsServiceProvider = Provider<GpsService>((ref) {
  final service = GpsService();
  ref.onDispose(service.dispose);
  return service;
});

final permissionServiceProvider = Provider<PermissionService>(
  (_) => PermissionService(),
);

final nominatimServiceProvider = Provider<NominatimService>(
  (_) => NominatimService(),
);

// ---------------------------------------------------------------------------
// Heading provider — compass only, isolated so only the arrow widget rebuilds.
// Emits the very first compass reading immediately so listeners have a value,
// then throttles to ≥1° changes thereafter (raw sensor is ~50 Hz).
// ---------------------------------------------------------------------------

final headingProvider = StreamProvider<double>((ref) {
  final events = FlutterCompass.events;
  if (events == null) {
    appLogger.w('Compass: FlutterCompass.events is null — no magnetometer?');
    return const Stream.empty();
  }
  appLogger.i('Compass: subscribing to FlutterCompass.events');

  // Explicit controller + subscription instead of a .where/.map chain.
  // The chained-stream approach silently lost emissions between the filter
  // and Riverpod's listener on this device — the filter logged "first heading
  // = 84.6°" but the StreamProvider state remained AsyncLoading forever.
  // With an explicit controller, every controller.add() is directly visible
  // to Riverpod's listener.
  final controller = StreamController<double>.broadcast();
  double? lastEmitted;
  var emitCount = 0;

  final sub = events.listen((event) {
    final h = event.heading;
    if (h == null) return;
    final normalized = (h + 360) % 360;

    if (lastEmitted == null) {
      lastEmitted = normalized;
      emitCount++;
      appLogger.i('Compass: first emit = ${normalized.toStringAsFixed(1)}°');
      controller.add(normalized);
      return;
    }

    var diff = (normalized - lastEmitted!).abs();
    if (diff > 180) diff = 360 - diff;
    if (diff < 1.0) return;

    lastEmitted = normalized;
    emitCount++;
    if (emitCount <= 5 || emitCount % 20 == 0) {
      appLogger.d('Compass: emit #$emitCount = ${normalized.toStringAsFixed(1)}°');
    }
    controller.add(normalized);
  });

  ref.onDispose(() {
    appLogger.w('Compass: disposing headingProvider');
    sub.cancel();
    controller.close();
  });

  return controller.stream;
});

// ---------------------------------------------------------------------------
// Map state notifier
// ---------------------------------------------------------------------------

class MapNotifier extends StateNotifier<MapState> {
  final GpsService _gps;
  final PermissionService _permissions;
  StreamSubscription<Position>? _locationSub;

  MapNotifier(this._gps, this._permissions) : super(const MapState()) {
    _init();
  }

  Future<void> _init() async {
    state = state.copyWith(status: MapStatus.locating);

    final permStatus = await _permissions.requestLocationPermissions();

    switch (permStatus) {
      case PermissionStatus.granted:
        await _startGps();
      case PermissionStatus.denied:
        state = state.copyWith(
          status: MapStatus.locationDenied,
          errorMessage: 'Location permission denied. Tap to retry.',
        );
      case PermissionStatus.permanentlyDenied:
        state = state.copyWith(
          status: MapStatus.locationPermanentlyDenied,
          errorMessage:
              'Location permission permanently denied. Enable it in Settings.',
        );
    }
  }

  Future<void> _startGps({bool fastMode = false}) async {
    // Get immediate fix
    final initial = await _gps.getCurrentLocation();
    state = state.copyWith(
      status: MapStatus.ready,
      userLocation: initial ?? AppConstants.fallbackLocation,
    );

    // Start continuous stream
    _gps.startTracking(fastMode: fastMode);
    _locationSub = _gps.positionStream.listen((position) {
      state = state.copyWith(
        userLocation: LatLng(position.latitude, position.longitude),
        // heading is driven by compass, not GPS — see _startCompass()
        speedKmh: (position.speed * 3.6).clamp(0.0, 300.0),
      );
    });
  }

  void setFastGps(bool fast) {
    _gps.startTracking(fastMode: fast);
  }

  Future<void> retryPermission() async {
    state = state.copyWith(status: MapStatus.locating, clearError: true);
    await _init();
  }

  Future<void> openSettings() async {
    await _permissions.openSettings();
  }

  void setDestination(SearchResult result) {
    appLogger.i('Destination set: ${result.shortName}');
    state = state.copyWith(destination: result);
  }

  void clearDestination() {
    state = state.copyWith(clearDestination: true);
  }

  @override
  void dispose() {
    _locationSub?.cancel();
    super.dispose();
  }
}

final mapProvider = StateNotifierProvider<MapNotifier, MapState>((ref) {
  return MapNotifier(
    ref.watch(gpsServiceProvider),
    ref.watch(permissionServiceProvider),
  );
});

// ---------------------------------------------------------------------------
// Search state notifier
// ---------------------------------------------------------------------------

enum SearchStatus { idle, loading, results, empty, error }

class SearchState {
  final SearchStatus status;
  final List<SearchResult> results;
  final String query;
  final String? errorMessage;

  const SearchState({
    this.status = SearchStatus.idle,
    this.results = const [],
    this.query = '',
    this.errorMessage,
  });

  SearchState copyWith({
    SearchStatus? status,
    List<SearchResult>? results,
    String? query,
    String? errorMessage,
  }) {
    return SearchState(
      status: status ?? this.status,
      results: results ?? this.results,
      query: query ?? this.query,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

class SearchNotifier extends StateNotifier<SearchState> {
  final NominatimService _nominatim;
  Timer? _debounce;

  SearchNotifier(this._nominatim) : super(const SearchState());

  void onQueryChanged(String query, {LatLng? userLocation}) {
    _debounce?.cancel();

    if (query.trim().isEmpty) {
      state = const SearchState();
      return;
    }

    state = state.copyWith(status: SearchStatus.loading, query: query);

    _debounce = Timer(
      const Duration(milliseconds: 400),
      () => _search(query, userLocation: userLocation),
    );
  }

  Future<void> _search(String query, {LatLng? userLocation}) async {
    try {
      final results = await _nominatim.search(
        query,
        viewportCenter: userLocation,
      );

      if (!mounted) return;

      if (results.isEmpty) {
        state = state.copyWith(status: SearchStatus.empty, results: []);
      } else {
        state = state.copyWith(
          status: SearchStatus.results,
          results: results,
        );
      }
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(
        status: SearchStatus.error,
        errorMessage: 'Search failed. Check your connection.',
      );
    }
  }

  void clear() {
    _debounce?.cancel();
    state = const SearchState();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}

final searchProvider =
    StateNotifierProvider.autoDispose<SearchNotifier, SearchState>((ref) {
  return SearchNotifier(ref.watch(nominatimServiceProvider));
});
