import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_heatmap/flutter_map_heatmap.dart';
import 'package:latlong2/latlong.dart';

/// Sprint 0.4 — Stack Test 4: validar que flutter_map_heatmap renderiza
/// overlay sin glitches sobre flutter_map + OSM.
///
/// Done criteria:
/// - Heatmap overlay visible sobre el mapa OSM
/// - 15 puntos sintéticos generan un blob de calor distinguible
/// - Sin glitches al zoom in/out
class HeatmapTestPage extends StatelessWidget {
  const HeatmapTestPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cochabamba = LatLng(-17.3935, -66.1570);
    final random = Random(42); // deterministic
    final points = List.generate(15, (i) {
      final lat = -17.3935 + (random.nextDouble() - 0.5) * 0.05;
      final lng = -66.1570 + (random.nextDouble() - 0.5) * 0.05;
      return WeightedLatLng(LatLng(lat, lng), 1.0);
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Test 4: flutter_map_heatmap'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
      ),
      body: FlutterMap(
        options: MapOptions(
          initialCenter: cochabamba,
          initialZoom: 13,
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.tokenizers.hito',
          ),
          HeatMapLayer(
            heatMapDataSource: InMemoryHeatMapDataSource(data: points),
            heatMapOptions: HeatMapOptions(
              gradient: HeatMapOptions.defaultGradient,
              minOpacity: 0.1,
              radius: 40,
            ),
          ),
        ],
      ),
    );
  }
}
