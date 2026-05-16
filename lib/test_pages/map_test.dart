import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Sprint 0.2 — Stack Test 1: validar que flutter_map renderiza tiles OSM
/// apuntando a Cochabamba sin glitches.
///
/// Done criteria:
/// - Cochabamba (-17.3935, -66.1570) visible al cargar
/// - Zoom in/out funciona sin glitches
/// - Tiles cargan sin errores en consola
class MapTestPage extends StatelessWidget {
  const MapTestPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cochabamba = LatLng(-17.3935, -66.1570);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Test 1: flutter_map + OSM'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
      ),
      body: FlutterMap(
        options: MapOptions(
          initialCenter: cochabamba,
          initialZoom: 13,
          minZoom: 5,
          maxZoom: 18,
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.tokenizers.hito',
          ),
          MarkerLayer(
            markers: [
              Marker(
                point: cochabamba,
                width: 60,
                height: 60,
                child: const Icon(
                  Icons.location_on,
                  size: 40,
                  color: Colors.red,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
