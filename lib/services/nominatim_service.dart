import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/place.dart';

class NominatimService {
  // ── Cache ────────────────────────────────────────────────
  static const int _maxCacheSize = 100;
  final Map<String, List<Place>> _cache = {};

  // ── Rate limiting ────────────────────────────────────────
  DateTime? _lastRequestTime;

  // ── Vigan City bounding box ──────────────────────────────
  // lon_min, lat_max, lon_max, lat_min (Nominatim format)
  static const String _viewbox = '120.3500,17.6100,120.4300,17.5300';

  // ============================================================
  // PUBLIC API
  // ============================================================
  Future<List<Place>> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];

    final cacheKey = trimmed.toLowerCase();
    if (_cache.containsKey(cacheKey)) {
      return _cache[cacheKey]!;
    }

    // Nominatim rate limit: max 1 req/sec
    await _throttle();

    final url = Uri.parse(
      'https://nominatim.openstreetmap.org/search'
      '?format=jsonv2'
      '&addressdetails=1'
      '&countrycodes=ph'
      '&limit=10'
      '&viewbox=$_viewbox'
      '&bounded=1'
      '&q=${Uri.encodeComponent(trimmed)}',
    );

    debugPrint('Nominatim: Searching "$trimmed"');

    try {
      final response = await http
          .get(
            url,
            headers: {
              'User-Agent':
                  'rtoda-fare-calculator/1.0 '
                  '(https://vigan.gov.ph; rtodavigan@gmail.com)',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        debugPrint('Nominatim: HTTP ${response.statusCode}');
        return [];
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! List) {
        debugPrint('Nominatim: Unexpected response format');
        return [];
      }

      final places = <Place>[];
      final seen = <String>{};

      for (final e in decoded) {
        if (e is! Map) continue;

        final lat = double.tryParse(e['lat']?.toString() ?? '');
        final lon = double.tryParse(e['lon']?.toString() ?? '');
        if (lat == null || lon == null) continue;

        final display = e['display_name']?.toString() ?? '';
        if (display.isEmpty) continue;

        // Dedupe by rounded coordinates
        final dedupeKey = '${lat.toStringAsFixed(3)},${lon.toStringAsFixed(3)}';
        if (!seen.add(dedupeKey)) continue;

        final barangay = _extractBarangay(e, display);
        final name = _extractName(e, display, barangay);

        places.add(
          Place(
            name: name,
            fullAddress: display,
            barangay: barangay,
            latitude: lat,
            longitude: lon,
          ),
        );
      }

      // Cache with size cap
      _cache[cacheKey] = places;
      if (_cache.length > _maxCacheSize) {
        _cache.remove(_cache.keys.first);
      }

      debugPrint('Nominatim: ${places.length} results for "$trimmed"');
      return places;
    } on TimeoutException {
      debugPrint('Nominatim: Timeout');
      return [];
    } catch (e) {
      debugPrint('Nominatim error: $e');
      return [];
    }
  }

  // ============================================================
  // HELPERS
  // ============================================================

  /// Ensures at most 1 request per second (Nominatim policy).
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

  /// Extracts barangay name from structured address or display_name.
  String _extractBarangay(Map e, String display) {
    // Try structured fields first (requires addressdetails=1)
    final address = e['address'];
    if (address is Map) {
      for (final key in ['suburb', 'village', 'quarter', 'neighbourhood']) {
        final value = address[key]?.toString().trim();
        if (value != null && value.isNotEmpty) return value;
      }
    }

    // Fallback: parse display_name
    final regex = RegExp(
      r'^(barangay|brgy\.?|bgy\.?)\s+(.+)$',
      caseSensitive: false,
    );

    for (final part in display.split(',')) {
      final text = part.trim();
      if (regex.hasMatch(text)) return text;
    }

    return '';
  }

  /// Picks the best display name.
  String _extractName(Map e, String display, String barangay) {
    if (barangay.isNotEmpty) return barangay;

    // Fall back to structured name
    final namedetails = e['name']?.toString().trim();
    if (namedetails != null && namedetails.isNotEmpty) return namedetails;

    // Last resort: first part of display_name
    return display.split(',').first.trim();
  }
}
