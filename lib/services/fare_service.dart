import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FareService {
  final SupabaseClient supabase = Supabase.instance.client;

  // ============================================================
  // PUBLIC API
  // ============================================================
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
      return {
        "covered": false,
        "message": "Fare lookup took too long. Please try again.",
      };
    } catch (e, stackTrace) {
      debugPrint('FARE CALCULATION ERROR: $e');
      debugPrint('STACK TRACE: $stackTrace');
      return {"covered": false, "message": _friendlyError(e)};
    }
  }

  // ============================================================
  // INTERNAL
  // ============================================================
  Future<Map<String, dynamic>> _doCalculateFare({
    required String pickupBarangay,
    required String destinationBarangay,
    required bool discounted,
    required bool nightFare,
    required bool isSingleOccupant,
  }) async {
    final cleanPickup = pickupBarangay.trim();
    final cleanDestination = destinationBarangay.trim();

    // ── 1. Look up pickup village ──────────────────────────
    final pickup = await supabase
        .from('villages')
        .select('village_name, zone_category')
        .ilike('village_name', cleanPickup)
        .limit(1)
        .maybeSingle();

    if (pickup == null) {
      return {
        "covered": false,
        "message": "Pickup is not covered by the CPSTMD Fare Matrix.",
      };
    }

    // ── 2. Look up destination village ─────────────────────
    final destination = await supabase
        .from('villages')
        .select('village_name, zone_category')
        .ilike('village_name', cleanDestination)
        .limit(1)
        .maybeSingle();

    if (destination == null) {
      return {
        "covered": false,
        "message": "Destination is not covered by the CPSTMD Fare Matrix.",
      };
    }

    // ── 3. Validate zones ──────────────────────────────────
    final pickupZone = pickup['zone_category']?.toString();
    final destinationZone = destination['zone_category']?.toString();

    if (pickupZone == null || destinationZone == null) {
      return {
        "covered": false,
        "message": "Village data is incomplete. Please try another location.",
      };
    }

    // Both locations outside Poblacion → not covered
    if (pickupZone != 'Zone_Poblacion' && destinationZone != 'Zone_Poblacion') {
      return {
        "covered": false,
        "message":
            "This route is not covered by the official CPSTMD Fare Matrix.",
      };
    }

    // ── 4. Determine fare zone ─────────────────────────────
    // At this point, at least one of the two is Zone_Poblacion.
    final fareZone = pickupZone == 'Zone_Poblacion'
        ? destinationZone
        : pickupZone;

    // ── 5. Look up fare ────────────────────────────────────
    final fare = await supabase
        .from('fare_matrix')
        .select()
        .eq('zone_category', fareZone)
        .limit(1)
        .maybeSingle();

    if (fare == null) {
      return {
        "covered": false,
        "message": "Official fare not found for this route.",
      };
    }

    // ── 6. Calculate fare ──────────────────────────────────
    final officialFare = _selectFare(
      fare: fare,
      isSingleOccupant: isSingleOccupant,
      nightFare: nightFare,
      discounted: discounted,
    );

    if (officialFare <= 0) {
      return {
        "covered": false,
        "message": "Fare data for this route is incomplete.",
      };
    }

    // ── 7. Return result ───────────────────────────────────
    return {
      "covered": true,
      "pickup": cleanPickup,
      "pickupZone": pickupZone,
      "destination": cleanDestination,
      "destinationZone": destinationZone,
      "fareZone": fareZone,
      "fare": officialFare,
    };
  }

  // ============================================================
  // FARE SELECTION
  // ============================================================
  double _selectFare({
    required Map<String, dynamic> fare,
    required bool isSingleOccupant,
    required bool nightFare,
    required bool discounted,
  }) {
    String key;
    String fallbackKey;

    if (isSingleOccupant) {
      if (nightFare) {
        key = 'single_discounted_fare_night';
        fallbackKey = 'single_night_fare';
      } else {
        key = 'single_discounted_fare_day';
        fallbackKey = 'single_day_fare';
      }
    } else {
      if (nightFare) {
        key = 'shared_discounted_fare_night';
        fallbackKey = 'shared_night_fare';
      } else {
        key = 'shared_discounted_fare_day';
        fallbackKey = 'shared_day_fare';
      }
    }

    if (!discounted) {
      return _asDouble(fare[fallbackKey]);
    }

    // Discounted path — fall back to regular if discount is null.
    final discountedValue = _asDouble(fare[key]);
    if (discountedValue > 0) {
      return discountedValue;
    }

    debugPrint('Discounted fare missing ($key) — falling back to $fallbackKey');
    return _asDouble(fare[fallbackKey]);
  }

  // ============================================================
  // HELPERS
  // ============================================================
  double _asDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  String _friendlyError(Object e) {
    if (e is TimeoutException) {
      return 'The fare service is taking too long. Please try again.';
    }
    if (e is PostgrestException) {
      if (e.code == '42P01' || e.code == '42703') {
        return 'Fare data is currently unavailable. '
            'Please try again later.';
      }
      return 'Could not retrieve fare information. Please try again.';
    }
    return 'Something went wrong while calculating the fare.';
  }
}
