import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../models/place.dart';
import '../services/google_geocoding_service.dart';
import '../services/google_places_service.dart';
import '../theme/app_theme.dart';

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
  bool _hasSearched = false;

  String _latestQuery = '';
  int _searchId = 0;

  // ============================================================
  // SEARCH
  // ============================================================
  Future<void> _search(String value) async {
    final trimmed = value.trim();

    if (trimmed.length < 3) {
      if (!mounted) return;
      setState(() {
        _results = [];
        _loading = false;
        _hasSearched = false;
      });
      return;
    }

    _latestQuery = value;
    final currentQuery = value;
    final myId = ++_searchId;

    if (!mounted) return;
    setState(() {
      _loading = true;
      _hasSearched = false;
    });

    try {
      final places = await _service.searchPlaces(value);

      // Ignore stale responses (user typed more, or GPS fired)
      if (myId != _searchId) return;
      if (currentQuery != _latestQuery) return;
      if (!mounted) return;

      setState(() {
        _results = places;
        _loading = false;
        _hasSearched = true;
      });
    } catch (e) {
      debugPrint('SEARCH ERROR: $e');
      if (myId != _searchId) return;
      if (!mounted) return;
      setState(() {
        _results = [];
        _loading = false;
        _hasSearched = true;
      });
    }
  }

  // ============================================================
  // CURRENT LOCATION
  // ============================================================
  Future<void> _useCurrentLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showError('Please turn on your device location.');
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _showError('Location permission denied.');
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        _showError(
          'Location permission is permanently denied. '
          'Please enable it in your device settings.',
        );
        return;
      }

      final myId = ++_searchId;
      setState(() => _loading = true);

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      ).timeout(const Duration(seconds: 20));

      final barangay = await _reverseService.getFullAddress(
        latitude: position.latitude,
        longitude: position.longitude,
      );

      if (myId != _searchId) return;
      if (!mounted) return;

      final currentPlace = Place(
        name: barangay ?? 'Current Location',
        fullAddress: 'Current GPS Location',
        barangay: barangay ?? '',
        latitude: position.latitude,
        longitude: position.longitude,
      );

      _controller.text = currentPlace.name;
      widget.onSelected(currentPlace);
      widget.onSearchFinished?.call();
      _focusNode.unfocus();
    } catch (e) {
      debugPrint('GPS ERROR: $e');
      if (mounted) {
        _showError('Could not get your current location.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ============================================================
  // HELPERS
  // ============================================================
  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  void _clearSearch() {
    _controller.clear();
    setState(() {
      _results = [];
      _loading = false;
      _hasSearched = false;
    });
  }

  void _selectPlace(Place place) {
    _controller.text = place.name;
    widget.onSelected(place);
    widget.onSearchFinished?.call();
    setState(() {
      _results = [];
      _hasSearched = false;
    });
    _focusNode.unfocus();
  }

  // ============================================================
  // LIFECYCLE
  // ============================================================
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

  // ============================================================
  // BUILD
  // ============================================================
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppColors.text,
          ),
        ),
        const SizedBox(height: 8),

        // ── Search field ──────────────────────────────────────
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _controller,
          builder: (context, value, _) {
            return TextField(
              focusNode: _focusNode,
              controller: _controller,
              textInputAction: TextInputAction.search,
              onSubmitted: (v) {
                _debounce?.cancel();
                _search(v);
              },
              onTap: () {
                widget.onSearchStarted?.call();
              },
              onChanged: (v) {
                if (_debounce?.isActive ?? false) _debounce!.cancel();
                _debounce = Timer(
                  const Duration(milliseconds: 700),
                  () => _search(v),
                );
                // Rebuild so the clear button appears/disappears.
                setState(() {});
              },
              decoration: InputDecoration(
                prefixIcon: Icon(widget.icon, color: AppColors.green),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_loading)
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.green,
                          ),
                        ),
                      ),
                    if (!_loading && value.text.isNotEmpty)
                      IconButton(
                        icon: const Icon(
                          Icons.close,
                          size: 18,
                          color: AppColors.muted,
                        ),
                        tooltip: 'Clear',
                        onPressed: _clearSearch,
                      ),
                    if (widget.allowCurrentLocation)
                      IconButton(
                        icon: const Icon(
                          Icons.my_location,
                          color: AppColors.green,
                        ),
                        tooltip: 'Use current location',
                        onPressed: _loading ? null : _useCurrentLocation,
                      ),
                  ],
                ),
                hintText: 'Search location…',
                filled: true,
                fillColor: AppColors.card,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(
                    color: AppColors.green,
                    width: 1.5,
                  ),
                ),
              ),
            );
          },
        ),

        // ── Min-chars hint ────────────────────────────────────
        if (_controller.text.isNotEmpty &&
            _controller.text.trim().length < 3 &&
            !_loading) ...[
          const Padding(
            padding: EdgeInsets.only(top: 4, left: 4),
            child: Text(
              'Type at least 3 characters to search',
              style: TextStyle(fontSize: 11, color: AppColors.muted),
            ),
          ),
        ],

        // ── Results ───────────────────────────────────────────
        if (_results.isNotEmpty) _buildResultsDropdown(),

        // ── Empty results ────────────────────────────────────
        if (_hasSearched && _results.isEmpty && !_loading)
          Container(
            margin: const EdgeInsets.only(top: 5),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: const Row(
              children: [
                Icon(Icons.search_off, color: AppColors.muted, size: 20),
                SizedBox(width: 8),
                Text(
                  'No places found',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildResultsDropdown() {
    return Container(
      margin: const EdgeInsets.only(top: 5),
      constraints: const BoxConstraints(maxHeight: 240),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: ListView.separated(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        itemCount: _results.length,
        separatorBuilder: (_, __) =>
            const Divider(height: 1, color: AppColors.borderLight),
        itemBuilder: (context, index) {
          final place = _results[index];
          return ListTile(
            leading: const Icon(
              Icons.location_on,
              color: AppColors.green,
              size: 20,
            ),
            title: Text(
              place.name,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.text,
              ),
            ),
            subtitle: Text(
              place.fullAddress,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
            onTap: () => _selectPlace(place),
          );
        },
      ),
    );
  }
}
