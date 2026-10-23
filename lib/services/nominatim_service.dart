import 'dart:convert';
import 'package:http/http.dart' as http;

import '../models/place.dart';

class NominatimService {
  final Map<String, List<Place>> _cache = {};
  Future<List<Place>> search(String query) async {
    final key = query.toLowerCase().trim();

    if (_cache.containsKey(key)) {
      return _cache[key]!;
    }

    if (query.trim().isEmpty) return [];

    final url = Uri.parse(
      "https://nominatim.openstreetmap.org/search"
      "?format=jsonv2"
      "&countrycodes=ph"
      "&limit=10"
      "&q=${Uri.encodeComponent("$query, Vigan City")}",
    );

    print("Searching: $query");
    print(url);

    final response = await http.get(
      url,
      headers: {
        "User-Agent": "rtoda-fare-calculator/1.0",
        "Accept": "application/json",
      },
    );

    print("Status Code: ${response.statusCode}");
    print("Body: ${response.body}");

    if (response.statusCode != 200) {
      return [];
    }

    final List data = jsonDecode(response.body);

    final places = data.map((e) {
      final display = e["display_name"] as String;

      final parts = display.split(",");

      // Find the first part that contains "Barangay"
      String barangay = "";

      for (final part in parts) {
        final text = part.trim();

        if (text.toLowerCase().startsWith("barangay")) {
          barangay = text;
          break;
        }
      }

      return Place(
        name: parts.first.trim(),
        fullAddress: display,
        barangay: barangay,
        latitude: double.parse(e["lat"]),
        longitude: double.parse(e["lon"]),
      );
    }).toList();

    _cache[key] = places;

    return places;
  }
}
