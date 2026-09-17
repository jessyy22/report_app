import 'package:flutter/material.dart';
import '../models/place.dart';
import '../services/google_places_service.dart';
import 'package:geolocator/geolocator.dart';
import '../services/google_geocoding_service.dart';
import 'dart:async';

class LocationSearch extends StatefulWidget {
  final String label;
  final IconData icon;
  final Function(Place) onSelected;
  final bool allowCurrentLocation;

  final VoidCallback? onSearchStarted;
  final VoidCallback? onSearchFinished;

  const LocationSearch({
    super.key,
    required this.label,
    required this.icon,
    required this.onSelected,
    this.allowCurrentLocation = false,
    this.onSearchStarted,
    this.onSearchFinished,
  });

  @override
  State<LocationSearch> createState() => _LocationSearchState();
}

class _LocationSearchState extends State<LocationSearch> {
  final TextEditingController _controller = TextEditingController();
  final GooglePlacesService _service = GooglePlacesService();
  final GoogleGeocodingService _reverseService = GoogleGeocodingService();
  final FocusNode _focusNode = FocusNode();

  Timer? _debounce;

  List<Place> _results = [];
  bool _loading = false;

  String _latestQuery = "";

  Future<void> _search(String value) async {
    if (value.trim().length < 3) {
      if (!mounted) return;

      setState(() {
        _results = [];
        _loading = false;
      });

      return;
    }

    _latestQuery = value;
    final currentQuery = value;

    if (!mounted) return;

    setState(() {
      _loading = true;
    });

    final places = await _service.searchPlaces(value);

    // Ignore outdated responses
    if (currentQuery != _latestQuery) return;

    if (!mounted) return;

    setState(() {
      _results = places;
      _loading = false;
    });
  }

  Future<void> _useCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }

      if (permission == LocationPermission.deniedForever) return;

      setState(() => _loading = true);

      // Using modern geolocator locationSettings syntax
      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      String? barangay = await _reverseService.getBarangay(
        latitude: position.latitude,
        longitude: position.longitude,
      );

      Place currentPlace = Place(
        name: barangay ?? "Current Location",
        fullAddress: "Current GPS Location",
        barangay: barangay ?? "",
        latitude: position.latitude,
        longitude: position.longitude,
      );

      _controller.text = currentPlace.name;
      widget.onSelected(currentPlace);
    } catch (e) {
      print("GPS Error: $e");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void initState() {
    super.initState();

    _focusNode.addListener(() {
      if (!_focusNode.hasFocus) {
        widget.onSearchFinished?.call();
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label, style: const TextStyle(fontWeight: FontWeight.bold)),

        const SizedBox(height: 8),

        TextField(
          focusNode: _focusNode,
          controller: _controller,
          onTap: () {
            widget.onSearchStarted?.call();
          },

          onChanged: (value) {
            widget.onSearchStarted?.call();

            if (_debounce?.isActive ?? false) {
              _debounce!.cancel();
            }

            _debounce = Timer(const Duration(milliseconds: 700), () {
              _search(value);
            });
          },
          decoration: InputDecoration(
            prefixIcon: Icon(widget.icon),

            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                if (widget.allowCurrentLocation)
                  IconButton(
                    icon: const Icon(Icons.my_location, color: Colors.green),
                    tooltip: "Use Current Location",
                    onPressed: _useCurrentLocation,
                  ),
              ],
            ),

            hintText: "Search location...",
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),

        if (_results.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 5),
            constraints: const BoxConstraints(maxHeight: 220),

            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.black12),
            ),

            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _results.length,
              itemBuilder: (context, index) {
                final place = _results[index];

                return ListTile(
                  leading: const Icon(Icons.location_on),

                  title: Text(place.name),

                  subtitle: Text(
                    place.fullAddress,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),

                  onTap: () {
                    _controller.text = place.name;

                    widget.onSelected(place);
                    widget.onSearchFinished?.call();
                    setState(() {
                      _results.clear();
                    });

                    FocusScope.of(context);
                  },
                );
              },
            ),
          ),
      ],
    );
  }
}
