import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/google_geocoding_service.dart';
import '../../services/notification_service.dart';
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
  final _otherReason = TextEditingController();

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

  Timer? _lookupDebounce;

  final items = const [
    'Overcharging',
    'Discriminate / Refusal to convey',
    'Discourteous / Arrogant Driver',
    'Overloading',
    'Illegal Parking',
    'No Mayors Permit',
    'No Drivers Permit',
    'Others',
  ];

  bool get _canSubmit =>
      !_uploading &&
      _declarationAccepted &&
      _tricycleId.isNotEmpty &&
      _bodyError.isEmpty &&
      _lat != null &&
      _lng != null;

  @override
  void initState() {
    super.initState();
    _setDateTime();
    _loadProfile();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _getLocation();
    });
  }

  @override
  void dispose() {
    _lookupDebounce?.cancel();
    _date.dispose();
    _time.dispose();
    _driver.dispose();
    _location.dispose();
    _name.dispose();
    _address.dispose();
    _contact.dispose();
    _body.dispose();
    _lateReason.dispose();
    _otherReason.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Snackbar helper
  // ---------------------------------------------------------------------------
  void _show(String message, {bool error = false}) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: error ? Colors.red.shade700 : Colors.green.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  // ---------------------------------------------------------------------------
  // Profile
  // ---------------------------------------------------------------------------
  Future<void> _loadProfile() async {
    final db = Supabase.instance.client;
    final user = db.auth.currentUser;

    if (user == null) {
      if (mounted) setState(() => _loadingProfile = false);
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
      if (!mounted) return;
      setState(() => _loadingProfile = false);
      _show('Unable to load commuter information.', error: true);
    }
  }

  // ---------------------------------------------------------------------------
  // Date / Time
  // ---------------------------------------------------------------------------
  void _setDateTime() {
    final now = DateTime.now();
    _date.text = DateFormat('yyyy-MM-dd').format(now);
    _time.text = DateFormat('hh:mm a').format(now);
  }

  // ---------------------------------------------------------------------------
  // Location
  // ---------------------------------------------------------------------------
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
                '${position.latitude}, ${position.longitude} '
                'accuracy=${position.accuracy}m '
                'age=${age.inSeconds}s '
                'mocked=${position.isMocked}',
              );

              if (age > const Duration(seconds: 15)) {
                debugPrint('GPS: Ignored stale location.');
                return;
              }

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

              if (position.accuracy <= 20 && !completer.isCompleted) {
                completer.complete(position);
              }
            },
            onError: (error) {
              debugPrint('GPS stream error: $error');
              if (!completer.isCompleted) completer.complete(bestPosition);
            },
          );

      Future.delayed(const Duration(seconds: 30), () {
        if (!completer.isCompleted) completer.complete(bestPosition);
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
    if (!mounted || _locating) return;
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
        '$_lat, $_lng accuracy=${_locationAccuracy}m',
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
      if (mounted) _show('Could not retrieve your location.', error: true);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _pickLocation() async {
    if (!mounted || _locating) return;
    setState(() => _locating = true);

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
        MaterialPageRoute(
          builder: (_) => IncidentLocationPicker(
            initial: (_lat != null && _lng != null)
                ? LatLng(_lat!, _lng!)
                : null,
          ),
        ),
      );

      if (!mounted) return;
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
      if (mounted) _show('Could not retrieve location: $e', error: true);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Body number lookup (debounced)
  // ---------------------------------------------------------------------------
  void _onBodyNumberChanged(String value) {
    _lookupDebounce?.cancel();

    final digits = value.trim();

    if (digits.isEmpty) {
      setState(() {
        _tricycleId = '';
        _bodyError = '';
      });
      return;
    }

    if (!RegExp(r'^\d+$').hasMatch(digits)) {
      setState(() {
        _bodyError = 'Please enter numbers only.';
        _tricycleId = '';
      });
      return;
    }

    setState(() {
      _bodyError = '';
      _tricycleId = '';
    });

    _lookupDebounce = Timer(const Duration(milliseconds: 500), () {
      _lookupDriver(digits);
    });
  }

  Future<void> _lookupDriver(String value) async {
    final digits = value.trim();
    if (digits.isEmpty) return;

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

      if (!mounted) return;

      if (tricycle == null) {
        setState(() {
          _bodyError = 'Body number not found in database.';
          _tricycleId = '';
        });
      } else {
        setState(() {
          _tricycleId = tricycle['tricycle_id'].toString();
          _bodyError = '';
        });
      }
    } catch (e) {
      debugPrint('Body number lookup error: $e');
      if (!mounted) return;
      setState(() {
        _bodyError = 'Database lookup error.';
        _tricycleId = '';
      });
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Image
  // ---------------------------------------------------------------------------
  Future<void> _pickImage(ImageSource source) async {
    try {
      final file = await _picker.pickImage(source: source, imageQuality: 80);
      if (file != null && mounted) {
        setState(() => _image = File(file.path));
      }
    } catch (e) {
      _show('Error selecting image: $e', error: true);
    }
  }

  // ---------------------------------------------------------------------------
  // Submit
  // ---------------------------------------------------------------------------
  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

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
      if (!mounted) return;
      if (_name.text.trim().isEmpty || _contact.text.trim().isEmpty) {
        _show('Your profile is incomplete. Please update it.', error: true);
        return;
      }
    }

    if (_reportType == ReportType.lateReport &&
        _lateReason.text.trim().isEmpty) {
      _show('Please provide a reason for the late report.', error: true);
      return;
    }

    if (_selectedItem == 'Others' && _otherReason.text.trim().isEmpty) {
      _show('Please specify the report type.', error: true);
      return;
    }

    setState(() => _uploading = true);

    try {
      String? imageUrl;

      if (_image != null) {
        final extension = _image!.path.split('.').last.toLowerCase();
        final path =
            'evidence/${user.id}/'
            '${DateTime.now().millisecondsSinceEpoch}.$extension';

        await db.storage
            .from('report_evidence')
            .upload(
              path,
              _image!,
              fileOptions: const FileOptions(upsert: false),
            );

        imageUrl = db.storage.from('report_evidence').getPublicUrl(path);
      }

      final barangay = await _getBarangay(_lat!, _lng!);

      final payload = <String, dynamic>{
        'commuter_id': user.id,
        'tricycle_id': _tricycleId,
        'report_type': _selectedItem == 'Others'
            ? 'Others: ${_otherReason.text.trim()}'
            : _selectedItem,
        'description': _driver.text.trim().isEmpty ? null : _driver.text.trim(),
        'location_text': _location.text.trim(),
        'barangay': barangay,
        'latitude': _lat,
        'longitude': _lng,
        'location_accuracy': _locationAccuracy,
        'evidence_url': imageUrl,
        'reported_at': _reportType == ReportType.lateReport
            ? '${_date.text} ${_time.text}'
            : DateTime.now().toUtc().toIso8601String(),
        'late_reason': _reportType == ReportType.lateReport
            ? _lateReason.text.trim()
            : null,
        'status': 'pending',
      };

      final inserted = await db
          .from('reports')
          .insert(payload)
          .select('id')
          .maybeSingle();

      final reportId = inserted?['id']?.toString();

      // ── Notifications (best-effort, non-blocking) ──────────────────────────
      unawaited(
        NotificationService.sendPush(
          userId: user.id,
          title: 'Report Submitted',
          message:
              'Your report'
              '${reportId != null ? ' #$reportId' : ''} '
              'has been received and is pending review. Thank you!',
          type: 'report_submitted',
        ).catchError((e) {
          debugPrint('Notification error: $e');
        }),
      );

      unawaited(
        NotificationService.sendPushToRole(
          role: 'admin', // ← match the role value used in your DB
          title: 'New Report Filed',
          message:
              'A new violation report'
              '${reportId != null ? ' #$reportId' : ''} '
              'was submitted and is pending review.',
          type: 'new_report',
        ).catchError((e) {
          debugPrint('Notification error (admin): $e');
        }),
      );

      if (!mounted) return;
      _show('Report submitted successfully. Thank you!');

      setState(() {
        _body.clear();
        _driver.clear();
        _tricycleId = '';
        _bodyError = '';
        _selectedItem = null;
        _image = null;
        _declarationAccepted = false;
        _lateReason.clear();
        _otherReason.clear();
        _reportType = ReportType.reportNow;
      });
      _setDateTime();
      if (mounted) await _getLocation();
    } catch (e) {
      debugPrint('Submit error: $e');
      if (!mounted) return;
      _show('Failed to submit report: $e', error: true);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loadingProfile) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Report a Violation'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              if (_uploading) const LinearProgressIndicator(),
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    16,
                    16,
                    24 + MediaQuery.of(context).viewInsets.bottom,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Report type
                      SegmentedButton<ReportType>(
                        segments: const [
                          ButtonSegment(
                            value: ReportType.reportNow,
                            label: Text('Report Now'),
                            icon: Icon(Icons.flash_on),
                          ),
                          ButtonSegment(
                            value: ReportType.lateReport,
                            label: Text('Late Report'),
                            icon: Icon(Icons.history),
                          ),
                        ],
                        selected: {_reportType},
                        onSelectionChanged: (s) =>
                            setState(() => _reportType = s.first),
                      ),
                      const SizedBox(height: 16),

                      // Date / Time
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _date,
                              readOnly: true,
                              decoration: const InputDecoration(
                                labelText: 'Date',
                                prefixIcon: Icon(Icons.calendar_today_outlined),
                                border: OutlineInputBorder(),
                                filled: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _time,
                              readOnly: true,
                              decoration: const InputDecoration(
                                labelText: 'Time',
                                prefixIcon: Icon(Icons.access_time),
                                border: OutlineInputBorder(),
                                filled: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Late reason
                      if (_reportType == ReportType.lateReport) ...[
                        TextFormField(
                          controller: _lateReason,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            labelText: 'Reason for late report',
                            hintText:
                                'Explain why this report is being filed late',
                            prefixIcon: Icon(Icons.info_outline),
                            border: OutlineInputBorder(),
                          ),
                          validator: (v) =>
                              _reportType == ReportType.lateReport &&
                                  (v == null || v.trim().isEmpty)
                              ? 'Please provide a reason'
                              : null,
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Body number
                      TextFormField(
                        controller: _body,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: InputDecoration(
                          labelText: 'Body Number',
                          hintText: 'e.g., 1234 (auto-prefixed with VGN-)',
                          prefixIcon: const Icon(
                            Icons.confirmation_number_outlined,
                          ),
                          suffixIcon: _searching
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
                              : _tricycleId.isNotEmpty
                              ? const Icon(
                                  Icons.check_circle,
                                  color: Colors.green,
                                )
                              : null,
                          errorText: _bodyError.isEmpty ? null : _bodyError,
                          helperText: _tricycleId.isNotEmpty
                              ? '✓ Verified body number'
                              : null,
                          border: const OutlineInputBorder(),
                        ),
                        onChanged: _onBodyNumberChanged,
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return 'Body number is required';
                          }
                          if (!RegExp(r'^\d+$').hasMatch(v.trim())) {
                            return 'Numbers only';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Violation type
                      DropdownButtonFormField<String>(
                        initialValue: _selectedItem,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Violation Type',
                          prefixIcon: Icon(Icons.report_problem_outlined),
                          border: OutlineInputBorder(),
                        ),
                        items: items
                            .map(
                              (e) => DropdownMenuItem(
                                value: e,
                                child: Text(e, overflow: TextOverflow.ellipsis),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => setState(() => _selectedItem = v),
                        validator: (v) =>
                            v == null ? 'Please select a violation type' : null,
                      ),
                      const SizedBox(height: 16),

                      // Other reason
                      if (_selectedItem == 'Others') ...[
                        TextFormField(
                          controller: _otherReason,
                          maxLines: 2,
                          decoration: const InputDecoration(
                            labelText: 'Please specify',
                            prefixIcon: Icon(Icons.edit_note),
                            border: OutlineInputBorder(),
                          ),
                          validator: (v) =>
                              _selectedItem == 'Others' &&
                                  (v == null || v.trim().isEmpty)
                              ? 'Please specify the violation'
                              : null,
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Description
                      TextFormField(
                        controller: _driver,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          labelText: 'Description (optional)',
                          hintText:
                              'Describe what happened (driver appearance, '
                              'plate, etc.)',
                          prefixIcon: Icon(Icons.description_outlined),
                          border: OutlineInputBorder(),
                          alignLabelWithHint: true,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Location
                      TextFormField(
                        controller: _location,
                        readOnly: true,
                        maxLines: 2,
                        minLines: 1,
                        decoration: InputDecoration(
                          labelText: 'Location',
                          prefixIcon: const Icon(Icons.location_on_outlined),
                          suffixIcon: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_locating)
                                const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                )
                              else ...[
                                IconButton(
                                  tooltip: 'Detect my location',
                                  icon: const Icon(Icons.my_location),
                                  onPressed: _getLocation,
                                ),
                                IconButton(
                                  tooltip: 'Pick on map',
                                  icon: const Icon(Icons.map_outlined),
                                  onPressed: _pickLocation,
                                ),
                              ],
                            ],
                          ),
                          helperText: _locationAccuracy != null
                              ? 'Accuracy: '
                                    '${_locationAccuracy!.toStringAsFixed(0)} m'
                              : null,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Reporter info
                      TextFormField(
                        controller: _name,
                        readOnly: true,
                        decoration: const InputDecoration(
                          labelText: 'Your Name',
                          prefixIcon: Icon(Icons.person_outline),
                          border: OutlineInputBorder(),
                          filled: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _contact,
                        readOnly: true,
                        decoration: const InputDecoration(
                          labelText: 'Contact Number',
                          prefixIcon: Icon(Icons.phone_outlined),
                          border: OutlineInputBorder(),
                          filled: true,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Image
                      Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: Colors.grey.shade300),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Evidence Photo (optional)',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              if (_image != null) ...[
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.file(
                                    _image!,
                                    height: 180,
                                    width: double.infinity,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        icon: const Icon(Icons.swap_horiz),
                                        label: const Text('Replace'),
                                        onPressed: _uploading
                                            ? null
                                            : () => _pickImage(
                                                ImageSource.camera,
                                              ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    IconButton(
                                      tooltip: 'Remove photo',
                                      icon: const Icon(
                                        Icons.delete_outline,
                                        color: Colors.red,
                                      ),
                                      onPressed: _uploading
                                          ? null
                                          : () => setState(() => _image = null),
                                    ),
                                  ],
                                ),
                              ] else
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        icon: const Icon(
                                          Icons.camera_alt_outlined,
                                        ),
                                        label: const Text('Camera'),
                                        onPressed: _uploading
                                            ? null
                                            : () => _pickImage(
                                                ImageSource.camera,
                                              ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        icon: const Icon(
                                          Icons.photo_library_outlined,
                                        ),
                                        label: const Text('Gallery'),
                                        onPressed: _uploading
                                            ? null
                                            : () => _pickImage(
                                                ImageSource.gallery,
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

                      // Declaration
                      CheckboxListTile(
                        value: _declarationAccepted,
                        onChanged: _uploading
                            ? null
                            : (v) => setState(
                                () => _declarationAccepted = v ?? false,
                              ),
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'I declare that the information provided is true '
                          'and correct. I understand that false reports may '
                          'result in account suspension.',
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Submit
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton.icon(
                          onPressed: _canSubmit ? _submit : null,
                          icon: _uploading
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.send),
                          label: Text(
                            _uploading ? 'Submitting…' : 'Submit Report',
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: theme.colorScheme.primary,
                            foregroundColor: theme.colorScheme.onPrimary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Minimal map picker
// ---------------------------------------------------------------------------
class IncidentLocationPicker extends StatefulWidget {
  const IncidentLocationPicker({super.key, this.initial});

  final LatLng? initial;

  @override
  State<IncidentLocationPicker> createState() => _IncidentLocationPickerState();
}

class _IncidentLocationPickerState extends State<IncidentLocationPicker> {
  late final MapController _mapController = MapController();
  LatLng? _picked;

  @override
  void initState() {
    super.initState();
    _picked = widget.initial;
  }

  @override
  Widget build(BuildContext context) {
    final center = _picked ?? const LatLng(14.5995, 120.9842); // Manila default

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pick Incident Location'),
        actions: [
          IconButton(
            tooltip: 'Use this location',
            icon: const Icon(Icons.check),
            onPressed: _picked == null
                ? null
                : () => Navigator.pop(context, _picked),
          ),
        ],
      ),
      body: FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCenter: center,
          initialZoom: 16,
          onTap: (_, point) => setState(() => _picked = point),
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.example.app',
          ),
          if (_picked != null)
            MarkerLayer(
              markers: [
                Marker(
                  point: _picked!,
                  width: 40,
                  height: 40,
                  child: const Icon(
                    Icons.location_on,
                    color: Colors.red,
                    size: 40,
                  ),
                ),
              ],
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _picked == null
            ? null
            : () => Navigator.pop(context, _picked),
        icon: const Icon(Icons.check),
        label: const Text('Use Location'),
      ),
    );
  }
}
