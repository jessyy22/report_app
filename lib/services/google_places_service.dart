import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/place.dart';

class GooglePlacesService {
  // Replace with your actual API Key
  static const String apiKey = "AIzaSyAovUxi_7Ak591LhTmShKqcnEOf2PRy1uI";

  Future<List<Place>> searchPlaces(String query) async {
    if (query.trim().isEmpty) return [];

    final autocompleteUrl =
        "https://places.googleapis.com/v1/places:autocomplete";

    final response = await http.post(
      Uri.parse(autocompleteUrl),
      headers: {
        "Content-Type": "application/json",
        "X-Goog-Api-Key": apiKey,
        "X-Goog-FieldMask":
            "suggestions.placePrediction.placeId,suggestions.placePrediction.text",
      },
      body: jsonEncode({
        "input": query,
        "includedRegionCodes": ["PH"],
        "regionCode": "PH",
        "languageCode": "en",
        "locationBias": {
          "circle": {
            "center": {"latitude": 17.5747, "longitude": 120.3869},
            "radius": 15000.0,
          },
        },
      }),
    );

    if (response.statusCode != 200) {
      print(response.body);
      return [];
    }

    final data = jsonDecode(response.body);

    if (data["suggestions"] == null) {
      return [];
    }

    List<Place> places = [];

    for (final suggestion in data["suggestions"]) {
      final placeId = suggestion["placePrediction"]["placeId"];

      final details = await _getPlaceDetails(placeId);

      if (details != null) {
        places.add(details);
      }
    }

    return places;
  }

  Future<Place?> _getPlaceDetails(String placeId) async {
    final url = "https://places.googleapis.com/v1/places/$placeId";

    final response = await http.get(
      Uri.parse(url),
      headers: {
        "X-Goog-Api-Key": apiKey,
        "X-Goog-FieldMask": "displayName,formattedAddress,location",
      },
    );

    if (response.statusCode != 200) {
      return null;
    }

    final json = jsonDecode(response.body);

    return Place(
      name: json["displayName"]["text"] ?? "",
      fullAddress: json["formattedAddress"] ?? "",
      barangay: "", // We'll fill this later using reverse geocoding
      latitude: (json["location"]["latitude"] as num).toDouble(),
      longitude: (json["location"]["longitude"] as num).toDouble(),
    );
  }
}
