import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/config/api_config.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/services/logger_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../features/ble/providers/ble_provider.dart';
import '../../../features/ble/screens/ble_screen.dart';
import '../../../features/navigation/providers/nav_sender_provider.dart';
import '../../../features/navigation/providers/routing_provider.dart';
import '../../../features/offline_maps/screens/download_region_screen.dart';
import '../data/nominatim_service.dart';
import '../models/map_state.dart';
import '../providers/map_provider.dart';
import '../widgets/ble_status_chip.dart';
import '../widgets/search_bar_widget.dart';
import '../widgets/user_location_marker.dart';
import 'search_screen.dart';

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen>
    with TickerProviderStateMixin {
  final _mapController = MapController();
  bool _userPannedAway = false;
  LatLng? _lastCenteredLocation;
  AnimationController? _moveAnim;

  // Created once; TileLayer disposes it when removed from the tree.
  late final _offlineTileProvider =
      FMTCStore('offline').getTileProvider();

  @override
  void dispose() {
    _moveAnim?.dispose();
    _mapController.dispose();
    super.dispose();
  }

  /// Smoothly pan + zoom the map to [location].
  /// [duration] defaults to 700 ms for destination fly-in, pass shorter for GPS tracking.
  void _animateTo(
    LatLng location, {
    double? zoom,
    Duration duration = const Duration(milliseconds: 700),
  }) {
    final camera   = _mapController.camera;
    final fromLat  = camera.center.latitude;
    final fromLng  = camera.center.longitude;
    final fromZoom = camera.zoom;
    final toZoom   = zoom ?? AppConstants.defaultZoom;

    _moveAnim?.dispose();
    _moveAnim = AnimationController(vsync: this, duration: duration);

    final latTween  = Tween<double>(begin: fromLat,  end: location.latitude);
    final lngTween  = Tween<double>(begin: fromLng,  end: location.longitude);
    final zoomTween = Tween<double>(begin: fromZoom, end: toZoom);
    final curve     = CurvedAnimation(
      parent: _moveAnim!,
      curve: Curves.easeInOutCubic,
    );

    _moveAnim!.addListener(() {
      _mapController.move(
        LatLng(latTween.evaluate(curve), lngTween.evaluate(curve)),
        zoomTween.evaluate(curve),
      );
    });

    _moveAnim!.forward();
    _lastCenteredLocation = location;
    _userPannedAway = false;
  }

  void _onMapMoved(MapCamera camera, bool hasGesture) {
    if (hasGesture) {
      _userPannedAway = true;
    }
  }

  Future<void> _openSearch() async {
    final result = await Navigator.of(context).push<SearchResult>(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const SearchScreen(),
        transitionsBuilder: (_, animation, __, child) {
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.05),
              end: Offset.zero,
            ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
            child: FadeTransition(opacity: animation, child: child),
          );
        },
        transitionDuration: const Duration(milliseconds: 220),
      ),
    );

    // Pan to the selected destination so user can see it on the map
    if (result != null && mounted) {
      _userPannedAway = true;
      _animateTo(result.location, zoom: 15.0);
    }
  }

  void _recenterOnUser() {
    final location = ref.read(mapProvider).userLocation;
    if (location != null) {
      _animateTo(location);
    }
  }

  void _openDownloadScreen() {
    final center = ref.read(mapProvider).userLocation ??
        AppConstants.fallbackLocation;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DownloadRegionScreen(initialCenter: center),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mapState = ref.watch(mapProvider);
    ref.watch(navSenderProvider); // keeps BLE packet sender alive

    // Auto-center on first GPS fix; keep following during navigation
    ref.listen<MapState>(mapProvider, (prev, next) {
      if (next.userLocation == null) return;
      final isNavigating = ref.read(routeProvider).isNavigating;
      if (isNavigating) {
        // Follow user during navigation with a short smooth step
        _userPannedAway = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _animateTo(
            next.userLocation!,
            zoom: AppConstants.navigationZoom,
            duration: const Duration(milliseconds: 300),
          );
        });
      } else if (!_userPannedAway) {
        final shouldCenter = prev?.userLocation == null || _lastCenteredLocation == null;
        if (shouldCenter) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _animateTo(next.userLocation!);
          });
        }
      }
    });

    final routeState = ref.watch(routeProvider);
    final bleState = ref.watch(bleProvider);

    // Zoom to nav zoom and lock follow when navigation starts;
    // reset map rotation back to north-up when navigation stops.
    ref.listen<RouteState>(routeProvider, (prev, next) {
      if (next.isNavigating && !(prev?.isNavigating ?? false)) {
        final location = ref.read(mapProvider).userLocation;
        if (location != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _animateTo(location, zoom: AppConstants.navigationZoom);
            // Don't wait for the next compass tick — apply current heading now
            final headingAsync = ref.read(headingProvider);
            appLogger.i(
              'Nav started — headingProvider state: '
              'isLoading=${headingAsync.isLoading} '
              'hasValue=${headingAsync.hasValue} '
              'hasError=${headingAsync.hasError} '
              'value=${headingAsync.valueOrNull}',
            );
            final heading = headingAsync.valueOrNull;
            if (heading != null) {
              _mapController.rotate(-heading);
            }
          });
        }
      } else if (!next.isNavigating && (prev?.isNavigating ?? false)) {
        // Navigation stopped — snap back to north-up
        _mapController.rotate(0.0);
      }
    });

    // Heading-up: rotate the map so the direction of travel always points to
    // the top of the screen.  Only active while navigating; `_mapController
    // .rotate()` only changes orientation, it doesn't affect the pan/zoom
    // animation driven by _animateTo, so both can run independently.
    ref.listen<AsyncValue<double>>(headingProvider, (_, next) {
      if (!mounted) return;
      final heading = next.valueOrNull;
      if (heading == null) return;
      if (!ref.read(routeProvider).isNavigating) return;
      _mapController.rotate(-heading);
    });

    return Scaffold(
      backgroundColor: AppTheme.surface,
      body: Stack(
        children: [
          // ── Map ────────────────────────────────────────────────────────────
          _buildMap(mapState, routeState),

          // ── Top overlay ────────────────────────────────────────────────────
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // BLE status + app name row
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceCard.withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          'MotoNav',
                          style: TextStyle(
                            color: AppTheme.onSurface,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(
                          Icons.download_for_offline_rounded,
                          color: AppTheme.onSurfaceMuted,
                          size: 22,
                        ),
                        onPressed: _openDownloadScreen,
                        tooltip: 'Download area for offline use',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                      const SizedBox(width: 10),
                      BleStatusChip(
                        connectionState: switch (bleState.status) {
                          BleStatus.connected => BleConnectionState.connected,
                          BleStatus.connecting => BleConnectionState.connecting,
                          _ => BleConnectionState.disconnected,
                        },
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const BleScreen(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Search bar
                  SearchBarWidget(
                    onTap: _openSearch,
                    destinationName: mapState.destination?.shortName,
                  ),
                ],
              ),
            ),
          ),

          // ── Location status overlays ────────────────────────────────────
          if (mapState.status == MapStatus.locating)
            const Positioned(
              bottom: 100,
              left: 0,
              right: 0,
              child: _StatusBanner(
                icon: Icons.gps_fixed_rounded,
                message: 'Getting your location...',
              ),
            ),

          if (mapState.status == MapStatus.locationDenied ||
              mapState.status == MapStatus.locationPermanentlyDenied)
            Positioned(
              bottom: 100,
              left: 16,
              right: 16,
              child: _PermissionBanner(
                message: mapState.errorMessage ?? 'Location unavailable',
                isPermanent:
                    mapState.status == MapStatus.locationPermanentlyDenied,
                onRetry: () => ref.read(mapProvider.notifier).retryPermission(),
                onSettings: () =>
                    ref.read(mapProvider.notifier).openSettings(),
              ),
            ),

          // ── Bottom action area ──────────────────────────────────────────
          if (mapState.destination != null)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _DestinationPanel(
                destinationName: mapState.destination!.shortName,
                routeState: routeState,
                onClear: () {
                  ref.read(mapProvider.notifier).clearDestination();
                  ref.read(routeProvider.notifier).stopNavigation();
                },
                onStartNavigation: () {
                  final origin = mapState.userLocation;
                  final dest = mapState.destination?.location;
                  if (origin != null && dest != null) {
                    ref.read(routeProvider.notifier).calculateRoute(origin, dest);
                  }
                },
                onStopNavigation: () {
                  ref.read(routeProvider.notifier).stopNavigation();
                  final location = ref.read(mapProvider).userLocation;
                  if (location != null) _animateTo(location);
                },
              ),
            ),

          // ── Recenter FAB ────────────────────────────────────────────────
          if (_userPannedAway)
            Positioned(
              right: 16,
              bottom: mapState.destination != null ? 130 : 40,
              child: FloatingActionButton.small(
                onPressed: _recenterOnUser,
                backgroundColor: AppTheme.surfaceCard,
                foregroundColor: AppTheme.onSurface,
                child: const Icon(Icons.my_location_rounded, size: 20),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMap(MapState mapState, RouteState routeState) {
    final center = mapState.userLocation ?? AppConstants.fallbackLocation;

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: center,
        initialZoom: AppConstants.defaultZoom,
        onMapEvent: (event) {
          if (event is MapEventMoveStart) {
            _onMapMoved(event.camera, event.source != MapEventSource.mapController);
          }
        },
        backgroundColor: AppTheme.surface,
      ),
      children: [
        // Tile layer — FMTC serves cached tiles offline, falls back to network
        TileLayer(
          urlTemplate: ApiConfig.osmTileUrl,
          userAgentPackageName: 'com.thejus.motonav',
          tileProvider: _offlineTileProvider,
          tileBuilder: _darkTileBuilder,
          errorTileCallback: (tile, error, stackTrace) {},
        ),

        // Route polyline
        if (routeState.route != null)
          PolylineLayer(
            polylines: [
              Polyline(
                points: routeState.route!.polyline,
                color: AppTheme.routeColor,
                strokeWidth: 5.0,
                borderColor: AppTheme.primary.withValues(alpha: 0.3),
                borderStrokeWidth: 2.0,
              ),
            ],
          ),

        // User location marker — heading read internally from headingProvider.
        // isHeadingUpMode keeps the arrow screen-up when the map is already
        // rotated to show the direction of travel at the top.
        if (mapState.userLocation != null)
          UserLocationMarker(
            location: mapState.userLocation!,
            isHeadingUpMode: routeState.isNavigating,
          ),

        // Destination marker
        if (mapState.destination != null)
          DestinationMarker(location: mapState.destination!.location),
      ],
    );
  }

  /// Apply a dark overlay to OSM tiles to match the app theme.
  Widget _darkTileBuilder(
    BuildContext context,
    Widget tileWidget,
    TileImage tile,
  ) {
    return ColorFiltered(
      colorFilter: const ColorFilter.matrix(<double>[
        0.28, 0,    0,    0, 0,
        0,    0.28, 0,    0, 0,
        0,    0,    0.30, 0, 0,
        0,    0,    0,    1, 0,
      ]),
      child: tileWidget,
    );
  }
}

