import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/services/logger_service.dart';
import '../data/osrm_service.dart';
import '../data/routing_service.dart';
import '../models/route_model.dart';

// ---------------------------------------------------------------------------
// Service provider
// ---------------------------------------------------------------------------

final routingServiceProvider = Provider<RoutingService>((ref) {
  return OsrmService();
});

// ---------------------------------------------------------------------------
// Route state
// ---------------------------------------------------------------------------

enum RouteStatus { idle, loading, loaded, error }

class RouteState {
  final RouteStatus status;
  final RouteResult? route;
  final String? errorMessage;
  final bool isNavigating;

  // Navigation progress — updated every GPS tick via updateProgress()
  final int currentStepIndex;
  final int distanceToTurnMeters;    // metres to the next turn point
  final int remainingDistanceMeters; // total remaining metres to destination

  const RouteState({
    this.status = RouteStatus.idle,
    this.route,
    this.errorMessage,
    this.isNavigating = false,
    this.currentStepIndex = 0,
    this.distanceToTurnMeters = 0,
    this.remainingDistanceMeters = 0,
  });

  RouteStep? get currentStep =>
      (route != null && currentStepIndex < route!.steps.length)
          ? route!.steps[currentStepIndex]
          : null;

  RouteStep? get nextStep =>
      (route != null && currentStepIndex + 1 < route!.steps.length)
          ? route!.steps[currentStepIndex + 1]
          : null;

  RouteState copyWith({
    RouteStatus? status,
    RouteResult? route,
    String? errorMessage,
    bool? isNavigating,
    int? currentStepIndex,
    int? distanceToTurnMeters,
    int? remainingDistanceMeters,
    bool clearRoute = false,
    bool clearError = false,
  }) {
    return RouteState(
      status: status ?? this.status,
      route: clearRoute ? null : (route ?? this.route),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      isNavigating: isNavigating ?? this.isNavigating,
      currentStepIndex: currentStepIndex ?? this.currentStepIndex,
      distanceToTurnMeters: distanceToTurnMeters ?? this.distanceToTurnMeters,
      remainingDistanceMeters:
          remainingDistanceMeters ?? this.remainingDistanceMeters,
    );
  }
}

// ---------------------------------------------------------------------------
// Route notifier
// ---------------------------------------------------------------------------

class RouteNotifier extends StateNotifier<RouteState> {
  final RoutingService _routing;
  static const _dist = Distance();
  static const _advanceThresholdM = 25.0; // auto-advance step within 25 m

  RouteNotifier(this._routing) : super(const RouteState());

  Future<void> calculateRoute(LatLng origin, LatLng destination) async {
    state = state.copyWith(status: RouteStatus.loading, clearError: true);

    try {
      final result = await _routing.getRoute(
        origin: origin,
        destination: destination,
      );
      appLogger.i(
        'Route calculated: ${result.distanceLabel}, ${result.durationLabel}',
      );
      state = state.copyWith(
        status: RouteStatus.loaded,
        route: result,
        isNavigating: true,
        currentStepIndex: 0,
        distanceToTurnMeters: result.distanceMeters.round(),
        remainingDistanceMeters: result.distanceMeters.round(),
      );
    } catch (e) {
      appLogger.e('Route calculation failed', error: e);
      state = state.copyWith(
        status: RouteStatus.error,
        errorMessage: e.toString().replaceFirst('Exception: ', ''),
        clearRoute: true,
        isNavigating: false,
      );
    }
  }

  /// Called on every GPS tick to advance the step index and recalculate
  /// distances. Safe to call frequently — exits immediately when not navigating.
  void updateProgress(LatLng location) {
    if (!state.isNavigating || state.route == null) return;
    final steps = state.route!.steps;
    if (steps.isEmpty) return;

    var idx = state.currentStepIndex;

    // Advance past steps whose turn point we've already passed
    while (idx < steps.length - 1) {
      final d = _dist.as(LengthUnit.Meter, location, steps[idx].point);
      if (d < _advanceThresholdM) {
        idx++;
      } else {
        break;
      }
    }

    final distToTurn =
        _dist.as(LengthUnit.Meter, location, steps[idx].point).round();

    // Remaining = dist to current turn point
    //           + distance of the current step (turn point → next waypoint)
    //           + all subsequent step distances
    // Loop starts at idx (not idx+1) so the current step's distance is included.
    // Stops before the last (arrive) step which has distanceMeters = 0 anyway.
    var remaining = distToTurn;
    for (int i = idx; i < steps.length - 1; i++) {
      remaining += steps[i].distanceMeters.round();
    }

    if (idx != state.currentStepIndex ||
        (distToTurn - state.distanceToTurnMeters).abs() > 2) {
      state = state.copyWith(
        currentStepIndex: idx,
        distanceToTurnMeters: distToTurn,
        remainingDistanceMeters: remaining,
      );
    }
  }

  void stopNavigation() {
    state = const RouteState();
  }

  void clearRoute() {
    state = const RouteState();
  }
}

final routeProvider = StateNotifierProvider<RouteNotifier, RouteState>((ref) {
  return RouteNotifier(ref.watch(routingServiceProvider));
});
