import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class GoogleGeocodingService {
  // ── No API key here. The Edge Function holds it. ─────────

  final SupabaseClient _supabase = Supabase.instance.client;

  // ── In-memory cache (rounded to ~11m precision) ─────────
  static final Map<String, ({String? address, String? barangay})> _cache = {};

  // ============================================================
  // PUBLIC API (unchanged signatures — drop-in replacement)
  // ============================================================

  /// Returns the full formatted address for the given coordinates.
  Future<String?> getFullAddress({
    required double latitude,
    required double longitude,
  }) async {
    final result = await reverseGeocode(
      latitude: latitude,
      longitude: longitude,
    );
    return result.address;
  }

  /// Returns the barangay name for the given coordinates.
  Future<String?> getBarangay({
    required double latitude,
    required double longitude,
  }) async {
    final result = await reverseGeocode(
      latitude: latitude,
      longitude: longitude,
    );
    return result.barangay;
  }

  /// Single call to the Edge Function — returns both address + barangay.
  Future<({String? address, String? barangay})> reverseGeocode({
    required double latitude,
    required double longitude,
  }) async {
    final cacheKey =
        '${latitude.toStringAsFixed(4)},${longitude.toStringAsFixed(4)}';

    // Cache hit — no network call
    if (_cache.containsKey(cacheKey)) {
      debugPrint('Geocoding: Cache hit for $cacheKey');
      return _cache[cacheKey]!;
    }

    try {
      final response = await _supabase.functions.invoke(
        'geocode',
        body: {'lat': latitude, 'lng': longitude},
      );

      if (response.status != 200) {
        debugPrint(
          'Geocoding Edge Function error: '
          'status=${response.status} data=${response.data}',
        );
        return (address: null, barangay: null);
      }

      final data = response.data as Map<String, dynamic>;
      final output = (
        address: data['address']?.toString(),
        barangay: data['barangay']?.toString(),
      );

      _cache[cacheKey] = output;

      debugPrint(
        'Geocoding: $cacheKey → '
        'address=${output.address != null ? 'OK' : 'null'}, '
        'barangay=${output.barangay}',
      );

      return output;
    } catch (e) {
      debugPrint('Geocoding Edge Function call failed: $e');
      return (address: null, barangay: null);
    }
  }

  /// Clear the in-memory cache (useful for testing).
  static void clearCache() {
    _cache.clear();
  }
}
