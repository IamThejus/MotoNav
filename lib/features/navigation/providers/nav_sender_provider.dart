import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/logger_service.dart';
import '../../ble/providers/ble_provider.dart';
import '../../map/models/map_state.dart';
import '../../map/providers/map_provider.dart';
import '../services/packet_builder.dart';
import 'routing_provider.dart';

/// Side-effect provider that:
///   - Switches GPS to fast mode (1 s) when navigation starts, slow on stop
///   - Calls updateProgress() on every GPS tick to advance step tracking
///   - Builds and sends a 9-byte turn-by-turn BLE packet every GPS tick
///
/// Watch this in map_screen to keep it alive.
final navSenderProvider = Provider<void>((ref) {
  // Switch GPS rate when navigation state changes
  ref.listen<RouteState>(routeProvider, (prev, next) {
    final wasNavigating = prev?.isNavigating ?? false;
    if (next.isNavigating && !wasNavigating) {
      ref.read(mapProvider.notifier).setFastGps(true);
    } else if (!next.isNavigating && wasNavigating) {
      ref.read(mapProvider.notifier).setFastGps(false);
    }
  });

  // Send BLE packet on every GPS tick during navigation
  ref.listen<MapState>(mapProvider, (_, mapState) {
    final location = mapState.userLocation;
    if (location == null) return;

    final routeState = ref.read(routeProvider);
    if (!routeState.isNavigating || routeState.route == null) return;

    // Advance step index and recalculate distances
    ref.read(routeProvider.notifier).updateProgress(location);

    final bleState = ref.read(bleProvider);
    if (!bleState.isConnected) return;

    // Read updated state after updateProgress
    final updated = ref.read(routeProvider);
    final currentStep = updated.currentStep;
    final nextStep = updated.nextStep;

    final packet = PacketBuilder.buildTurnPacket(
      currentSign: currentStep?.sign ?? 0,
      distanceToTurnMeters: updated.distanceToTurnMeters,
      remainingDistanceMeters: updated.remainingDistanceMeters,
      nextSign: nextStep?.sign ?? 0,
      speedKmh: mapState.speedKmh,
    );

    appLogger.d(
      'NAV turn: step=${updated.currentStepIndex} '
      'sign=${currentStep?.sign} dist=${updated.distanceToTurnMeters}m '
      'remaining=${(updated.remainingDistanceMeters / 1000).toStringAsFixed(1)}km '
      'next=${nextStep?.sign} spd=${mapState.speedKmh.round()}',
    );

    ref.read(bleProvider.notifier).writePacket(packet);
  });
});
