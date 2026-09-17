import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

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
    return FlutterMap(
      mapController: controller,
      options: MapOptions(
        initialCenter: LatLng(17.5744, 120.3893),
        initialZoom: 15,
      ),
      children: [
        TileLayer(
          urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
          userAgentPackageName: "com.example.report_app",
          tileProvider: NetworkTileProvider(),
        ),

        if (pickup != null && destination != null)
          PolylineLayer(
            polylines: [
              Polyline(
                points: [pickup!, destination!],
                strokeWidth: 4,
                color: Colors.green,
              ),
            ],
          ),

        MarkerLayer(
          markers: [
            if (pickup != null)
              Marker(
                point: pickup!,
                width: 40,
                height: 40,
                child: const Icon(Icons.trip_origin, color: Colors.green),
              ),

            if (destination != null)
              Marker(
                point: destination!,
                width: 40,
                height: 40,
                child: const Icon(
                  Icons.location_pin,
                  color: Colors.red,
                  size: 35,
                ),
              ),
          ],
        ),
      ],
    );
  }
}
