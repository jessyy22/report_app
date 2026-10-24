import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/place.dart';

class GooglePlacesService {
  /// Supabase Edge Function endpoint.
  static String get _endpoint =>
      'https://haryaqpwigdqthiulgwu.supabase.co/functions/v1/places';

  /// Send the anon/publishable key in the `apikey` header.
  /// Do NOT put it in `Authorization: Bearer ...` — that requires a JWT.
  static Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'apikey': 'sb_publishable_05uY19PVrsc6414rAEH83Q_QqCby_rs',
  };

  // ============================================================
  // SEARCH (autocomplete + details)
  // ============================================================
  Future<List<Place>> searchPlaces(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];

    try {
      final response = await http
          .post(
            Uri.parse(_endpoint),
            headers: _headers,
            body: jsonEncode({'action': 'autocomplete', 'query': trimmed}),
          )
          .timeout(const Duration(seconds: 10));

      debugPrint('Places: status=${response.statusCode} for "$trimmed"');

      if (response.statusCode != 200) {
        debugPrint('Places error body: ${response.body}');
        return [];
      }

      final data = jsonDecode(response.body);
      final results = data['results'];

      if (results is! List || results.isEmpty) {
        debugPrint('Places: no suggestions in response');
        return [];
      }

      // Fetch details in parallel (faster than sequential)
      final futures = <Future<Place?>>[];
      for (final r in results) {
        if (r is! Map) continue;
        final placeId = r['placeId']?.toString();
        if (placeId == null || placeId.isEmpty) continue;
        futures.add(_getPlaceDetails(placeId));
      }

      final resolved = await Future.wait(futures);
      final places = resolved.whereType<Place>().toList();

      debugPrint('Places: ${places.length} resolved for "$trimmed"');
      return places;
    } on TimeoutException {
      debugPrint('Places: timeout for "$trimmed"');
      return [];
    } catch (e) {
      debugPrint('Places: exception — $e');
      return [];
    }
  }

  // ============================================================
  // DETAILS
  // ============================================================
  Future<Place?> _getPlaceDetails(String placeId) async {
    try {
      final response = await http
          .post(
            Uri.parse(_endpoint),
            headers: _headers,
            body: jsonEncode({'action': 'details', 'placeId': placeId}),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        debugPrint('Place details error: ${response.statusCode} for $placeId');
        return null;
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;

      final lat = (json['latitude'] as num?)?.toDouble();
      final lng = (json['longitude'] as num?)?.toDouble();
      if (lat == null || lng == null) return null;

      return Place(
        name: json['name']?.toString() ?? '',
        fullAddress: json['fullAddress']?.toString() ?? '',
        barangay: json['barangay']?.toString() ?? '',
        latitude: lat,
        longitude: lng,
      );
    } catch (e) {
      debugPrint('Place details exception: $e');
      return null;
    }
  }
}
