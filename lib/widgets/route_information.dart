import 'package:flutter/material.dart';
import '../models/place.dart';

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
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            blurRadius: 20,
            color: Colors.black12,
          ),
        ],
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),

          Container(
            width: 45,
            height: 5,
            decoration: BoxDecoration(
              color: Colors.grey.shade400,
              borderRadius: BorderRadius.circular(20),
            ),
          ),

          const SizedBox(height: 15),

          Expanded(
            child: ListView(
              controller: controller,
              padding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 5,
              ),
              children: [
                const Text(
                  "Route Information",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 20),

                Row(
                  children: [
                    const Icon(Icons.trip_origin, color: Colors.green),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        pickupBarangay ??
                            pickup?.name ??
                            "Select Pickup Location",
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 15),

                Row(
                  children: [
                    const Icon(Icons.location_on, color: Colors.red),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        destinationBarangay ??
                            destination?.name ??
                            "Select Destination",
                      ),
                    ),
                  ],
                ),

                const Divider(height: 30),

                _infoRow(
                  "Distance",
                  "${distance.toStringAsFixed(2)} km",
                ),

                _infoRow(
                  "Zone",
                  destinationZone ?? "--",
                ),

                const SizedBox(height: 18),

                const Text(
                  "Fare Options",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 12),

                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Icon(
                            isSingleOccupant
                                ? Icons.person
                                : Icons.groups,
                            color: Colors.green,
                          ),

                          const SizedBox(width: 12),

                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isSingleOccupant
                                      ? "Single Occupant"
                                      : "Shared / Multiple",
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const Text(
                                  "Passenger Type",
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          Switch(
                            value: isSingleOccupant,
                            onChanged: onPassengerChanged,
                          ),
                        ],
                      ),

                      const Divider(),

                      Row(
                        children: [
                          Icon(
                            discounted
                                ? Icons.school
                                : Icons.payments,
                            color: Colors.orange,
                          ),

                          const SizedBox(width: 12),

                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(
                                  discounted
                                      ? "Discounted Fare"
                                      : "Regular Fare",
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const Text(
                                  "Fare Category",
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          Switch(
                            value: discounted,
                            onChanged: onDiscountChanged,
                          ),
                        ],
                      ),

                      const Divider(),

                      Row(
                        children: [
                          Icon(
                            nightFare
                                ? Icons.nightlight_round
                                : Icons.wb_sunny,
                            color: Colors.blue,
                          ),

                          const SizedBox(width: 12),

                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(
                                  nightFare
                                      ? "Night Rate"
                                      : "Day Rate",
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const Text(
                                  "Automatically determined by current time",
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                covered
                    ? Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          children: [
                            const Text(
                              "OFFICIAL CPSTMD FARE",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.green,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              "₱${officialFare.toStringAsFixed(2)}",
                              style: const TextStyle(
                                fontSize: 34,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      )
                    : Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          message,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.orange,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),

                const SizedBox(height: 30),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String title, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}