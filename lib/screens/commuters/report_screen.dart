import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart';
import '../../services/notification_service.dart';
import '../../services/google_geocoding_service.dart';
import '../../services/reverse_geocoding_service.dart';

class ReportForm extends StatefulWidget {
  const ReportForm({super.key});

  @override
  State<ReportForm> createState() => _ReportFormState();
}

enum ReportType { reportNow, lateReport }

class _ReportFormState extends State<ReportForm> {
  final _formKey = GlobalKey<FormState>();

  final _date = TextEditingController();
  final _time = TextEditingController();
  final _driver = TextEditingController();
  final _location = TextEditingController();
  final _name = TextEditingController();
  final _address = TextEditingController();
  final _contact = TextEditingController();
  final _body = TextEditingController();
  final _lateReason = TextEditingController();

  final _picker = ImagePicker();

  final GoogleGeocodingService _googleGeocoding = GoogleGeocodingService();

  final ReverseGeocodingService _reverseGeocoding = ReverseGeocodingService();

  String _tricycleId = '';
  String _bodyError = '';

  String? _selectedItem;

  bool _loadingProfile = true;
  bool _searching = false;
  bool _uploading = false;
  bool _locating = false;
  bool _declarationAccepted = false;

  File? _image;

  double? _lat;
  double? _lng;
  double? _locationAccuracy;

  ReportType _reportType = ReportType.reportNow;

  final items = [
    'Overcharging',
    'Abuse',
    'Discriminate / Refusal to convey',
    'Discourteous / Arrogant Driver',
    'Overloading',
    'Illegal Parking',
    'No Mayors Permit',
    'No Drivers Permit',
    'Others',
  ];

  @override
  void initState() {
    super.initState();

    _setDateTime();
    _loadProfile();
    _getLocation();
  }

  Future<void> _loadProfile() async {
    final db = Supabase.instance.client;
    final user = db.auth.currentUser;

    if (user == null) {
      if (mounted) {
        setState(() => _loadingProfile = false);
      }
      return;
    }

    try {
      final data = await db
          .from('commuter_profiles')
          .select('id, full_name, phone_number')
          .eq('id', user.id)
          .maybeSingle();

      if (!mounted) return;

      if (data == null) {
        setState(() => _loadingProfile = false);

        _show('No commuter profile was found for this account.', error: true);

        return;
      }

      _name.text = (data['full_name'] ?? '').toString();
      _contact.text = (data['phone_number'] ?? '').toString();

      setState(() => _loadingProfile = false);
    } catch (e) {
      debugPrint('Profile error: $e');

      if (mounted) {
        setState(() => _loadingProfile = false);

        _show('Unable to load commuter information.', error: true);
      }
    }
  }

  void _setDateTime() {
    final now = DateTime.now();

    _date.text = DateFormat('yyyy-MM-dd').format(now);
    _time.text = DateFormat('hh:mm a').format(now);
  }

  Future<Position?> _getAccuratePosition() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();

      if (!serviceEnabled) {
        debugPrint('GPS: Location services are disabled.');
        return null;
      }

      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();

        if (permission == LocationPermission.denied) {
          debugPrint('GPS: Location permission denied.');
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        debugPrint('GPS: Location permission permanently denied.');
        return null;
      }

      final accuracyStatus = await Geolocator.getLocationAccuracy();
      debugPrint('GPS permission accuracy: $accuracyStatus');

      if (accuracyStatus == LocationAccuracyStatus.reduced) {
        debugPrint('GPS WARNING: Phone is using approximate/reduced location.');
      }

      Position? bestPosition;

      final completer = Completer<Position?>();
      StreamSubscription<Position>? subscription;

