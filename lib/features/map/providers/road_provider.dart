import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/services/logger_service.dart';
import '../data/overpass_service.dart';
import '../data/road_cache.dart';
import '../models/map_state.dart';
import '../models/road_segment.dart';
import 'map_provider.dart';

class RoadNotifier extends StateNotifier<List<RoadSegment>> {
  final OverpassService _overpass;
  final RoadCache _cache = RoadCache();
  bool _fetching = false;

  RoadNotifier(this._overpass) : super(const []);

  Future<void> maybeRefresh(LatLng location) async {
    if (_fetching || !_cache.needsRefresh(location)) return;
    _fetching = true;
    try {
      final segments = await _overpass.getRoads(location);
      if (mounted) {
        _cache.update(segments, location);
        state = segments;
      }
    } catch (e) {
      appLogger.w('Road refresh failed: $e');
    } finally {
      _fetching = false;
    }
  }
}

final overpassServiceProvider = Provider<OverpassService>((_) => OverpassService());

final roadProvider = StateNotifierProvider<RoadNotifier, List<RoadSegment>>((ref) {
  final notifier = RoadNotifier(ref.watch(overpassServiceProvider));

  // Trigger immediately if GPS is already available
  final initialLocation = ref.read(mapProvider).userLocation;
  if (initialLocation != null) notifier.maybeRefresh(initialLocation);

  // Refresh whenever user location changes
  ref.listen<MapState>(mapProvider, (_, next) {
    final location = next.userLocation;
    if (location != null) notifier.maybeRefresh(location);
  });

  return notifier;
});
