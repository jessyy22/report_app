import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart';

class FareMap extends StatelessWidget {
  final MapController controller;
  final LatLng? pickup;
  final LatLng? destination;

  const FareMap({
    super.key,
    required this.controller,
    this.pickup,
    this.destination,
  });

  @override
  Widget build(BuildContext context) {
    // Auto-fit both markers into view when both are set.
    if (pickup != null && destination != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          controller.fitCamera(
            CameraFit.bounds(
              bounds: LatLngBounds.fromPoints([pickup!, destination!]),
              padding: const EdgeInsets.all(60),
            ),
          );
        } catch (e) {
          debugPrint('FareMap fitCamera error: $e');
        }
      });
    }

    return FlutterMap(
      mapController: controller,
      options: MapOptions(
        initialCenter: const LatLng(17.5744, 120.3893),
        initialZoom: 15,
        minZoom: 10,
        maxZoom: 18,
        interactionOptions: const InteractionOptions(
          // Allow pan + zoom, disable rotate + tilt (avoid accidental
          // two-finger gestures).
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
      ),
      children: [
        // ── Tile layer ─────────────────────────────────────────
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.report_app',
          tileProvider: NetworkTileProvider(),
          errorTileCallback: (tile, error, stackTrace) {
            debugPrint('Tile error: $error');
          },
        ),

        // ── Connecting polyline ────────────────────────────────
        if (pickup != null && destination != null)
          PolylineLayer(
            polylines: [
              Polyline(
                points: [pickup!, destination!],
                strokeWidth: 4,
                color: AppColors.green,
              ),
            ],
          ),

        // ── Markers ────────────────────────────────────────────
        MarkerLayer(
          markers: [
            if (pickup != null)
              Marker(
                point: pickup!,
                width: 40,
                height: 40,
                child: _markerBadge(
                  icon: Icons.trip_origin,
                  color: AppColors.green,
                ),
              ),
            if (destination != null)
              Marker(
                point: destination!,
                width: 40,
                height: 40,
                child: _markerBadge(
                  icon: Icons.location_pin,
                  color: AppColors.danger,
                ),
              ),
          ],
        ),

        // ── OSM attribution (required by OSM Tile Usage Policy) ─
        RichAttributionWidget(
          attributions: [
            TextSourceAttribution(
              'OpenStreetMap contributors',
              onTap: () => launchUrl(
                Uri.parse('https://openstreetmap.org/copyright'),
                mode: LaunchMode.externalApplication,
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Marker icon with a soft white background so it stays visible
  /// on any map tile color.
  Widget _markerBadge({required IconData icon, required Color color}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.20),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(6),
      child: Icon(icon, color: color, size: 24),
    );
  }
}
