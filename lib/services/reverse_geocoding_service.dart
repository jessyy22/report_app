import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ReverseGeocodingService {
  // ── User-Agent (Nominatim policy requires email/URL) ────
  static const String _userAgent =
      'RTODA-FareCalculator/1.0 '
      '(https://vigan.gov.ph; rtodavigan@gmail.com)';

  // ── Cache (rounded to ~11m precision) ───────────────────
  static final Map<String, ({String? address, String? barangay})> _cache = {};

  // ── Rate limiting (Nominatim: max 1 req/sec) ────────────
  DateTime? _lastRequestTime;

  // ============================================================
  // PUBLIC API (backward compatible)
  // ============================================================

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

  // ============================================================
  // COMBINED API — one Nominatim call returns both
  // ============================================================
  Future<({String? address, String? barangay})> reverseGeocode({
    required double latitude,
    required double longitude,
  }) async {
    final cacheKey =
        '${latitude.toStringAsFixed(4)},${longitude.toStringAsFixed(4)}';

    // Cache hit
    if (_cache.containsKey(cacheKey)) {
      debugPrint('ReverseGeocode: Cache hit for $cacheKey');
      return _cache[cacheKey]!;
    }

    await _throttle();

    final url = Uri.parse(
      'https://nominatim.openstreetmap.org/reverse'
      '?format=jsonv2'
      '&addressdetails=1'
      '&accept-language=en'
      '&lat=$latitude'
      '&lon=$longitude',
    );

    try {
      final response = await http
          .get(
            url,
            headers: {
              'User-Agent': _userAgent,
              'Accept': 'application/json',
              'Accept-Language': 'en',
            },
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        debugPrint('ReverseGeocode: HTTP ${response.statusCode}');
        return (address: null, barangay: null);
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        debugPrint('ReverseGeocode: Unexpected response format');
        return (address: null, barangay: null);
      }

      final displayName = decoded['display_name']?.toString().trim();
      final address = decoded['address'];

      String? barangay;
      if (address is Map) {
        // Priority order — suburb is most reliable for PH barangays
        barangay =
            (address['suburb'] ??
                    address['quarter'] ??
                    address['village'] ??
                    address['city_district'] ??
                    address['neighbourhood'])
                ?.toString()
                .trim();

        if (barangay != null && barangay.isEmpty) barangay = null;
      }

      final output = (
        address: (displayName == null || displayName.isEmpty)
            ? null
            : displayName,
        barangay: barangay,
      );

      _cache[cacheKey] = output;

      debugPrint(
        'ReverseGeocode: $cacheKey → '
        'address=${output.address != null ? 'OK' : 'null'}, '
        'barangay=${output.barangay}',
      );

      return output;
    } on TimeoutException {
      debugPrint('ReverseGeocode: Timeout after 10s');
      return (address: null, barangay: null);
    } catch (e) {
      debugPrint('ReverseGeocode error: $e');
      return (address: null, barangay: null);
    }
  }

  // ============================================================
  // HELPERS
  // ============================================================
  Future<void> _throttle() async {
    if (_lastRequestTime != null) {
      final elapsed = DateTime.now().difference(_lastRequestTime!);
      const minInterval = Duration(seconds: 1);
      if (elapsed < minInterval) {
        await Future.delayed(minInterval - elapsed);
      }
    }
    _lastRequestTime = DateTime.now();
  }

  /// Clear the cache (useful for testing or when settings change).
  static void clearCache() {
    _cache.clear();
  }
}
