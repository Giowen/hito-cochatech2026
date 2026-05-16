import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../providers.dart';

/// Mapa con los 15 markers de propiedades, coloreados por compatibility.
/// Sincronizado con selectedPropertyIdProvider: click marker → highlight + center.
class PropertiesMap extends ConsumerStatefulWidget {
  const PropertiesMap({super.key});

  @override
  ConsumerState<PropertiesMap> createState() => _PropertiesMapState();
}

class _PropertiesMapState extends ConsumerState<PropertiesMap> {
  late final MapController _mapController;
  static final _defaultCenter = LatLng(-17.395, -66.150);

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
  }

  @override
  Widget build(BuildContext context) {
    final propertiesAsync = ref.watch(propertiesProvider);
    final matchesAsync = ref.watch(matchResultsProvider);
    final selectedId = ref.watch(selectedPropertyIdProvider);

    // Listen to selected change, animate map to that property
    ref.listen<String?>(selectedPropertyIdProvider, (prev, current) {
      if (current == null) return;
      final properties = propertiesAsync.value;
      if (properties == null) return;
      final selected =
          {for (final p in properties) p.id: p}[current];
      if (selected != null) {
        _mapController.move(selected.coords, 14);
      }
    });

    return propertiesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (properties) => matchesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (matches) {
          final matchMap = {for (final m in matches) m.propertyId: m};

          return FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _defaultCenter,
              initialZoom: 12.5,
              minZoom: 10,
              maxZoom: 17,
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.tokenizers.hito',
              ),
              MarkerLayer(
                markers: properties
                    .map((property) {
                      final match = matchMap[property.id];
                      if (match == null) return null;
                      final isSelected = property.id == selectedId;
                      return Marker(
                        point: property.coords,
                        width: isSelected ? 64 : 50,
                        height: isSelected ? 64 : 50,
                        child: GestureDetector(
                          onTap: () {
                            ref
                                .read(selectedPropertyIdProvider.notifier)
                                .select(property.id);
                          },
                          child: _MarkerBadge(
                            compatibility: match.compatibilityPercent,
                            isSelected: isSelected,
                          ),
                        ),
                      );
                    })
                    .whereType<Marker>()
                    .toList(),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _MarkerBadge extends StatelessWidget {
  final int compatibility;
  final bool isSelected;

  const _MarkerBadge({
    required this.compatibility,
    required this.isSelected,
  });

  Color _bucketColor() {
    if (compatibility >= 80) return Colors.green.shade600;
    if (compatibility >= 50) return Colors.orange.shade600;
    return Colors.grey.shade500;
  }

  @override
  Widget build(BuildContext context) {
    final color = _bucketColor();
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white,
          width: isSelected ? 4 : 3,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color.fromRGBO(0, 0, 0, 0.3),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: Text(
          '$compatibility',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: isSelected ? 18 : 14,
          ),
        ),
      ),
    );
  }
}
