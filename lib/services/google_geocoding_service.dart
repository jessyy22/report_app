import 'dart:convert';
import 'package:http/http.dart' as http;

class GoogleGeocodingService {
  static const String apiKey = "AIzaSyAeEzeHJPfDS33XJiZk6vDl2olcua1seqs";

  Future<String?> getFullAddress({
    required double latitude,
    required double longitude,
  }) async {
    try {
      final url =
          "https://maps.googleapis.com/maps/api/geocode/json"
          "?latlng=$latitude,$longitude"
          "&key=$apiKey";

      final response = await http.get(Uri.parse(url));

      if (response.statusCode != 200) {
        print(response.body);
        return null;
      }

      final data = jsonDecode(response.body);

      if (data["status"] != "OK") {
        print(data);
        return null;
      }

      final results = data["results"] as List;

      if (results.isEmpty) {
        return null;
      }

      final formattedAddress = results.first["formatted_address"];

      if (formattedAddress == null) {
        return null;
      }

      print("========== Google Geocoding ==========");
      print("Complete Address: $formattedAddress");
      print("======================================");

      return formattedAddress.toString().trim();
    } catch (e) {
      print("Google Geocoding Error: $e");
      return null;
    }
  }

  // Kept for compatibility with any existing code.
  Future<String?> getBarangay({
    required double latitude,
    required double longitude,
  }) async {
    try {
      final url =
          "https://maps.googleapis.com/maps/api/geocode/json"
          "?latlng=$latitude,$longitude"
          "&key=$apiKey";

      final response = await http.get(Uri.parse(url));

      if (response.statusCode != 200) {
        return null;
      }

      final data = jsonDecode(response.body);

      if (data["status"] != "OK") {
        return null;
      }

      final results = data["results"] as List;

      for (final result in results) {
        final components = result["address_components"] as List;

        for (final component in components) {
          final types = List<String>.from(component["types"]);

          if (types.contains("administrative_area_level_4")) {
            return component["long_name"];
          }

          if (types.contains("sublocality")) {
            return component["long_name"];
          }

          if (types.contains("sublocality_level_1")) {
            return component["long_name"];
          }
        }
      }

      return null;
    } catch (e) {
      print("Google Geocoding Error: $e");
      return null;
    }
  }
}