// ── Supporting widgets ────────────────────────────────────────────────────────

class _StatusBanner extends StatelessWidget {
  final IconData icon;
  final String message;

  const _StatusBanner({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.surfaceCard.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 12,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(AppTheme.primary),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              message,
              style: const TextStyle(
                color: AppTheme.onSurface,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PermissionBanner extends StatelessWidget {
  final String message;
  final bool isPermanent;
  final VoidCallback onRetry;
  final VoidCallback onSettings;

  const _PermissionBanner({
    required this.message,
    required this.isPermanent,
    required this.onRetry,
    required this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.error.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.location_off_rounded,
                  color: AppTheme.error, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    color: AppTheme.onSurface,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (!isPermanent)
                Expanded(
                  child: OutlinedButton(
                    onPressed: onRetry,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.primary,
                      side: const BorderSide(color: AppTheme.primary),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text('Retry'),
                  ),
                ),
              if (!isPermanent) const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: onSettings,
                  child: const Text('Open Settings'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DestinationPanel extends StatelessWidget {
  final String destinationName;
  final RouteState routeState;
  final VoidCallback onClear;
  final VoidCallback onStartNavigation;
  final VoidCallback onStopNavigation;

  const _DestinationPanel({
    required this.destinationName,
    required this.routeState,
    required this.onClear,
    required this.onStartNavigation,
    required this.onStopNavigation,
  });

  @override
  Widget build(BuildContext context) {
    final isLoading = routeState.status == RouteStatus.loading;
    final route = routeState.route;

    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        20 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: const BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black45,
            blurRadius: 20,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.flag_rounded, color: AppTheme.primary, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  destinationName,
                  style: const TextStyle(
                    color: AppTheme.onSurface,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded,
                    color: AppTheme.onSurfaceMuted, size: 20),
                onPressed: onClear,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),

          // Route info row
          if (route != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.straighten_rounded,
                    color: AppTheme.onSurfaceMuted, size: 14),
                const SizedBox(width: 4),
                Text(
                  route.distanceLabel,
                  style: const TextStyle(
                      color: AppTheme.onSurfaceMuted, fontSize: 13),
                ),
                const SizedBox(width: 16),
                const Icon(Icons.schedule_rounded,
                    color: AppTheme.onSurfaceMuted, size: 14),
                const SizedBox(width: 4),
                Text(
                  route.durationLabel,
                  style: const TextStyle(
                      color: AppTheme.onSurfaceMuted, fontSize: 13),
                ),
              ],
            ),
          ],

          // Error message
          if (routeState.status == RouteStatus.error &&
              routeState.errorMessage != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.warning_amber_rounded,
                    color: AppTheme.error, size: 14),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    routeState.errorMessage!,
                    style: const TextStyle(
                        color: AppTheme.error, fontSize: 12),
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: 14),
          if (routeState.isNavigating)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onStopNavigation,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.error,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.stop_rounded, size: 18),
                label: const Text('Stop Navigation'),
              ),
            )
          else
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: isLoading ? null : onStartNavigation,
                icon: isLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.black,
                        ),
                      )
                    : const Icon(Icons.navigation_rounded, size: 18),
                label: const Text('Start Navigation'),
              ),
            ),
        ],
      ),
    );
  }
}
