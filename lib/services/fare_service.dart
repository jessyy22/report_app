import 'package:supabase_flutter/supabase_flutter.dart';

class FareService {
  final SupabaseClient supabase = Supabase.instance.client;

  Future<Map<String, dynamic>> calculateFare({
    required String pickupBarangay,
    required String destinationBarangay,
    required bool discounted,
    required bool nightFare,
    required bool
    isSingleOccupant, 
  }) async {
    try {

      final pickup = await supabase
          .from('villages')
          .select()
          .ilike('village_name', pickupBarangay)
          .maybeSingle();

      if (pickup == null) {
        return {
          "covered": false,
          "message": "Pickup is not covered by the CPSTMD Fare Matrix.",
        };
      }

      final destination = await supabase
          .from('villages')
          .select()
          .ilike('village_name', destinationBarangay)
          .maybeSingle();

      if (destination == null) {
        return {
          "covered": false,
          "message": "Destination is not covered by the CPSTMD Fare Matrix.",
        };
      }

      final pickupZone = pickup["zone_category"];
      final destinationZone = destination["zone_category"];
      // Both locations are outside Poblacion
      if (pickupZone != "Zone_Poblacion" &&
          destinationZone != "Zone_Poblacion") {
        return {
          "covered": false,
          "message":
              "This route is not covered by the official CPSTMD Fare Matrix.",
        };
      }

      String targetZone;

      if (pickupZone == "Zone_Poblacion") {
        targetZone = destinationZone;
      } else if (destinationZone == "Zone_Poblacion") {
        targetZone = pickupZone;
      } else {
        targetZone = destinationZone;
      }

      final fare = await supabase
          .from("fare_matrix")
          .select()
          .eq("zone_category", targetZone)
          .maybeSingle();

      if (fare == null) {
        return {"covered": false, "message": "Official fare not found."};
      }

      double officialFare;

      if (isSingleOccupant) {
        if (nightFare) {
          officialFare = discounted
              ? (fare["single_discounted_fare_night"] as num).toDouble()
              : (fare["single_night_fare"] as num).toDouble();
        } else {
          officialFare = discounted
              ? (fare["single_discounted_fare_day"] as num).toDouble()
              : (fare["single_day_fare"] as num).toDouble();
        }
      } else {
        // Shared / Multiple Occupants
        if (nightFare) {
          officialFare =
              discounted && fare["shared_discounted_fare_night"] != null
              ? (fare["shared_discounted_fare_night"] as num).toDouble()
              : (fare["shared_night_fare"] as num).toDouble();
        } else {
          officialFare =
              discounted && fare["shared_discounted_fare_day"] != null
              ? (fare["shared_discounted_fare_day"] as num).toDouble()
              : (fare["shared_day_fare"] as num).toDouble();
        }
      }

      return {
        "covered": true,
        "pickup": pickupBarangay,
        "pickupZone": pickupZone,
        "destination": destinationBarangay,
        "destinationZone": targetZone,
        "fare": officialFare,
      };
    } catch (e) {
      return {"covered": false, "message": e.toString()};
    }
  }
}