      subscription =
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 0,
            ),
          ).listen(
            (Position position) {
              final age = DateTime.now().difference(position.timestamp).abs();

              debugPrint(
                'GPS update: '
                '${position.latitude}, '
                '${position.longitude} '
                'accuracy=${position.accuracy}m '
                'age=${age.inSeconds}s '
                'mocked=${position.isMocked}',
              );

              // Ignore old/stale readings.
              if (age > const Duration(seconds: 15)) {
                debugPrint('GPS: Ignored stale location.');
                return;
              }

              // Ignore mocked locations.
              if (position.isMocked) {
                debugPrint('GPS: Ignored mocked location.');
                return;
              }

              if (bestPosition == null ||
                  position.accuracy < bestPosition!.accuracy) {
                bestPosition = position;

                debugPrint(
                  'GPS: New best position '
                  '${position.latitude}, ${position.longitude} '
                  'accuracy=${position.accuracy}m',
                );
              }

              // Good enough to use immediately.
              if (position.accuracy <= 20 && !completer.isCompleted) {
                completer.complete(position);
              }
            },
            onError: (error) {
              debugPrint('GPS stream error: $error');

              if (!completer.isCompleted) {
                completer.complete(bestPosition);
              }
            },
          );

      // Give the phone up to 30 seconds to provide a fresh GPS fix.
      Future.delayed(const Duration(seconds: 30), () {
        if (!completer.isCompleted) {
          completer.complete(bestPosition);
        }
      });

      final position = await completer.future;

      await subscription.cancel();

      if (position == null) {
        debugPrint('GPS: No valid fresh location received.');
        return null;
      }

      debugPrint(
        'GPS selected: '
        '${position.latitude}, ${position.longitude} '
        'accuracy=${position.accuracy}m '
        'timestamp=${position.timestamp}',
      );

      return position;
    } catch (e) {
      debugPrint('GPS error: $e');
      return null;
    }
  }

  Future<String?> _getBarangay(double latitude, double longitude) async {
    try {
      final googleResult = await _googleGeocoding.getBarangay(
        latitude: latitude,
        longitude: longitude,
      );

      if (googleResult != null && googleResult.trim().isNotEmpty) {
        debugPrint('Google Geocoding Barangay: $googleResult');

        return googleResult.trim();
      }
    } catch (e) {
      debugPrint('Google Geocoding failed: $e');
    }

    try {
      final osmResult = await _reverseGeocoding.getBarangay(
        latitude: latitude,
        longitude: longitude,
      );

      if (osmResult != null && osmResult.trim().isNotEmpty) {
        debugPrint('OSM Geocoding Barangay: $osmResult');

        return osmResult.trim();
      }
    } catch (e) {
      debugPrint('OSM Reverse Geocoding failed: $e');
    }

    return null;
  }

  Future<String?> _getReadableLocation(
    double latitude,
    double longitude,
  ) async {
    try {
      final googleResult = await _googleGeocoding.getFullAddress(
        latitude: latitude,
        longitude: longitude,
      );

      if (googleResult != null && googleResult.trim().isNotEmpty) {
        debugPrint('Google Full Address: $googleResult');
        return googleResult.trim();
      }
    } catch (e) {
      debugPrint('Google Full Address failed: $e');
    }

    try {
      final osmResult = await _reverseGeocoding.getFullAddress(
        latitude: latitude,
        longitude: longitude,
      );

      if (osmResult != null && osmResult.trim().isNotEmpty) {
        debugPrint('OSM Full Address: $osmResult');
        return osmResult.trim();
      }
    } catch (e) {
      debugPrint('OSM Full Address failed: $e');
    }

    try {
      final places = await placemarkFromCoordinates(latitude, longitude);

      if (places.isNotEmpty) {
        final place = places.first;

        final parts = [
          place.street,
          place.subLocality,
          place.locality,
          place.subAdministrativeArea,
          place.administrativeArea,
          place.postalCode,
          place.country,
        ].where((value) => value != null && value.trim().isNotEmpty);

        final address = parts.join(', ');

        if (address.isNotEmpty) {
          debugPrint('Device Full Address: $address');
          return address;
        }
      }
    } catch (e) {
      debugPrint('Device reverse geocoding failed: $e');
    }

    return null;
  }

  Future<void> _getLocation() async {
    if (!mounted) return;

    setState(() => _locating = true);

    try {
      final position = await _getAccuratePosition();

      if (position == null) {
        if (mounted) {
          _show(
            'Unable to get your current location. '
            'Please make sure GPS is enabled.',
            error: true,
          );
        }

        return;
      }

      _lat = position.latitude;
      _lng = position.longitude;
      _locationAccuracy = position.accuracy;

      debugPrint(
        'Selected GPS location: '
        '$_lat, $_lng '
        'accuracy=${_locationAccuracy}m',
      );

      final readableLocation = await _getReadableLocation(
        position.latitude,
        position.longitude,
      );

      if (!mounted) return;

      setState(() {
        _location.text =
            readableLocation ?? '${position.latitude}, ${position.longitude}';
      });
    } catch (e) {
      debugPrint('Location error: $e');

      if (mounted) {
        _show('Could not retrieve your location.', error: true);
      }
    } finally {
      if (mounted) {
        setState(() => _locating = false);
      }
    }
  }

  Future<void> _lookupDriver(String value) async {
    final digits = value.trim();

    if (digits.isEmpty) {
      if (mounted) {
        setState(() {
          _tricycleId = '';
          _bodyError = '';
        });
      }

      return;
    }

    if (!RegExp(r'^\d+$').hasMatch(digits)) {
      if (mounted) {
        setState(() {
          _bodyError = 'Please enter numbers only.';
          _tricycleId = '';
        });
      }

      return;
    }

    final body = 'VGN-$digits';

    if (mounted) {
      setState(() {
        _searching = true;
        _bodyError = '';
      });
    }

    try {
      final db = Supabase.instance.client;

      final tricycle = await db
          .from('tricycles')
          .select('tricycle_id, body_number')
          .eq('body_number', body)
          .maybeSingle();

      if (tricycle == null) {
        if (mounted) {
          setState(() {
            _bodyError = 'Body number not found in database.';
            _tricycleId = '';
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _tricycleId = tricycle['tricycle_id'].toString();
            _bodyError = '';
          });
        }
      }
    } catch (e) {
      debugPrint('Body number lookup error: $e');

      if (mounted) {
        setState(() {
          _bodyError = 'Database lookup error.';
          _tricycleId = '';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _searching = false);
      }
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final file = await _picker.pickImage(source: source, imageQuality: 80);

      if (file != null && mounted) {
        setState(() {
          _image = File(file.path);
        });
      }
    } catch (e) {
      _show('Error selecting image: $e', error: true);
    }
  }

  Future<void> _pickLocation() async {
    if (mounted) {
      setState(() => _locating = true);
    }

    try {
      var permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _show('Location permission is required.', error: true);

        return;
      }

      if (!mounted) return;

      final result = await Navigator.push<LatLng>(
        context,
        MaterialPageRoute(builder: (_) => const IncidentLocationPicker()),
      );

      if (result == null) return;

      _lat = result.latitude;
      _lng = result.longitude;

      final readableLocation = await _getReadableLocation(
        result.latitude,
        result.longitude,
      );

      if (!mounted) return;

      setState(() {
        _location.text =
            readableLocation ?? '${result.latitude}, ${result.longitude}';
      });
    } catch (e) {
      debugPrint('Location picker error: $e');

      _show('Could not retrieve location: $e', error: true);
    } finally {
      if (mounted) {
        setState(() => _locating = false);
      }
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_bodyError.isNotEmpty || _tricycleId.isEmpty) {
      _show('Please enter a valid verified body number.', error: true);

      return;
    }

    if (!_declarationAccepted) {
      _show('Please confirm the declaration before submitting.', error: true);

      return;
    }

    final db = Supabase.instance.client;
    final user = db.auth.currentUser;

    if (user == null) {
      _show('You must be logged in.', error: true);

      return;
    }

    if (_lat == null || _lng == null) {
      _show('Please wait for your location to be detected.', error: true);

      return;
    }

    if (_name.text.trim().isEmpty || _contact.text.trim().isEmpty) {
      await _loadProfile();

      if (_name.text.trim().isEmpty || _contact.text.trim().isEmpty) {
        return;
      }
    }

    if (mounted) {
      setState(() => _uploading = true);
    }

    try {
      String? imageUrl;

      if (_image != null) {
        final extension = _image!.path.split('.').last;

        final path =
            'evidence/${user.id}_${DateTime.now().millisecondsSinceEpoch}.$extension';

        await db.storage
            .from('evidence')
            .upload(
              path,
              _image!,
              fileOptions: const FileOptions(
                cacheControl: '3600',
                upsert: true,
              ),
            );

        imageUrl = db.storage.from('evidence').getPublicUrl(path);
      }

      await db.from('reports').insert({
        'user_id': user.id,

        'body_number': 'VGN-${_body.text.trim()}',

        'tricycle_id': _tricycleId,

        'reported_driver_name': _driver.text.trim().isEmpty
            ? null
            : _driver.text.trim(),

        'violation': _selectedItem,

        'location': _location.text.trim(),

        'latitude': _lat,

        'longitude': _lng,

        'incidentdate': _date.text,

        'incidenttime': _time.text,

        'evidence_url': imageUrl,

        'status': 'Pending',

        'complainantname': _name.text.trim(),

        'address': _address.text.trim().isEmpty ? null : _address.text.trim(),

        'contact': _contact.text.trim(),

        'report_type': _reportType == ReportType.reportNow
            ? 'Report Now'
            : 'Late Report',

        'late_report_reason': _reportType == ReportType.lateReport
            ? _lateReason.text.trim()
            : null,
      });

      try {
        await NotificationService.sendPushToRole(
          role: 'admin_staff',
          title: 'New Report Received',
          message:
              'A new ${_selectedItem ?? 'offense'} report was submitted for body number VGN-${_body.text.trim()}.',
          type: 'report',
        );
      } catch (e) {
        debugPrint('Notification error: $e');
      }

      if (!mounted) return;

      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: const Text('Report Submitted'),
          content: const Text(
            'Your report was submitted successfully and safely logged.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );

      _reset();
      _setDateTime();
      _getLocation();
    } catch (e) {
      _show('Submission Error: $e', error: true);
    } finally {
      if (mounted) {
        setState(() => _uploading = false);
      }
    }
  }

  void _reset() {
    _formKey.currentState?.reset();

    setState(() {
      _selectedItem = null;

      _tricycleId = '';
      _bodyError = '';

      _image = null;

      _body.clear();
      _driver.clear();
      _location.clear();

      _date.clear();
      _time.clear();

      _lateReason.clear();

      _lat = null;
      _lng = null;
      _locationAccuracy = null;

      _reportType = ReportType.reportNow;
      _declarationAccepted = false;
    });
  }

  Future<void> _pickDate() async {
    if (_reportType == ReportType.reportNow) {
      return;
    }

    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2025),
      lastDate: DateTime.now(),
    );

    if (date != null && mounted) {
      setState(() {
        _date.text = DateFormat('yyyy-MM-dd').format(date);
      });
    }
  }

  Future<void> _pickTime() async {
    if (_reportType == ReportType.reportNow) {
      return;
    }

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );

    if (time != null && mounted) {
      setState(() {
        _time.text = time.format(context);
      });
    }
  }

  void _show(String text, {bool error = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: error ? Colors.redAccent : null,
      ),
    );
  }

  InputDecoration _input(
    String label,
    IconData icon, {
    String? hint,
    Widget? suffix,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon, color: Colors.green),
      suffixIcon: suffix,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.green, width: 2),
      ),
    );
  }

  Widget _header(String text, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 4),
      child: Row(
        children: [
          Icon(icon, color: Colors.green),
          const SizedBox(width: 8),
          Text(
            text,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    for (final controller in [
      _date,
      _time,
      _driver,
      _location,
      _name,
      _address,
      _contact,
      _body,
      _lateReason,
    ]) {
      controller.dispose();
    }

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),

      appBar: AppBar(
        title: const Text(
          'RTODA Public Complaint Desk',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
        backgroundColor: Colors.green,
      ),

      body: _uploading
          ? const Center(child: CircularProgressIndicator(color: Colors.green))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            _header('Report Type', Icons.assignment),

                            RadioListTile<ReportType>(
                              title: const Text('Report Now'),
                              subtitle: const Text(
                                'Use current date, time, and location.',
                              ),
                              value: ReportType.reportNow,
                              groupValue: _reportType,
                              onChanged: (value) async {
                                if (value == null) {
                                  return;
                                }

                                setState(() {
                                  _reportType = value;
                                });

                                _lateReason.clear();

                                _setDateTime();

                                await _getLocation();
                              },
                            ),

                            RadioListTile<ReportType>(
                              title: const Text('Late Report'),
                              subtitle: const Text(
                                'Report an earlier incident.',
                              ),
                              value: ReportType.lateReport,
                              groupValue: _reportType,
                              onChanged: (value) {
                                if (value == null) {
                                  return;
                                }

                                setState(() {
                                  _reportType = value;

                                  _date.clear();
                                  _time.clear();
                                  _location.clear();
                                  _lat = null;
                                  _lng = null;
                                  _locationAccuracy = null;
                                });
                              },
                            ),

                            if (_reportType == ReportType.lateReport)
                              TextFormField(
                                controller: _lateReason,
                                maxLines: 3,
                                decoration: _input(
                                  'Reason for Late Report',
                                  Icons.edit_note,
                                ),
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'Please provide a reason.';
                                  }

                                  return null;
                                },
                              ),

                            const Divider(height: 30),

                            _header('Incident Details', Icons.gavel),

                            TextFormField(
                              controller: _body,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(3),
                              ],
                              decoration: _input(
                                'Tricycle Body Number',
                                Icons.local_taxi,
                                hint: 'e.g. 123',
                                suffix: _searching
                                    ? const Padding(
                                        padding: EdgeInsets.all(12),
                                        child: SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        ),
                                      )
                                    : null,
                              ).copyWith(prefixText: 'VGN-'),
                              onChanged: _lookupDriver,
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Please enter body number';
                                }

                                if (_bodyError.isNotEmpty) {
                                  return _bodyError;
                                }

                                return null;
                              },
                            ),

                            const SizedBox(height: 16),

                            DropdownButtonFormField<String>(
                              value: _selectedItem,
                              decoration: _input(
                                'Nature of Complaint',
                                Icons.report,
                              ),
                              items: items
                                  .map(
                                    (item) => DropdownMenuItem(
                                      value: item,
                                      child: Text(item),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) {
                                setState(() {
                                  _selectedItem = value;
                                });
                              },
                              validator: (value) {
                                if (value == null) {
                                  return 'Please select complaint';
                                }

                                return null;
                              },
                            ),

                            const SizedBox(height: 16),

                            TextFormField(
                              controller: _driver,
                              textCapitalization: TextCapitalization.words,
                              decoration: _input(
                                'Driver Name (Optional)',
                                Icons.person_outline,
                                hint: 'Enter if you know the driver',
                              ),
                            ),

                            const SizedBox(height: 6),

                            Align(
                              alignment: Alignment.centerLeft,
                              child: Padding(
                                padding: const EdgeInsets.only(left: 4),
                                child: Text(
                                  'Only enter the driver name if you know it.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ),
                            ),

                            const SizedBox(height: 16),

                            TextFormField(
                              controller: _location,
                              readOnly: true,
                              onTap: _reportType == ReportType.lateReport
                                  ? _pickLocation
                                  : null,
                              decoration: _input(
                                'Incident Location',
                                Icons.location_on,
                                hint: 'Tap to pinpoint location',
                                suffix: _locating
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: Padding(
                                          padding: EdgeInsets.all(12),
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.green,
                                          ),
                                        ),
                                      )
                                    : const Icon(
                                        Icons.map,
                                        color: Colors.green,
                                      ),
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Please pinpoint location';
                                }

                                return null;
                              },
                            ),

                            if (_locationAccuracy != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 6, left: 4),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    'GPS accuracy: ${_locationAccuracy!.toStringAsFixed(1)} meters',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ),
                              ),

                            const SizedBox(height: 16),

                            Row(
                              children: [
                                _DateField(
                                  controller: _date,
                                  onTap: _pickDate,
                                  label: 'Incident Date',
                                ),

                                const SizedBox(width: 12),

                                _DateField(
                                  controller: _time,
                                  onTap: _pickTime,
                                  label: 'Incident Time',
                                  icon: Icons.access_time,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _header(
                              'Evidence Attachment (Optional)',
                              Icons.camera_alt,
                            ),

                            const Text(
                              'Add a photo of the incident or fare receipt.',
                              style: TextStyle(color: Colors.black54),
                            ),

                            const SizedBox(height: 16),

                            if (_image == null)
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () =>
                                          _pickImage(ImageSource.camera),
                                      icon: const Icon(
                                        Icons.camera_alt,
                                        color: Colors.green,
                                      ),
                                      label: const Text('Camera'),
                                    ),
                                  ),

                                  const SizedBox(width: 12),

                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () =>
                                          _pickImage(ImageSource.gallery),
                                      icon: const Icon(
                                        Icons.image,
                                        color: Colors.green,
                                      ),
                                      label: const Text('Gallery'),
                                    ),
                                  ),
                                ],
                              )
                            else
                              Stack(
                                children: [
                                  Container(
                                    height: 200,
                                    width: double.infinity,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12),
                                      image: DecorationImage(
                                        image: FileImage(_image!),
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  ),

                                  Positioned(
                                    top: 8,
                                    right: 8,
                                    child: CircleAvatar(
                                      backgroundColor: Colors.black54,
                                      child: IconButton(
                                        onPressed: () {
                                          setState(() => _image = null);
                                        },
                                        icon: const Icon(
                                          Icons.close,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            _header(
                              'Complainant Information',
                              Icons.assignment_ind,
                            ),

                            if (_loadingProfile)
                              const Padding(
                                padding: EdgeInsets.only(bottom: 16),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.green,
                                      ),
                                    ),
                                    SizedBox(width: 10),
                                    Text('Loading your profile...'),
                                  ],
                                ),
                              ),

                            TextFormField(
                              controller: _name,
                              readOnly: true,
                              decoration: _input(
                                'Full Name',
                                Icons.badge,
                                hint: 'Automatically from your account',
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Name could not be loaded.';
                                }

                                return null;
                              },
                            ),

                            const SizedBox(height: 16),

                            TextFormField(
                              controller: _address,
                              decoration: _input(
                                'Home Address (Optional)',
                                Icons.home,
                                hint: 'Optional',
                              ),
                            ),

                            const SizedBox(height: 16),

                            TextFormField(
                              controller: _contact,
                              readOnly: true,
                              keyboardType: TextInputType.phone,
                              decoration: _input(
                                'Contact Number',
                                Icons.phone,
                                hint: 'Automatically from your account',
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Contact number could not be loaded.';
                                }

                                return null;
                              },
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _header('PART IV - DECLARATION', Icons.fact_check),

                            const Text(
                              'Upon submitting this form, I hereby certify that the information provided is true and correct to the best of my knowledge.',
                              style: TextStyle(
                                fontSize: 14,
                                height: 1.5,
                                fontStyle: FontStyle.italic,
                              ),
                            ),

                            const SizedBox(height: 12),

                            Row(
                              children: [
                                Checkbox(
                                  value: _declarationAccepted,
                                  activeColor: Colors.green,
                                  onChanged: (value) {
                                    setState(() {
                                      _declarationAccepted = value ?? false;
                                    });
                                  },
                                ),

                                const Text(
                                  'YES',
                                  style: TextStyle(fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 30),

                    ElevatedButton.icon(
                      onPressed: _loadingProfile || _uploading ? null : _submit,
                      icon: const Icon(Icons.send, color: Colors.white),
                      label: const Text(
                        'SUBMIT OFFENSE REPORT',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 56),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
    );
  }
}

class _DateField extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onTap;
  final String label;
  final IconData icon;

  const _DateField({
    required this.controller,
    required this.onTap,
    required this.label,
    this.icon = Icons.calendar_today,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: TextFormField(
        controller: controller,
        readOnly: true,
        onTap: onTap,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: Colors.green),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
        validator: (value) {
          if (value == null || value.trim().isEmpty) {
            return 'Required';
          }

          return null;
        },
      ),
    );
  }
}

