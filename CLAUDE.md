# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

---

## What this project is

MotoNav is a Flutter Android app that acts as a navigation companion for an
ESP32-C3 microcontroller with a GC9A01 240×240 circular display, connected
over BLE. The phone does GPS, routing, and step tracking, then sends compact
turn-by-turn packets to the ESP32 over BLE every GPS tick.

---

## Common commands

```bash
# Run on a connected Android device (no API key needed — OSRM is free)
flutter run

# Run with GraphHopper as the routing backend
flutter run --dart-define=GRAPH_HOPPER_API_KEY=your_key_here

# Build release APK
flutter build apk --release

# Analyze (lint)
flutter analyze

# Run tests
flutter test

# Run a single test file
flutter test test/path/to/foo_test.dart

# Regenerate code (freezed / json_serializable / riverpod_generator)
dart run build_runner build --delete-conflicting-outputs
```

---

## Tech stack

| Layer           | Choice                          |
|-----------------|---------------------------------|
| Framework       | Flutter (Android only)          |
| State           | Riverpod (StateNotifier pattern)|
| Map             | flutter_map + OSM tiles         |
| Routing         | OSRM (default, free) / GraphHopper (opt-in via dart-define) |
| Search          | Nominatim (OSM, no key needed)  |
| Road geometry   | Overpass API (cached, ~400m radius) |
| Offline tiles   | flutter_map_tile_caching (FMTC) with ObjectBox backend |
| GPS             | geolocator                      |
| BLE             | flutter_blue_plus               |
| Background      | flutter_background_service      |
| Min SDK         | 26 (Android 8)                  |
| Target SDK      | 34 (Android 14)                 |
| Package         | com.thejus.motonav              |

---

## Phase status

| Phase | Status      | Description                                           |
|-------|-------------|-------------------------------------------------------|
| 1     | ✅ Complete  | Map + GPS + Nominatim search + autocomplete           |
| 2     | ✅ Complete  | Routing (OSRM) + route polyline + turn-by-turn steps  |
| 3     | ✅ Complete  | BLE scan + connect + auto-reconnect + packet writes   |
| 4     | ✅ Complete  | Overpass road geometry + in-memory cache (3 min TTL)  |
| 5     | ✅ Complete  | BLE packet generation + nav sender (per-GPS-tick)     |
| –     | ✅ Complete  | Offline map tile download (FMTC, zoom 13–17)          |
| 6     | ⏳ Pending   | Background navigation service (foreground svc)        |
| 7     | ⏳ Pending   | Minimap preview widget on home screen                 |

---

## Data flow — full pipeline

```
Phone GPS
  ↓
GpsService (stream; 1 s interval nav mode / 2 s idle, 10 m distance filter)
  ↓
MapNotifier (Riverpod) → MapScreen renders location
  ↓
RouteNotifier.calculateRoute() → OsrmService → route polyline + steps
  ↓
navSenderProvider (Provider<void>):
  • listens to RouteState → switches GPS to fast mode when navigating
  • listens to MapState (GPS tick) → calls RouteNotifier.updateProgress()
    → builds TN packet via PacketBuilder
    → writes to ESP32 via BleNotifier.writePacket()
  ↓
BleService.writePacket() → flutter_blue_plus characteristic write
  ↓
ESP32 renders turn info on GC9A01 display
```

**Important**: `navSenderProvider` must be watched (not just read) in `MapScreen`
to keep it alive. It is the single orchestration point for navigation.

`RoadNotifier` runs in parallel — triggered by `MapState` GPS ticks, fetches
Overpass road segments when user moves >100 m or cache expires (3 min TTL).

`CoordinateNormalizer` (`lib/features/navigation/services/coordinate_normalizer.dart`)
converts `LatLng` points to signed pixel offsets on the 240×240 ESP32 display,
applying heading-up rotation so the rider's direction always points to display top.
Scale: `displayCenter / overpassQueryRadiusMeters` = 0.3 px/m.

---

## BLE packet format — FIXED, do not change

The ESP32 firmware expects this exact 11-byte turn-by-turn packet:

```
[0]     'T'  (0x54)
[1]     'N'  (0x4E)
[2]     current turn sign + 10  (uint8, range 0-20)
[3..4]  distance to turn (uint16 BE, units = ×10 m)
[5..6]  remaining distance (uint16 BE, units = km)
[7]     next turn sign + 10  (uint8)
[8]     speed km/h (uint8)
[9..10] ETA minutes (uint16 BE)
```

