import 'dart:convert';
import 'package:http/http.dart' as http;

class ReverseGeocodingService {
  static const String _userAgent = "RTODA-FareCalculator/1.0";

  Future<String?> getFullAddress({
    required double latitude,
    required double longitude,
  }) async {
    try {
      final url = Uri.parse(
        "https://nominatim.openstreetmap.org/reverse"
        "?format=jsonv2"
        "&lat=$latitude"
        "&lon=$longitude"
        "&addressdetails=1",
      );

      final response = await http.get(
        url,
        headers: {"User-Agent": _userAgent, "Accept": "application/json"},
      );

      if (response.statusCode != 200) {
        return null;
      }

      final data = jsonDecode(response.body);

      final displayName = data["display_name"];

      if (displayName == null || displayName.toString().trim().isEmpty) {
        return null;
      }

      print("========== Reverse Geocoding ==========");
      print("Complete Address: $displayName");
      print("=======================================");

      return displayName.toString().trim();
    } catch (e) {
      print("Reverse Geocoding Error: $e");
      return null;
    }
  }

  // Kept for compatibility with existing code.
  Future<String?> getBarangay({
    required double latitude,
    required double longitude,
  }) async {
    try {
      final url = Uri.parse(
        "https://nominatim.openstreetmap.org/reverse"
        "?format=jsonv2"
        "&lat=$latitude"
        "&lon=$longitude"
        "&addressdetails=1",
      );

      final response = await http.get(
        url,
        headers: {"User-Agent": _userAgent, "Accept": "application/json"},
      );

      if (response.statusCode != 200) {
        return null;
      }

      final data = jsonDecode(response.body);

      if (data["address"] == null) {
        return null;
      }

      final address = data["address"];

      String? barangay =
          address["village"] ??
          address["suburb"] ??
          address["city_district"] ??
          address["neighbourhood"] ??
          address["hamlet"] ??
          address["quarter"];

      return barangay?.trim();
    } catch (e) {
      print("Reverse Geocoding Error: $e");
      return null;
    }
  }
}
