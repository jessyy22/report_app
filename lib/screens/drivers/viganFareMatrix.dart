import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FareZone {
  final String zoneCategory;
  final List<String> villages;
  final double singleDayFare;
  final double singleNightFare;
  final double singleDiscountedDayFare;
  final double singleDiscountedNightFare;
  final double sharedDayFare;
  final double sharedNightFare;
  final double sharedDiscountedDayFare;
  final double sharedDiscountedNightFare;

  FareZone({
    required this.zoneCategory,
    required this.villages,
    required this.singleDayFare,
    required this.singleNightFare,
    required this.singleDiscountedDayFare,
    required this.singleDiscountedNightFare,
    required this.sharedDayFare,
    required this.sharedNightFare,
    required this.sharedDiscountedDayFare,
    required this.sharedDiscountedNightFare,
  });

  factory FareZone.fromJson(Map<String, dynamic> json, List<String> villages) {
    double asDouble(dynamic v) => (v as num).toDouble();

    return FareZone(
      zoneCategory: json['zone_category'] as String,
      villages: villages,
      singleDayFare: asDouble(json['single_day_fare']),
      singleNightFare: asDouble(json['single_night_fare']),
      singleDiscountedDayFare: asDouble(json['single_discounted_fare_day']),
      singleDiscountedNightFare: asDouble(json['single_discounted_fare_night']),
      sharedDayFare: asDouble(json['shared_day_fare']),
      sharedNightFare: asDouble(json['shared_night_fare']),
      sharedDiscountedDayFare: asDouble(json['shared_discounted_fare_day']),
      sharedDiscountedNightFare: asDouble(json['shared_discounted_fare_night']),
    );
  }

  bool get isPoblacion => zoneCategory == 'Zone_Poblacion';
}

