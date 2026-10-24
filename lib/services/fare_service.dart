import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FareService {
  final SupabaseClient supabase = Supabase.instance.client;

  Future<Map<String, dynamic>> calculateFare({
    required String pickupBarangay,
    required String destinationBarangay,
    required bool discounted,
    required bool nightFare,
    required bool isSingleOccupant,
  }) async {
    try {
      return await _doCalculateFare(
        pickupBarangay: pickupBarangay,
        destinationBarangay: destinationBarangay,
        discounted: discounted,
        nightFare: nightFare,
        isSingleOccupant: isSingleOccupant,
      ).timeout(const Duration(seconds: 15));
    } on TimeoutException {
      return {"covered": false, "message": "Fare lookup took too long."};
    } catch (e) {
      debugPrint('FARE ERROR: $e');
      return {"covered": false, "message": "Fare calculation error."};
    }
  }

  Future<Map<String, dynamic>> _doCalculateFare({
    required String pickupBarangay,
    required String destinationBarangay,
    required bool discounted,
    required bool nightFare,
    required bool isSingleOccupant,
  }) async {
    final cleanPickup = pickupBarangay.trim();
    final cleanDestination = destinationBarangay.trim();

    // 1. Get Pickup Village
    final pickup = await supabase
        .from('villages')
        .select('zone_category')
        .ilike('village_name', cleanPickup)
        .maybeSingle();

    // 2. Get Destination Village
    final destination = await supabase
        .from('villages')
        .select('zone_category')
        .ilike('village_name', cleanDestination)
        .maybeSingle();

    if (pickup == null || destination == null) {
      return {
        "covered": false,
        "message": "One of the locations is not in the database.",
      };
    }

    final pickupZone = pickup['zone_category'];
    final destZone = destination['zone_category'];

    // 3. Rule: At least one must be Zone_Poblacion
    if (pickupZone != 'Zone_Poblacion' && destZone != 'Zone_Poblacion') {
      return {
        "covered": false,
        "message": "Route not covered (neither is Poblacion).",
      };
    }

    // 4. Find the target zone (the one that IS NOT Poblacion)
    String targetZone;
    if (pickupZone == 'Zone_Poblacion' && destZone == 'Zone_Poblacion') {
      targetZone = 'Zone_Poblacion'; // Poblacion to Poblacion
    } else if (pickupZone == 'Zone_Poblacion') {
      targetZone = destZone; // Leaving Poblacion
    } else {
      targetZone = pickupZone; // Going to Poblacion
    }

    debugPrint('Looking up fare for Zone: $targetZone');

    // 5. Fetch the row. We ONLY filter by zone_category.
    final fareRow = await supabase
        .from('fare_matrix')
        .select()
        .eq('zone_category', targetZone)
        .maybeSingle();

    if (fareRow == null) {
      return {
        "covered": false,
        "message": "No fare row exists for $targetZone in the matrix.",
      };
    }

    // 6. Get the price
    final fare = _selectFare(fareRow, isSingleOccupant, nightFare, discounted);

    if (fare <= 0) {
      return {
        "covered": false,
        "message": "Fare row found, but the price is 0 or null.",
      };
    }

    return {
      "covered": true,
      "fare": fare,
      "pickupZone": pickupZone,
      "destinationZone": destZone,
    };
  }

  double _selectFare(
    Map<String, dynamic> fare,
    bool isSingle,
    bool isNight,
    bool isDiscounted,
  ) {
    String key = isSingle
        ? (isNight ? 'single_night_fare' : 'single_day_fare')
        : (isNight ? 'shared_night_fare' : 'shared_day_fare');

    String discountKey = isSingle
        ? (isNight
              ? 'single_discounted_fare_night'
              : 'single_discounted_fare_day')
        : (isNight
              ? 'shared_discounted_fare_night'
              : 'shared_discounted_fare_day');

    if (isDiscounted) {
      double d = _asDouble(fare[discountKey]);
      if (d > 0) return d;
    }
    return _asDouble(fare[key]);
  }

  double _asDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }
}
