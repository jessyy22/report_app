import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class GoogleGeocodingService {
  static String get _endpoint =>
      'https://haryaqpwigdqthiulgwu.supabase.co/functions/v1/places';

  static Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'apikey': 'sb_publishable_05uY19PVrsc6414rAEH83Q_QqCby_rs',
  };

  Future<String?> getFullAddress({
    required double latitude,
    required double longitude,
  }) async {
    final d = await _reverse(latitude, longitude);
    if (d == null) return null;
    final addr = d['address'] as String?;
    return (addr == null || addr.isEmpty) ? null : addr;
  }

  /// Barangay name only — for fare matrix lookup (e.g. "Poblacion").
  Future<String?> getBarangay({
    required double latitude,
    required double longitude,
  }) async {
    final d = await _reverse(latitude, longitude);
    if (d == null) return null;
    final brgy = d['barangay'] as String?;
    return (brgy == null || brgy.isEmpty) ? null : brgy;
  }

  Future<Map<String, dynamic>?> _reverse(double lat, double lng) async {
    try {
      final res = await http
          .post(
            Uri.parse(_endpoint),
            headers: _headers,
            body: jsonEncode({'action': 'reverse', 'lat': lat, 'lng': lng}),
          )
          .timeout(const Duration(seconds: 10));

      if (res.statusCode != 200) {
        print('Geocoding error ${res.statusCode}: ${res.body}');
        return null;
      }
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (e) {
      print('Google Geocoding Error: $e');
      return null;
    }
  }
}