class ViganFareMatrix {
  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.9,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: SingleChildScrollView(
                controller: scrollController,
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    _header(),
                    const SizedBox(height: 15),
                    FutureBuilder<List<FareZone>>(
                      future: _fetchFareZones(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 60),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }

                        if (snapshot.hasError) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 60),
                            child: Center(
                              child: Text(
                                "Couldn't load fare matrix.\n${snapshot.error}",
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.red),
                              ),
                            ),
                          );
                        }

                        final zones = snapshot.data ?? [];

                        final poblacionZone = zones
                            .where((z) => z.isPoblacion)
                            .cast<FareZone?>()
                            .firstWhere((_) => true, orElse: () => null);

                        final outsideZone = zones
                            .where((z) => !z.isPoblacion)
                            .cast<FareZone?>()
                            .firstWhere((_) => true, orElse: () => null);

                        return Column(
                          children: [
                            if (zones.isNotEmpty) ...[
                              _timeHeader(
                                "6:00 AM TO 6:00 PM",
                                Colors.green.shade700,
                              ),
                              ...zones.map(
                                (z) => _zoneSection(z, isNight: false),
                              ),
                              const SizedBox(height: 10),
                              _timeHeader(
                                "6:00 PM TO 6:00 AM",
                                Colors.blue.shade700,
                              ),
                              if (poblacionZone != null)
                                _nightSummarySection(
                                  poblacionZone,
                                  "FOR TRIPS WITHIN THE POBLACION AREA.",
                                ),
                              if (outsideZone != null)
                                _nightSummarySection(
                                  outsideZone,
                                  "FOR TRIPS GOING OUTSIDE THE POBLACION AREA.",
                                ),
                            ],

                            const SizedBox(height: 20),
                            _provisionalNotice(),
                            const SizedBox(height: 15),
                            _penaltyNotice(),
                            const SizedBox(height: 40),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// Fetches fare_matrix rows and attaches each zone's village names.
  static Future<List<FareZone>> _fetchFareZones() async {
    final client = Supabase.instance.client;

    final villagesRes = await client
        .from('villages')
        .select('village_name, zone_category');

    final villagesByZone = <String, List<String>>{};
    for (final row in villagesRes as List<dynamic>) {
      final zone = row['zone_category'] as String;
      final name = row['village_name'] as String;
      villagesByZone.putIfAbsent(zone, () => []).add(name);
    }

    final fareRes = await client.from('fare_matrix').select();

    return (fareRes as List<dynamic>).map((row) {
      final json = row as Map<String, dynamic>;
      final zone = json['zone_category'] as String;
      return FareZone.fromJson(json, villagesByZone[zone] ?? []);
    }).toList();
  }

  static Widget _header() {
    return Column(
      children: [
        Text(
          "CITY OF VIGAN",
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: Colors.green.shade800,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          "SCHEDULE OF FARES",
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const Text(
          "TRICYCLE FOR HIRE",
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        Text(
          "as per Ordinance No. 1 Series of 2011 as amended by Ordinance No. 10 Series of 2022",
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 11,
            fontStyle: FontStyle.italic,
            color: Colors.grey.shade600,
          ),
        ),
        const SizedBox(height: 12),
        Divider(color: Colors.green.shade700, thickness: 1.2),
      ],
    );
  }

  static Widget _timeHeader(String text, Color color) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8),
      margin: const EdgeInsets.only(bottom: 15),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  /// One card per zone, shown under the day (6AM-6PM) header.
  static Widget _zoneSection(FareZone zone, {required bool isNight}) {
    final singleFare = isNight ? zone.singleNightFare : zone.singleDayFare;
    final singleDiscounted = isNight
        ? zone.singleDiscountedNightFare
        : zone.singleDiscountedDayFare;
    final sharedFare = isNight ? zone.sharedNightFare : zone.sharedDayFare;
    final sharedDiscounted = isNight
        ? zone.sharedDiscountedNightFare
        : zone.sharedDiscountedDayFare;

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _zoneSentence(zone, isNight: isNight),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: Colors.indigo.shade900,
            ),
          ),
          const SizedBox(height: 8),
          _fare("Single Occupant", _peso(singleFare)),
          _fare(
            "Student, Senior Citizen and PWD Single Occupant (W/ID)",
            _peso(singleDiscounted),
          ),
          _fare("Two or More Occupants", "${_peso(sharedFare)} each"),
          _fare(
            "Two or More Students, Senior Citizens & PWD's (W/ID)",
            "${_peso(sharedDiscounted)} each",
          ),
        ],
      ),
    );
  }

  static Widget _nightSummarySection(FareZone zone, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: Colors.indigo.shade900,
            ),
          ),
          const SizedBox(height: 8),
          _fare("Single Occupant", _peso(zone.singleNightFare)),
          _fare(
            "Student, Senior Citizen and PWD Single Occupant (W/ID)",
            _peso(zone.singleDiscountedNightFare),
          ),
          _fare("Two or More Occupants", "${_peso(zone.sharedNightFare)} each"),
          _fare(
            "Two or More Students, Senior Citizens & PWD's (W/ID)",
            "${_peso(zone.sharedDiscountedNightFare)} each",
          ),
        ],
      ),
    );
  }

  static String _zoneSentence(FareZone zone, {required bool isNight}) {
    if (zone.isPoblacion) {
      final barangays = zone.villages.isNotEmpty
          ? zone.villages.join(', ')
          : 'Barangay I to Barangay IX';
      return isNight
          ? "FOR TRIPS WITHIN THE POBLACION AREA."
          : "WITHIN THE POBLACION AREA ($barangays) AND VICE VERSA.";
    }

    final villageList = zone.villages.join(', ');
    return isNight
        ? "FOR TRIPS GOING OUTSIDE THE POBLACION AREA."
        : "FROM THE POBLACION AREA TO $villageList AND VICE VERSA.";
  }

  static Widget _fare(String label, String price) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: Text(label)),
          const SizedBox(width: 8),
          Text(price, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  static Widget _provisionalNotice() {
    return Text(
      "A Provisional Schedule of Fares shall be imposed, wherein there shall be a Five Pesos (₱5.00) increase to the current schedule of fares for every ₱1.00 fuel price hike. Provided however that, in case there will be a rollback of the fuel price by ₱1.00, the schedule of fares shall also be reverted back by Five Pesos (₱5.00).",
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 11,
        fontStyle: FontStyle.italic,
        color: Colors.grey.shade700,
      ),
    );
  }

  static Widget _penaltyNotice() {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        border: Border.all(color: Colors.red),
        borderRadius: BorderRadius.circular(10),
      ),
      child: RichText(
        textAlign: TextAlign.center,
        text: TextSpan(
          style: TextStyle(color: Colors.grey.shade900, fontSize: 12),
          children: const [
            TextSpan(
              text: "PENALTY FOR VIOLATION: ",
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
            ),
            TextSpan(
              text:
                  "A fine of Two Thousand Pesos (₱2,000.00) or one day community service shall be determined by the General Services Office (GSO). Report violations at tel #: 0917-103-2784. The unauthorized tampering or removal of this fare matrix shall be considered vandalism punishable under Ordinance No. 12 Section 54, D, Series of 2006.",
            ),
          ],
        ),
      ),
    );
  }

  static String _peso(double amount) => "₱${amount.toStringAsFixed(2)}";
}
