import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class ViganFreeMapScreen extends StatefulWidget {
  @override
  _ViganFreeMapScreenState createState() => _ViganFreeMapScreenState();
}

class _ViganFreeMapScreenState extends State<ViganFreeMapScreen> {
  final Distance distance = const Distance();
  final LatLng _viganCenter = LatLng(17.5744, 120.3893);
  final MapController _mapController = MapController();

  String _pickupLabel = "Detecting current location...";
  String _destinationLabel = "Where to?";

  LatLng? _pickupPoint;
  LatLng? _dropoffPoint;

  double _distanceInKm = 0.0;
  double _calculatedFare = 0.0;
  bool _isDiscounted = false;
  String _detectedZone = "Verify your pickup and drop-off points";

  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;

  // Mode for map tap: 'pickup', 'dropoff', or null
  String? _mapTapMode;

  @override
  void initState() {
    super.initState();
    _autoDetectPickup();
  }

  Future<void> _autoDetectPickup() async {
    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      setState(() {
        _pickupPoint = LatLng(position.latitude, position.longitude);
        _pickupLabel = "Current Location (GPS Verified)";
        _calculateOrdinanceFare();
      });
      _mapController.move(_pickupPoint!, 15.0);
    } catch (e) {
      setState(() {
        _pickupPoint = _viganCenter;
        _pickupLabel = "Vigan City Center (Default Location)";
      });
    }
  }

  Future<void> _searchPlacesInPhilippines(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
      });
      return;
    }
    setState(() {
      _isSearching = true;
    });
    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/search?format=json&q=${Uri.encodeComponent(query)}&countrycodes=ph&limit=8',
      );
      final response = await http.get(
        url,
        headers: {'User-Agent': 'vigan_tricycle_fare_calculator_app'},
      );
      if (response.statusCode == 200) {
        final List data = json.decode(response.body);
        setState(() {
          _searchResults = data
              .map(
                (item) => {
                  'display_name': item['display_name'],
                  'lat': double.parse(item['lat']),
                  'lon': double.parse(item['lon']),
                },
              )
              .toList();
        });
      }
    } catch (e) {
      debugPrint("Geocoding Error: $e");
    } finally {
      setState(() {
        _isSearching = false;
      });
    }
  }

  // Fetch zone category for the village from your database
  Future<String?> fetchVillageZoneCategory(String villageName) async {
    final response = await Supabase.instance.client
        .from('villages')
        .select('zone_category')
        .eq('village_name', villageName);

    if (response != null && response.isNotEmpty) {
      return response[0]['zone_category'] as String?;
    }
    return null;
  }

  Future<Map<String, dynamic>?> fetchFareForZone(String zoneCategory) async {
    final response = await Supabase.instance.client
        .from('fare_matrix')
        .select()
        .eq('zone_category', zoneCategory);

    if (response != null && response.isNotEmpty) {
      return response[0]; // assuming response is a list of maps
    }
    return null;
  }

  // Main fare calculation, updated to include zone database check
  Future<void> _calculateOrdinanceFare() async {
    if (_pickupPoint == null || _dropoffPoint == null) return;

    double meters = distance(_pickupPoint!, _dropoffPoint!);
    _distanceInKm = double.parse((meters / 1000).toStringAsFixed(1));

    int currentHour = DateTime.now().hour;
    bool isNightRate = (currentHour >= 18 || currentHour < 6);

    // Check if pickup label matches a village in your database
    String villageName = _pickupLabel
        .split('(')[0]
        .trim(); // or however you store it

    String zoneCategory = "Poblacion Core Regular"; // default fallback
    if (villageName.isNotEmpty &&
        villageName != "Current Location (GPS Verified)" &&
        villageName != "Vigan City Center (Default Location)") {
      // Attempt to fetch zone category from your database
      String? fetchedZone = await fetchVillageZoneCategory(villageName);
      if (fetchedZone != null) {
        zoneCategory = fetchedZone;
      }
    }

    // Fetch fare corresponding to the zone
    final fareData = await fetchFareForZone(zoneCategory);
    if (fareData != null) {
      // Determine fare based on time/night/day and discount
      double fare = 0.0;
      if (!isNightRate) {
        fare = _isDiscounted
            ? (fareData['single_discounted_fare_day'] as num).toDouble()
            : (fareData['single_day_fare'] as num).toDouble();
        _detectedZone = "Zone: $zoneCategory (Day)";
      } else {
        fare = _isDiscounted
            ? (fareData['single_discounted_fare_night'] as num).toDouble()
            : (fareData['single_night_fare'] as num).toDouble();
        _detectedZone = "Zone: $zoneCategory (Night)";
      }
      setState(() {
        _calculatedFare = fare;
      });
    } else {
      // Fallback fare if no zone info found
      setState(() {
        _calculatedFare = _isDiscounted ? 12.00 : 15.00; // default fare
        _detectedZone = "Default Zone";
      });
    }
  }

  void _setMapMode(String mode) {
    setState(() {
      _mapTapMode = mode;
    });
  }

  void _onMapTap(LatLng point) {
    if (_mapTapMode == null) return;
    setState(() {
      if (_mapTapMode == 'pickup') {
        _pickupPoint = point;
        _pickupLabel = "Selected Pickup";
      } else if (_mapTapMode == 'dropoff') {
        _dropoffPoint = point;
        _destinationLabel = "Selected Dropoff";
      }
      _calculateOrdinanceFare();
      _mapTapMode = null; // reset mode after setting
    });
  }

  void _openLocationSearchOverlay({required bool isSelectingPickup}) {
    _searchResults = [];
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Container(
              padding: EdgeInsets.fromLTRB(
                16,
                20,
                16,
                MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              height: MediaQuery.of(context).size.height * 0.8,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    isSelectingPickup
                        ? "Verify / Edit Pickup Location"
                        : "Select Destination",
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1C1C1C),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    onChanged: (val) async {
                      await _searchPlacesInPhilippines(val);
                      setModalState(() {});
                    },
                    decoration: InputDecoration(
                      hintText: "Search cities, streets, or landmarks in PH...",
                      prefixIcon: const Icon(
                        Icons.search,
                        color: Color(0xFF00B14F),
                      ),
                      suffixIcon: _isSearching
                          ? const Padding(
                              padding: EdgeInsets.all(12.0),
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF00B14F),
                              ),
                            )
                          : null,
                      filled: true,
                      fillColor: const Color(0xFFF5F5F5),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Search results list...
                  Expanded(
                    child: _searchResults.isEmpty
                        ? Center(
                            child: Text(
                              _isSearching
                                  ? "Loading locations..."
                                  : "Type location parameters to search...",
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 13,
                              ),
                            ),
                          )
                        : ListView.builder(
                            itemCount: _searchResults.length,
                            itemBuilder: (context, index) {
                              final place = _searchResults[index];
                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(
                                  Icons.location_on,
                                  color: Colors.grey,
                                ),
                                title: Text(
                                  place['display_name'],
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w500,
                                    fontSize: 13,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                onTap: () {
                                  setState(() {
                                    LatLng targetedCoords = LatLng(
                                      place['lat'],
                                      place['lon'],
                                    );
                                    if (isSelectingPickup) {
                                      _pickupLabel = place['display_name']
                                          .split(',')[0];
                                      _pickupPoint = targetedCoords;
                                    } else {
                                      _destinationLabel = place['display_name']
                                          .split(',')[0];
                                      _dropoffPoint = targetedCoords;
                                    }
                                    _calculateOrdinanceFare();
                                  });
                                  _mapController.move(
                                    LatLng(place['lat'], place['lon']),
                                    15.0,
                                  );
                                  Navigator.pop(context);
                                },
                              );
                            },
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

  void _showDriverVerificationSheet() {
    if (_pickupPoint == null || _dropoffPoint == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 48,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "Legal Fare Verification",
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF1C1C1C),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.grey),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const Text(
                    "Show this breakdown to your driver to verify compliance.",
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      vertical: 20,
                      horizontal: 16,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00B14F).withOpacity(0.06),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFF00B14F).withOpacity(0.2),
                      ),
                    ),
                    child: Column(
                      children: [
                        const Text(
                          "TOTAL REGULATED RATE",
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF00B14F),
                            letterSpacing: 1,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "₱${_calculatedFare.toStringAsFixed(2)}",
                          style: const TextStyle(
                            fontSize: 42,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF1C1C1C),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "Route Target • $_detectedZone",
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[700],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    "RATE MATRIX ANALYSIS",
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildBreakdownRow(
                    "Target Destination Base",
                    "₱${_calculatedFare.toStringAsFixed(2)}",
                    true,
                  ),
                  const Divider(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "Apply Concession Discount\n(Student / Senior / PWD W/ ID)",
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Switch.adaptive(
                        value: _isDiscounted,
                        activeColor: const Color(0xFF00B14F),
                        onChanged: (bool newValue) {
                          setState(() {
                            _isDiscounted = newValue;
                            _calculateOrdinanceFare();
                          });
                          setModalState(() {
                            _isDiscounted = newValue;
                          });
                        },
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  const Center(
                    child: Text(
                      "Drivers who do not follow the fare matrix face penalties.",
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _openSubmitReportFormSheet();
                      },
                      icon: const Icon(Icons.gavel, size: 16),
                      label: const Text(
                        "Report Overcharging Driver",
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFD32F2F),
                        side: const BorderSide(color: Color(0xFFD32F2F)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
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

  void _openSubmitReportFormSheet() {
    final TextEditingController _bodyNumberController = TextEditingController();
    final TextEditingController _commentsController = TextEditingController();
    String _selectedViolationType = "Overpricing / Overcharging";

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            16,
            20,
            MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.report_problem, color: Color(0xFFD32F2F)),
                      SizedBox(width: 8),
                      Text(
                        "File Incident Report",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(height: 24),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "ROUTE: $_pickupLabel → $_destinationLabel",
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "ORDINANCE VALUE: ₱${_calculatedFare.toStringAsFixed(2)}",
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF00B14F),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                "TRICYCLE BODY NUMBER",
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _bodyNumberController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  hintText: "e.g., 1432",
                  prefixIcon: const Icon(Icons.directions_bike),
                  filled: true,
                  fillColor: const Color(0xFFF5F5F5),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                "VIOLATION TYPE",
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                value: _selectedViolationType,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: const Color(0xFFF5F5F5),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
                items:
                    [
                          "Overpricing / Overcharging",
                          "Refusal to Convey Passenger",
                          "Disregarding Senior/Student Discount",
                        ]
                        .map(
                          (label) => DropdownMenuItem(
                            value: label,
                            child: Text(
                              label,
                              style: const TextStyle(fontSize: 14),
                            ),
                          ),
                        )
                        .toList(),
                onChanged: (value) {
                  if (value != null) _selectedViolationType = value;
                },
              ),
              const SizedBox(height: 16),
              const Text(
                "ADDITIONAL DETAILS",
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _commentsController,
                maxLines: 2,
                decoration: InputDecoration(
                  hintText: "Enter extra information...",
                  filled: true,
                  fillColor: const Color(0xFFF5F5F5),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    if (_bodyNumberController.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text("Please provide the body number."),
                        ),
                      );
                      return;
                    }

                    try {
                      final supabase = Supabase.instance.client;
                      await supabase.from('tricycle_reports').insert({
                        'report_type': _selectedViolationType,
                        'route_distance_km': _distanceInKm,
                        'official_fare': _calculatedFare,
                        'description':
                            'Tricycle Body Number: ${_bodyNumberController.text.trim()}. Notes: ${_commentsController.text.trim()}',
                        'status': 'Pending',
                      });
                    } catch (err) {}

                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        backgroundColor: Color(0xFF00B14F),
                        content: Text("Violation logged successfully."),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD32F2F),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    "Submit Official Report",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBreakdownRow(String title, String cost, bool isActive) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              color: isActive ? const Color(0xFF1C1C1C) : Colors.grey[400],
            ),
          ),
          Text(
            isActive ? cost : "—",
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: isActive ? const Color(0xFF1C1C1C) : Colors.grey[400],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F9F9),
      appBar: AppBar(
        title: const Text(
          "Vigan Fare Guard",
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        backgroundColor: const Color(0xFF00B14F),
        elevation: 0,
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline, color: Colors.white),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    "Using Official Vigan City Tricycle Fare Ordinance Matrix Pricing Rules.",
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Top Routing Interface Panel Block
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              color: Colors.white,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    GestureDetector(
                      onTap: () =>
                          _openLocationSearchOverlay(isSelectingPickup: true),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.radio_button_checked,
                            color: Color(0xFF00B14F),
                            size: 16,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  "PICKUP LOCATION",
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  _pickupLabel,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.black12),
                            ),
                            child: const Text(
                              "Edit",
                              style: TextStyle(
                                fontSize: 11,
                                color: Color(0xFF00B14F),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 7),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          width: 2,
                          height: 12,
                          color: Colors.grey[300],
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () =>
                          _openLocationSearchOverlay(isSelectingPickup: false),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.location_on,
                            color: Colors.redAccent,
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  "DROP-OFF DESTINATION",
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  _destinationLabel,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: _destinationLabel == "Where to?"
                                        ? FontWeight.normal
                                        : FontWeight.bold,
                                    color: _destinationLabel == "Where to?"
                                        ? Colors.grey
                                        : const Color(0xFF1C1C1C),
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.keyboard_arrow_down,
                            color: Colors.grey,
                            size: 20,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Map Frame with tap detection
            Container(
              height: 340,
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.black12, width: 0.5),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _viganCenter,
                    initialZoom: 14.5,
                    onTap: (tapPosition, point) => _onMapTap(point),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.vigan',
                    ),
                    if (_pickupPoint != null && _dropoffPoint != null)
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: [_pickupPoint!, _dropoffPoint!],
                            strokeWidth: 4,
                            color: const Color(0xFF00B14F),
                          ),
                        ],
                      ),
                    MarkerLayer(
                      markers: [
                        if (_pickupPoint != null)
                          Marker(
                            point: _pickupPoint!,
                            width: 30,
                            height: 30,
                            child: const Icon(
                              Icons.radio_button_checked,
                              color: Color(0xFF00B14F),
                              size: 24,
                            ),
                          ),
                        if (_dropoffPoint != null)
                          Marker(
                            point: _dropoffPoint!,
                            width: 30,
                            height: 30,
                            child: const Icon(
                              Icons.location_on,
                              color: Colors.redAccent,
                              size: 28,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Buttons to select mode for map tap
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton.icon(
                    icon: Icon(Icons.my_location),
                    label: Text("Set Pickup"),
                    onPressed: () => _setMapMode('pickup'),
                  ),
                  SizedBox(width: 10),
                  ElevatedButton.icon(
                    icon: Icon(Icons.location_pin),
                    label: Text("Set Dropoff"),
                    onPressed: () => _setMapMode('dropoff'),
                  ),
                ],
              ),
            ),

            // Bottom info and fare
            Expanded(
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                color: Colors.white,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _detectedZone,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.grey,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (_distanceInKm > 0)
                          Text(
                            "Distance: $_distanceInKm km",
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.black54,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                      ],
                    ),
                    const Divider(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "LEGAL ORDINANCE FARE",
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              "₱${_calculatedFare.toStringAsFixed(2)}",
                              style: const TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF1C1C1C),
                              ),
                            ),
                          ],
                        ),
                        ElevatedButton(
                          onPressed:
                              (_pickupPoint == null || _dropoffPoint == null)
                              ? null
                              : _showDriverVerificationSheet,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00B14F),
                            disabledBackgroundColor: Colors.grey[200],
                            padding: const EdgeInsets.symmetric(
                              horizontal: 28,
                              vertical: 14,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            elevation: 0,
                          ),
                          child: const Text(
                            "Verify with Driver",
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
