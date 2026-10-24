import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../theme/app_theme.dart';

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
    // Null-safe: tolerate missing/null fare columns.
    double asDouble(dynamic v) => (v as num?)?.toDouble() ?? 0.0;

    return FareZone(
      zoneCategory: json['zone_category']?.toString() ?? '',
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
                color: AppColors.card,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  _dragHandle(context),
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: () async => _fetchFareZones(),
                      child: SingleChildScrollView(
                        controller: scrollController,
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                        child: Column(
                          children: [
                            _header(),
                            const SizedBox(height: 16),
                            FutureBuilder<List<FareZone>>(
                              future: _fetchFareZones(),
                              builder: (context, snapshot) {
                                if (snapshot.connectionState ==
                                    ConnectionState.waiting) {
                                  return const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 60),
                                    child: Center(
                                      child: CircularProgressIndicator(),
                                    ),
                                  );
                                }

                                if (snapshot.hasError) {
                                  return _errorState(snapshot.error);
                                }

                                final zones = snapshot.data ?? [];
                                if (zones.isEmpty) {
                                  return const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 60),
                                    child: Center(
                                      child: Text(
                                        'No fare data available yet.',
                                        style: TextStyle(
                                          color: AppColors.muted,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                  );
                                }

                                final poblacionZone = zones
                                    .where((z) => z.isPoblacion)
                                    .cast<FareZone?>()
                                    .firstWhere(
                                      (_) => true,
                                      orElse: () => null,
                                    );
                                final outsideZone = zones
                                    .where((z) => !z.isPoblacion)
                                    .cast<FareZone?>()
                                    .firstWhere(
                                      (_) => true,
                                      orElse: () => null,
                                    );

                                return Column(
                                  children: [
                                    _timeHeader(
                                      '6:00 AM – 6:00 PM',
                                      AppColors.green,
                                      Icons.wb_sunny_outlined,
                                    ),
                                    const SizedBox(height: 12),
                                    ...zones.map(_zoneSection),
                                    const SizedBox(height: 16),
                                    _timeHeader(
                                      '6:00 PM – 6:00 AM',
                                      Colors.indigo.shade700,
                                      Icons.nightlight_outlined,
                                    ),
                                    const SizedBox(height: 12),
                                    if (poblacionZone != null)
                                      _nightSummarySection(
                                        poblacionZone,
                                        'For trips within the Poblacion area.',
                                      ),
                                    if (outsideZone != null)
                                      _nightSummarySection(
                                        outsideZone,
                                        'For trips going outside the '
                                        'Poblacion area.',
                                      ),
                                    const SizedBox(height: 24),
                                    _provisionalNotice(),
                                    const SizedBox(height: 16),
                                    _penaltyNotice(),
                                  ],
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ============================================================
  // DATA
  // ============================================================
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

  // ============================================================
  // HEADER
  // ============================================================
  static Widget _dragHandle(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 10),
        Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: AppColors.border,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: IconButton(
            tooltip: 'Close',
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
      ],
    );
  }

  static Widget _header() {
    return Column(
      children: [
        Text(
          'CITY OF VIGAN',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: AppColors.greenDark,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Schedule of Fares',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: AppColors.text,
          ),
        ),
        const Text(
          'Tricycle for Hire',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'As per Ordinance No. 1, Series of 2011 '
          'as amended by Ordinance No. 10, Series of 2022',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 11,
            fontStyle: FontStyle.italic,
            color: AppColors.muted,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 14),
        Container(height: 1, color: AppColors.border),
      ],
    );
  }

  static Widget _timeHeader(String text, Color color, IconData icon) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 13,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // ZONE SECTIONS
  // ============================================================
  static Widget _zoneSection(FareZone zone) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _zoneSentence(zone),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: AppColors.text,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          _fareTable(
            rows: _buildRows(
              singleRegular: zone.singleDayFare,
              singleDiscounted: zone.singleDiscountedDayFare,
              sharedRegular: zone.sharedDayFare,
              sharedDiscounted: zone.sharedDiscountedDayFare,
            ),
          ),
        ],
      ),
    );
  }

  static Widget _nightSummarySection(FareZone zone, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: AppColors.text,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          _fareTable(
            rows: _buildRows(
              singleRegular: zone.singleNightFare,
              singleDiscounted: zone.singleDiscountedNightFare,
              sharedRegular: zone.sharedNightFare,
              sharedDiscounted: zone.sharedDiscountedNightFare,
            ),
          ),
        ],
      ),
    );
  }

  static List<_FareRow> _buildRows({
    required double singleRegular,
    required double singleDiscounted,
    required double sharedRegular,
    required double sharedDiscounted,
  }) {
    final rows = <_FareRow>[];

    // Always add regular fares if they are valid
    if (singleRegular > 0) {
      rows.add(_FareRow('Single Occupant', singleRegular));
    }

    // Only add discount if > 0
    if (singleDiscounted > 0) {
      rows.add(
        _FareRow(
          'Student, Senior Citizen, PWD – Single (w/ ID)',
          singleDiscounted,
        ),
      );
    }

    // Always add regular shared if valid
    if (sharedRegular > 0) {
      rows.add(_FareRow('Two or More Occupants', sharedRegular, each: true));
    }

    // Only add discount if > 0
    if (sharedDiscounted > 0) {
      rows.add(
        _FareRow(
          'Two or More Students, Seniors, PWD (w/ ID)',
          sharedDiscounted,
          each: true,
        ),
      );
    }

    return rows;
  }

  static String _zoneSentence(FareZone zone) {
    if (zone.isPoblacion) {
      final barangays = zone.villages.isNotEmpty
          ? zone.villages.join(', ')
          : 'Barangay I to Barangay IX';
      return 'Within the Poblacion area ($barangays) and vice versa.';
    }

    final villageList = zone.villages.isNotEmpty
        ? zone.villages.join(', ')
        : '(unspecified villages)';
    return 'From the Poblacion area to $villageList and vice versa.';
  }

  // ============================================================
  // FARE TABLE
  // ============================================================
  static Widget _fareTable({required List<_FareRow> rows}) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(12),
        color: AppColors.card,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (int i = 0; i < rows.length; i++) ...[
            if (i > 0) Container(height: 1, color: AppColors.borderLight),
            _fareRow(rows[i]),
          ],
        ],
      ),
    );
  }

  static Widget _fareRow(_FareRow row) {
    return Container(
      color: row.each ? AppColors.background : AppColors.card,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              row.label,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.35,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            row.each ? '${_peso(row.amount)} each' : _peso(row.amount),
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 13,
              color: AppColors.text,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // NOTICES
  // ============================================================
  static Widget _provisionalNotice() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        border: Border.all(color: Colors.amber.shade200),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, size: 16, color: Colors.amber.shade800),
              const SizedBox(width: 6),
              Text(
                'PROVISIONAL FARE SCHEDULE',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                  color: Colors.amber.shade900,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'A ₱5.00 increase applies for every ₱1.00 fuel price hike. '
            'Conversely, if fuel price rolls back by ₱1.00, fares revert '
            'by ₱5.00.',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  static Widget _penaltyNotice() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.dangerSoft,
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                size: 16,
                color: AppColors.danger,
              ),
              const SizedBox(width: 6),
              const Text(
                'PENALTY FOR VIOLATION',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                  color: AppColors.danger,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'A fine of ₱2,000.00 or one day community service, '
            'as determined by the General Services Office (GSO). '
            'Report violations at 0917-103-2784.',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Unauthorized tampering or removal of this fare matrix '
            'is considered vandalism punishable under Ordinance No. 12, '
            'Section 54-D, Series of 2006.',
            style: TextStyle(
              fontSize: 11,
              fontStyle: FontStyle.italic,
              color: AppColors.muted,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  static Widget _errorState(Object? error) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: AppColors.danger, size: 36),
            const SizedBox(height: 8),
            const Text(
              "Couldn't load fare matrix.",
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              error.toString(),
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.danger, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  static String _peso(double amount) {
    final isWhole = amount == amount.roundToDouble();
    return '₱${amount.toStringAsFixed(isWhole ? 0 : 2)}';
  }
}

class _FareRow {
  final String label;
  final double amount;
  final bool each;

  _FareRow(this.label, this.amount, {this.each = false});
}
