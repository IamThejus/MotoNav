import 'package:geocoding/geocoding.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/services/logger_service.dart';

class SearchResult {
  final String displayName;
  final String shortName;
  final LatLng location;
  final String type;
  final String? category;

  const SearchResult({
    required this.displayName,
    required this.shortName,
    required this.location,
    required this.type,
    this.category,
  });
}

class NominatimService {
  /// Forward search using device's native geocoder (Google on Android).
  /// shortName = what the user typed (preserves the actual place name).
  /// displayName = locality/city context from reverse geocoding.
  Future<List<SearchResult>> search(
    String query, {
    LatLng? viewportCenter,
  }) async {
    if (query.trim().isEmpty) return [];

    try {
      final locations = await locationFromAddress(query);
      if (locations.isEmpty) return [];

      final results = <SearchResult>[];
      final queryTrimmed = query.trim();

      for (final loc in locations.take(5)) {
        try {
          final placemarks = await placemarkFromCoordinates(
            loc.latitude,
            loc.longitude,
          );

          String displayName = queryTrimmed;
          if (placemarks.isNotEmpty) {
            final pm = placemarks.first;
            // Build address context: subLocality, locality, state
            final addressParts = <String>[
              if (pm.subLocality?.isNotEmpty ?? false) pm.subLocality!,
              if (pm.locality?.isNotEmpty ?? false)    pm.locality!,
              if (pm.administrativeArea?.isNotEmpty ?? false)
                pm.administrativeArea!,
            ];
            if (addressParts.isNotEmpty) {
              displayName = addressParts.join(', ');
            }
          }

          results.add(SearchResult(
            shortName:   queryTrimmed,   // user's search text = place name
            displayName: displayName,    // address for context
            location:    LatLng(loc.latitude, loc.longitude),
            type:        'place',
          ));
        } catch (_) {
          // If reverse geocode fails, still add the result with query as both names
          results.add(SearchResult(
            shortName:   queryTrimmed,
            displayName: queryTrimmed,
            location:    LatLng(loc.latitude, loc.longitude),
            type:        'place',
          ));
        }
      }

      appLogger.i('Geocoding "$query": ${results.length} results');
      return results;
    } on NoResultFoundException {
      appLogger.d('No results for "$query"');
      return [];
    } catch (e) {
      appLogger.e('Geocoding search error', error: e);
      return [];
    }
  }

  /// Reverse geocode coordinates to a human-readable address.
  Future<String?> reverseGeocode(LatLng location) async {
    try {
      final placemarks = await placemarkFromCoordinates(
        location.latitude,
        location.longitude,
      );
      if (placemarks.isEmpty) return null;

      final pm = placemarks.first;
      final parts = <String>[
        if (pm.name?.isNotEmpty ?? false)              pm.name!,
        if (pm.subLocality?.isNotEmpty ?? false)       pm.subLocality!,
        if (pm.locality?.isNotEmpty ?? false)          pm.locality!,
        if (pm.administrativeArea?.isNotEmpty ?? false) pm.administrativeArea!,
      ].where((s) => s.isNotEmpty).take(3).toList();

      return parts.isEmpty ? null : parts.join(', ');
    } catch (e) {
      appLogger.e('Reverse geocode error', error: e);
      return null;
    }
  }
}
