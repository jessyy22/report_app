import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/place.dart';
import '../theme/app_theme.dart';

class RouteInformationCard extends StatelessWidget {
  final ScrollController controller;
  final Place? pickup;
  final Place? destination;
  final double distance;

  final String? pickupBarangay;
  final String? destinationBarangay;
  final String? destinationZone;

  final ValueChanged<bool> onPassengerChanged;
  final ValueChanged<bool> onDiscountChanged;

  final double officialFare;
  final bool covered;
  final String message;

  final bool isSingleOccupant;
  final bool nightFare;
  final bool discounted;

  const RouteInformationCard({
    super.key,
    required this.pickup,
    required this.destination,
    required this.distance,
    required this.pickupBarangay,
    required this.destinationBarangay,
    required this.destinationZone,
    required this.officialFare,
    required this.onPassengerChanged,
    required this.onDiscountChanged,
    required this.isSingleOccupant,
    required this.nightFare,
    required this.discounted,
    required this.covered,
    required this.message,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [BoxShadow(blurRadius: 20, color: Color(0x14000000))],
      ),
      child: Column(
        children: [
          // ── Drag handle + close ───────────────────────────
          Stack(
            children: [
              Center(
                child: Container(
                  width: 45,
                  height: 5,
                  margin: const EdgeInsets.only(top: 10),
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
              Positioned(
                right: 4,
                top: 0,
                child: IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          Expanded(
            child: ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 30),
              children: [
                // ── Title ──────────────────────────────────
                const Text(
                  'Route Information',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.text,
                    letterSpacing: -0.3,
                  ),
                ),

                const SizedBox(height: 20),

                // ── Pickup row ─────────────────────────────
                _locationRow(
                  icon: Icons.trip_origin,
                  iconColor: AppColors.green,
                  backgroundColor: AppColors.greenSoft,
                  label: 'Pickup',
                  value: pickupBarangay ?? pickup?.name ?? 'Select pickup',
                ),

                const SizedBox(height: 12),

                // ── Destination row ────────────────────────
                _locationRow(
                  icon: Icons.location_on,
                  iconColor: AppColors.danger,
                  backgroundColor: AppColors.dangerSoft,
                  label: 'Destination',
                  value:
                      destinationBarangay ??
                      destination?.name ??
                      'Select destination',
                ),

                const Divider(height: 32),

                // ── Info rows ──────────────────────────────
                _infoRow(
                  'Distance',
                  distance > 0 ? '${distance.toStringAsFixed(2)} km' : '--',
                ),
                _infoRow('Zone', destinationZone ?? 'Select a destination'),

                const SizedBox(height: 20),

                // ── Fare options ───────────────────────────
                const Text(
                  'Fare Options',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 12),

                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    children: [
                      _switchRow(
                        icon: isSingleOccupant ? Icons.person : Icons.groups,
                        iconColor: AppColors.green,
                        title: isSingleOccupant
                            ? 'Single Occupant'
                            : 'Shared / Multiple',
                        subtitle: 'Passenger Type',
                        value: isSingleOccupant,
                        onChanged: (v) {
                          HapticFeedback.selectionClick();
                          onPassengerChanged(v);
                        },
                      ),
                      const Divider(height: 1, color: AppColors.border),
                      _switchRow(
                        icon: discounted ? Icons.school : Icons.payments,
                        iconColor: Colors.orange.shade700,
                        title: discounted ? 'Discounted Fare' : 'Regular Fare',
                        subtitle: 'Fare Category',
                        value: discounted,
                        onChanged: (v) {
                          HapticFeedback.selectionClick();
                          onDiscountChanged(v);
                        },
                      ),
                      const Divider(height: 1, color: AppColors.border),
                      _infoToggleRow(
                        icon: nightFare
                            ? Icons.nightlight_round
                            : Icons.wb_sunny,
                        iconColor: Colors.indigo.shade700,
                        title: nightFare ? 'Night Rate' : 'Day Rate',
                        subtitle: 'Automatically determined by current time',
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // ── Fare result ────────────────────────────
                covered ? _officialFareBox() : _notCoveredWarning(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Official fare box ────────────────────────────────────
  Widget _officialFareBox() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.greenSoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.green.withValues(alpha: 0.20)),
      ),
      child: Column(
        children: [
          Text(
            'OFFICIAL CPSTMD FARE',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: AppColors.greenDark,
              fontSize: 12,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              _formatPeso(officialFare),
              style: const TextStyle(
                fontSize: 40,
                fontWeight: FontWeight.w800,
                color: AppColors.greenDark,
                letterSpacing: -1.0,
                height: 1.0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Not covered warning ──────────────────────────────────
  Widget _notCoveredWarning() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.amber.shade200),
      ),
      child: Column(
        children: [
          Icon(Icons.info_outline, color: Colors.amber.shade900, size: 32),
          const SizedBox(height: 8),
          const Text(
            'Fare Not Available',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  // ── Location row ─────────────────────────────────────────
  Widget _locationRow({
    required IconData icon,
    required Color iconColor,
    required Color backgroundColor,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: backgroundColor,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: iconColor, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.muted,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Info row ─────────────────────────────────────────────
  Widget _infoRow(String title, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(color: AppColors.muted, fontSize: 13),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: AppColors.text,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Switch row ───────────────────────────────────────────
  Widget _switchRow({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: AppColors.text,
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 11, color: AppColors.muted),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: Colors.white,
            activeTrackColor: AppColors.green,
          ),
        ],
      ),
    );
  }

  // ── Read-only info row (night fare) ───────────────────────
  Widget _infoToggleRow({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: AppColors.text,
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 11, color: AppColors.muted),
                ),
              ],
            ),
          ),
          Icon(Icons.lock_outline, size: 16, color: AppColors.muted),
        ],
      ),
    );
  }

  // ── Peso formatting ──────────────────────────────────────
  static String _formatPeso(double amount) {
    final isWhole = amount == amount.roundToDouble();
    return '₱${amount.toStringAsFixed(isWhole ? 0 : 2)}';
  }
}
