import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';

import '../../services/sos_service.dart';

class SOSScreen extends StatefulWidget {
  final String userRole;

  const SOSScreen({super.key, required this.userRole});

  @override
  State<SOSScreen> createState() => _SOSScreenState();
}

class _SOSScreenState extends State<SOSScreen> {
  final _descriptionController = TextEditingController();

  bool _sending = false;
  bool _sent = false;

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  // ============================================================
  // GET CURRENT LOCATION
  // ============================================================

  Future<Position> _getLocation() async {
    final enabled = await Geolocator.isLocationServiceEnabled();

    if (!enabled) {
      throw Exception('Please turn on your device location.');
    }

    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      throw Exception('Location permission was denied.');
    }

    if (permission == LocationPermission.deniedForever) {
      throw Exception(
        'Location permission is permanently denied. '
        'Please enable it in your device settings.',
      );
    }

    return await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
  }

  // ============================================================
  // GET LOCATION NAME
  // ============================================================

  Future<String?> _getLocationName(Position position) async {
    try {
      final placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      if (placemarks.isEmpty) {
        return null;
      }

      final place = placemarks.first;

      final parts = <String>[];

      if (place.street != null && place.street!.trim().isNotEmpty) {
        parts.add(place.street!.trim());
      }

      if (place.subLocality != null && place.subLocality!.trim().isNotEmpty) {
        parts.add(place.subLocality!.trim());
      }

      if (place.locality != null && place.locality!.trim().isNotEmpty) {
        parts.add(place.locality!.trim());
      }

      if (place.administrativeArea != null &&
          place.administrativeArea!.trim().isNotEmpty) {
        parts.add(place.administrativeArea!.trim());
      }

      if (place.country != null && place.country!.trim().isNotEmpty) {
        parts.add(place.country!.trim());
      }

      if (parts.isEmpty) {
        return null;
      }

      return parts.join(', ');
    } catch (e) {
      debugPrint('Reverse geocoding failed: $e');

      return null;
    }
  }

  // ============================================================
  // CONFIRM SOS
  // ============================================================

  Future<void> _confirmSOS() async {
    if (_sending || _sent) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_rounded, color: Colors.red),
              SizedBox(width: 10),
              Expanded(child: Text('Send SOS Alert?')),
            ],
          ),
          content: const Text(
            'This will send an emergency alert to the '
            'RTODA monitoring team and share your current '
            'location.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context, false);
              },
              child: const Text('CANCEL'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () {
                Navigator.pop(context, true);
              },
              child: const Text('SEND SOS'),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      await _sendSOS();
    }
  }

  // ============================================================
  // SEND SOS
  // ============================================================

  Future<void> _sendSOS() async {
    if (_sending || _sent) return;

    setState(() {
      _sending = true;
    });

    try {
      // 1. Get GPS position
      final position = await _getLocation();

      debugPrint('SOS GPS: ${position.latitude}, ${position.longitude}');

      // 2. Convert GPS coordinates to readable location
      final locationName = await _getLocationName(position);

      debugPrint('SOS Location Name: $locationName');

      // 3. Send to Supabase
      await SOSService.sendSOS(
        userRole: widget.userRole,

        latitude: position.latitude,
        longitude: position.longitude,

        locationName: locationName,

        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
      );

      if (!mounted) return;

      setState(() {
        _sending = false;
        _sent = true;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('SOS alert sent to the RTODA monitoring team.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _sending = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to send SOS: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // ============================================================
  // UI
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'SOS Alert',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),

      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),

          child: Column(
            children: [
              const SizedBox(height: 20),

              // SOS ICON
              Container(
                width: 110,
                height: 110,

                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(.10),
                  shape: BoxShape.circle,
                ),

                child: const Icon(
                  Icons.sos_rounded,
                  color: Colors.red,
                  size: 70,
                ),
              ),

              const SizedBox(height: 22),

              const Text(
                'Emergency SOS',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
              ),

              const SizedBox(height: 10),

              Text(
                _sent
                    ? 'Your SOS alert has been sent. '
                          'The RTODA monitoring team has been notified.'
                    : 'Use this button only when you need '
                          'urgent assistance from the RTODA monitoring team.',
                textAlign: TextAlign.center,

                style: const TextStyle(color: Colors.black54, height: 1.5),
              ),

              const SizedBox(height: 28),

              // DESCRIPTION
              TextField(
                controller: _descriptionController,
                enabled: !_sending && !_sent,
                maxLines: 4,

                decoration: InputDecoration(
                  labelText: 'What happened? (Optional)',
                  hintText: 'Briefly describe the emergency...',
                  alignLabelWithHint: true,

                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // SEND SOS BUTTON
              SizedBox(
                width: double.infinity,
                height: 58,

                child: ElevatedButton.icon(
                  onPressed: _sending || _sent ? null : _confirmSOS,

                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,

                    disabledBackgroundColor: _sent ? Colors.green : Colors.grey,

                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),

                  icon: _sending
                      ? const SizedBox(
                          width: 22,
                          height: 22,

                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : Icon(
                          _sent
                              ? Icons.check_circle_rounded
                              : Icons.sos_rounded,
                        ),

                  label: Text(
                    _sending
                        ? 'SENDING SOS...'
                        : _sent
                        ? 'SOS SENT'
                        : 'SEND SOS ALERT',

                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // INFORMATION
              Container(
                padding: const EdgeInsets.all(14),

                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(.08),
                  borderRadius: BorderRadius.circular(14),
                ),

                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,

                  children: [
                    Icon(Icons.info_outline_rounded, color: Colors.orange),

                    SizedBox(width: 10),

                    Expanded(
                      child: Text(
                        'Your current GPS location will be '
                        'included with the SOS alert. '
                        'The location name will also be '
                        'identified when available.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.black54,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
