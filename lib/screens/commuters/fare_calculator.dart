import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../models/place.dart';
import '../../widgets/location_search.dart';
import '../../widgets/fare_map.dart';
import '../../widgets/route_information.dart';
import '../../services/google_geocoding_service.dart';
import '../../services/fare_service.dart';

class FareCalculatorScreen extends StatefulWidget {
  const FareCalculatorScreen({super.key});

  @override
  State<FareCalculatorScreen> createState() => _FareCalculatorScreenState();
}

class _FareCalculatorScreenState extends State<FareCalculatorScreen> {
  final MapController _controller = MapController();
  final GoogleGeocodingService _reverseService = GoogleGeocodingService();
  final FareService _fareService = FareService();

  String? pickupBarangay;
  String? destinationBarangay;
  String? destinationZone;
  double officialFare = 0;
  bool covered = false;
  String fareMessage = "";
  Place? pickup;
  Place? destination;
  bool isSearching = false;
  bool discounted = false;
  bool isSingleOccupant = true;
  bool get _isNightTime {
    final currentHour = DateTime.now().hour;
    return currentHour >= 18 || currentHour < 6;
  }

  void _moveMap() {
    if (pickup != null && destination != null) {
      final bounds = LatLngBounds.fromPoints([
        LatLng(pickup!.latitude, pickup!.longitude),
        LatLng(destination!.latitude, destination!.longitude),
      ]);

      _controller.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.only(
            left: 60,
            right: 60,
            top: 120,
            bottom: 250,
          ),
        ),
      );
    } else if (pickup != null) {
      _controller.move(LatLng(pickup!.latitude, pickup!.longitude), 16);
    }

    setState(() {});
  }

  final Distance _distance = const Distance();

  double get routeDistance {
    if (pickup == null || destination == null) {
      return 0;
    }

    final meters = _distance(
      LatLng(pickup!.latitude, pickup!.longitude),
      LatLng(destination!.latitude, destination!.longitude),
    );

    return meters / 1000;
  }

  Future<void> _calculateOfficialFare() async {
    if (pickup == null || destination == null) return;

    pickupBarangay = await _reverseService.getBarangay(
      latitude: pickup!.latitude,
      longitude: pickup!.longitude,
    );

    destinationBarangay = await _reverseService.getBarangay(
      latitude: destination!.latitude,
      longitude: destination!.longitude,
    );

    if (pickupBarangay == null || destinationBarangay == null) {
      setState(() {
        covered = false;
        fareMessage = "Unable to determine barangay.";
      });
      return;
    }

    final result = await _fareService.calculateFare(
      pickupBarangay: pickupBarangay!,
      destinationBarangay: destinationBarangay!,
      discounted: discounted,
      nightFare: _isNightTime,
      isSingleOccupant: isSingleOccupant,
    );

    setState(() {
      covered = result["covered"];

      if (covered) {
        officialFare = result["fare"];
        destinationZone = result["zone"] ?? result["destinationZone"];
        fareMessage = "Official Fare";
      } else {
        officialFare = 0;
        destinationZone = null;
        fareMessage = result["message"];
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("RTODA Fare Calculator")),
      body: SafeArea(
        child: Stack(
          children: [
            // 1. Map Layer
            Positioned.fill(
              child: FareMap(
                controller: _controller,
                pickup: pickup == null
                    ? null
                    : LatLng(pickup!.latitude, pickup!.longitude),
                destination: destination == null
                    ? null
                    : LatLng(destination!.latitude, destination!.longitude),
              ),
            ),

            // 2. Search Card
            Positioned(
              top: 12,
              left: 16,
              right: 16,
              child: Material(
                elevation: 8,
                borderRadius: BorderRadius.circular(22),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: const [
                      BoxShadow(
                        blurRadius: 18,
                        offset: Offset(0, 8),
                        color: Colors.black12,
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      LocationSearch(
                        label: "Pickup",
                        icon: Icons.my_location,
                        allowCurrentLocation: true,
                        onSearchStarted: () =>
                            setState(() => isSearching = true),
                        onSearchFinished: () =>
                            setState(() => isSearching = false),
                        onSelected: (place) async {
                          setState(() {
                            pickup = place;
                            isSearching = false;
                          });

                          _moveMap();

                          if (destination != null) {
                            await _calculateOfficialFare();
                          }
                        },
                      ),

                      const SizedBox(height: 10),

                      LocationSearch(
                        label: "Destination",
                        icon: Icons.location_on,
                        allowCurrentLocation: true,
                        onSearchStarted: () =>
                            setState(() => isSearching = true),
                        onSearchFinished: () =>
                            setState(() => isSearching = false),
                        onSelected: (place) async {
                          setState(() {
                            destination = place;
                            isSearching = false;
                          });

                          _moveMap();

                          if (pickup != null) {
                            await _calculateOfficialFare();
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // 3. Draggable Route Information Sheet
            if (pickup != null && destination != null && !isSearching)
              DraggableScrollableSheet(
                initialChildSize: 0.13,
                minChildSize: 0.11,
                maxChildSize: 0.65,
                snap: true,
                snapSizes: const [0.13, 0.35, 0.65],
                builder: (context, scrollController) {
                  return RouteInformationCard(
                    controller: scrollController,
                    pickup: pickup,
                    destination: destination,
                    distance: routeDistance,
                    pickupBarangay: pickupBarangay,
                    destinationBarangay: destinationBarangay,
                    destinationZone: destinationZone,
                    officialFare: officialFare,
                    covered: covered,
                    message: fareMessage,
                    isSingleOccupant: isSingleOccupant,
                    discounted: discounted,
                    nightFare: _isNightTime,

                    onPassengerChanged: (value) async {
                      setState(() {
                        isSingleOccupant = value;
                      });

                      await _calculateOfficialFare();
                    },

                    onDiscountChanged: (value) async {
                      setState(() {
                        discounted = value;
                      });

                      await _calculateOfficialFare();
                    },
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