Turn sign encoding (GraphHopper / OSRM sign values, stored as `sign + 10`):
- `-4` = U-turn, `-3` = sharp left, `-2` = left, `-1` = slight left
- `0` = straight, `1` = slight right, `2` = right, `3` = sharp right
- `4` = arrive, `6` = roundabout

**Do not change this format** — the ESP32 firmware depends on it.

---

## Routing service switching

The active routing backend is set in `routing_provider.dart`:

```dart
final routingServiceProvider = Provider<RoutingService>((ref) {
  return OsrmService();   // ← swap to GraphHopperService() here
});
```

- `OsrmService` — free, no key, uses `router.project-osrm.org`
- `GraphHopperService` — requires `--dart-define=GRAPH_HOPPER_API_KEY=<key>`,
  reads key via `ApiConfig.graphHopperApiKey`

Both implement the same `RoutingService` interface.

---

## Offline maps

Tiles are cached with `flutter_map_tile_caching` using the ObjectBox backend.
The FMTC store is named `'offline'` throughout the codebase.

Initialization happens **before** `ProviderScope` in `main()`:
```dart
await FMTCObjectBoxBackend().initialise();
await FMTCStore('offline').manage.create();
```
If FMTC init fails the app still launches — offline maps are silently disabled.

`DownloadRegionScreen` (`lib/features/offline_maps/screens/`) lets the user
pan to an area and download tiles at zoom 13–17. `MapScreen`'s `TileLayer` uses
`FMTCStore('offline').getTileProvider()` which serves cached tiles and falls
back to network automatically.

---

## Key constants — do not hardcode these anywhere else

```dart
// lib/core/constants/app_constants.dart
fallbackLocation       = LatLng(9.9312, 76.2673)  // Kochi, Kerala
defaultZoom            = 15.0
navigationZoom         = 17.0
searchResultZoom       = 14.0

bleDeviceName          = 'MotoNav'
bleServiceUuid         = '12345678-1234-1234-1234-123456789abc'
bleCharUuid            = 'abcd1234-5678-90ab-cdef-123456789abc'

displaySize            = 240
displayCenter          = 120

gpsFastIntervalMs      = 2000   // idle GPS (0.5 Hz, 10 m distance filter)
gpsNavigationIntervalMs = 1000  // nav GPS  (1 Hz,   no distance filter)

nominatimDebounceMs    = 400
nominatimMaxResults    = 7

// lib/core/config/api_config.dart
overpassQueryRadiusMeters = 400  // NOTE: lives in ApiConfig, not AppConstants
```

---

## Riverpod patterns

```dart
// Service provider
final myServiceProvider = Provider<MyService>((ref) {
  final s = MyService();
  ref.onDispose(s.dispose);
  return s;
});

// State notifier
final myProvider = StateNotifierProvider<MyNotifier, MyState>((ref) {
  return MyNotifier(ref.watch(myServiceProvider));
});
```

- `ref.watch` in build methods; `ref.read` in callbacks/events.
- `autoDispose` for screen-scoped providers (e.g. `searchProvider`).
- Side-effect-only providers (like `navSenderProvider`) use `Provider<void>` and
  must be watched somewhere to stay alive.

---

## Phase 6 — Background navigation service

```
lib/features/navigation/services/
  nav_background_service.dart   # flutter_background_service foreground wrapper
```

Should promote `navSenderProvider` logic into a foreground service so navigation
continues when the app is backgrounded. GPS, BLE writes, and step tracking all
need to run in the background isolate.

---

## Rules — always follow these

1. Never hardcode API keys, UUIDs, or coordinates — use `AppConstants` and `ApiConfig`.
2. Never break the BLE packet format — the ESP32 firmware depends on it.
3. Always use Riverpod (`ref.watch` / `ref.read`) — no `setState` in feature screens.
4. Always handle loading, error, and empty states in UI.
5. Feature-first folder structure — new features go in `lib/features/<name>/`.
6. New services go in `lib/core/services/` (shared) or `lib/features/<name>/data/` (feature-specific).
7. Log with `appLogger` from `logger_service.dart` — never use `print()`.
8. Dispose streams and subscriptions in `dispose()` — BleNotifier and GpsService both hold subscriptions.
9. Always use the FMTC store name `'offline'` for tile caching — do not create additional stores.