class IncidentLocationPicker extends StatefulWidget {
  const IncidentLocationPicker({super.key});

  @override
  State<IncidentLocationPicker> createState() => _IncidentLocationPickerState();
}

class _IncidentLocationPickerState extends State<IncidentLocationPicker> {
  final _map = MapController();

  LatLng _center = const LatLng(17.5744, 120.3893);

  bool _loading = true;

  @override
  void initState() {
    super.initState();

    _getPosition();
  }

  Future<void> _getPosition() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (mounted) {
          setState(() => _loading = false);
        }

        return;
      }

      var permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() => _loading = false);
        }

        return;
      }

      Position? bestPosition;

      for (var attempt = 0; attempt < 3; attempt++) {
        try {
          final position = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.bestForNavigation,
              distanceFilter: 0,
            ),
            timeLimit: const Duration(seconds: 12),
          );

          if (bestPosition == null ||
              position.accuracy < bestPosition.accuracy) {
            bestPosition = position;
          }

          debugPrint(
            'Map GPS attempt ${attempt + 1}: '
            '${position.latitude}, ${position.longitude} '
            'accuracy=${position.accuracy}m',
          );

          if (position.accuracy <= 20) {
            break;
          }
        } catch (e) {
          debugPrint('Map GPS attempt ${attempt + 1} failed: $e');
        }

        if (attempt < 2) {
          await Future.delayed(const Duration(milliseconds: 700));
        }
      }

      if (!mounted) return;

      setState(() {
        if (bestPosition != null) {
          _center = LatLng(bestPosition!.latitude, bestPosition.longitude);
        }

        _loading = false;
      });
    } catch (e) {
      debugPrint('Map location error: $e');

      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Pinpoint Incident Location',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.green,
        iconTheme: const IconThemeData(color: Colors.white),
      ),

      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Colors.green))
          : Stack(
              children: [
                FlutterMap(
                  mapController: _map,
                  options: MapOptions(
                    initialCenter: _center,
                    initialZoom: 16.5,
                    onPositionChanged: (position, _) {
                      if (position.center != null) {
                        _center = position.center!;
                      }
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.rtoda.complaint_desk_app',
                    ),
                  ],
                ),

                const Center(
                  child: Padding(
                    padding: EdgeInsets.only(bottom: 36),
                    child: Icon(
                      Icons.location_pin,
                      size: 50,
                      color: Colors.redAccent,
                    ),
                  ),
                ),

                Positioned(
                  bottom: 24,
                  left: 24,
                  right: 24,
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.pop(context, _center),
                    icon: const Icon(
                      Icons.check_circle_outline,
                      color: Colors.white,
                    ),
                    label: const Text(
                      'CONFIRM INCIDENT LOCATION',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
