import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import '../providers.dart';
import '../theme.dart';

/// Mapa con los 15 markers de propiedades, coloreados por compatibility.
/// Sincronizado con selectedPropertyIdProvider: click marker → highlight + center.
class PropertiesMap extends ConsumerStatefulWidget {
  const PropertiesMap({super.key});

  @override
  ConsumerState<PropertiesMap> createState() => _PropertiesMapState();
}

class _PropertiesMapState extends ConsumerState<PropertiesMap> {
  late final MapController _mapController;
  bool _showZones = true;
  static final _defaultCenter = LatLng(-17.395, -66.150);

  // Polygon zones (Sprint 2.4 — reemplazo de flutter_map_heatmap)
  static final _greenZone = [
    LatLng(-17.388, -66.150),
    LatLng(-17.388, -66.130),
    LatLng(-17.412, -66.130),
    LatLng(-17.412, -66.150),
  ];
  static final _amberZone = [
    LatLng(-17.370, -66.170),
    LatLng(-17.370, -66.150),
    LatLng(-17.390, -66.150),
    LatLng(-17.390, -66.170),
  ];

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
    final activeValuationId = ref.watch(activeValuationPropertyIdProvider);
    // Comparables IDs cuando valuation está activa
    final comparableIds = activeValuationId != null
        ? ref.watch(valuationProvider(activeValuationId)).value?.comparables ??
            const <String>[]
        : const <String>[];

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

          return Stack(
            children: [
              FlutterMap(
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
                  if (_showZones)
                    PolygonLayer(
                      polygons: [
                        Polygon(
                          points: _greenZone,
                          color: Colors.green.withAlpha(60),
                          borderColor: Colors.green.shade700,
                          borderStrokeWidth: 2,
                        ),
                        Polygon(
                          points: _amberZone,
                          color: Colors.orange.withAlpha(50),
                          borderColor: Colors.orange.shade700,
                          borderStrokeWidth: 2,
                        ),
                      ],
                    ),
                  MarkerLayer(
                    markers: properties
                        .map((property) {
                          final match = matchMap[property.id];
                          if (match == null) return null;
                          final isSelected = property.id == selectedId;
                          return Marker(
                            point: property.coords,
                            width: isSelected ? 86 : 72,
                            height: isSelected ? 56 : 46,
                            child: GestureDetector(
                              onTap: () {
                                ref
                                    .read(selectedPropertyIdProvider.notifier)
                                    .select(property.id);
                              },
                              child: _MarkerBadge(
                                compatibility: match.compatibilityPercent,
                                isSelected: isSelected,
                                isAnticretico:
                                    property.supportsAnticretico,
                              ),
                            ),
                          );
                        })
                        .whereType<Marker>()
                        .toList(),
                  ),
                  // "C" labels para comparables cuando valuation activa
                  if (comparableIds.isNotEmpty)
                    MarkerLayer(
                      markers: properties
                          .where((p) => comparableIds.contains(p.id))
                          .map(
                            (p) => Marker(
                              point: LatLng(p.lat - 0.0035, p.lng),
                              width: 28,
                              height: 28,
                              child: const _ComparableBadge(),
                            ),
                          )
                          .toList(),
                    ),
                ],
              ),
              Positioned(
                top: 12,
                right: 12,
                child: _ZonesToggle(
                  active: _showZones,
                  onToggle: () =>
                      setState(() => _showZones = !_showZones),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ComparableBadge extends StatelessWidget {
  const _ComparableBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.blueGrey.shade700,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [
          BoxShadow(
            color: Color.fromRGBO(0, 0, 0, 0.3),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: const Center(
        child: Text(
          'C',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

class _ZonesToggle extends StatelessWidget {
  final bool active;
  final VoidCallback onToggle;

  const _ZonesToggle({required this.active, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(22),
      color: active ? Colors.green.shade600 : Colors.white,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onToggle,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                active ? Icons.layers : Icons.layers_outlined,
                size: 18,
                color: active ? Colors.white : Colors.grey.shade800,
              ),
              const SizedBox(width: 6),
              Text(
                'Zonas',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: active ? Colors.white : Colors.grey.shade800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MarkerBadge extends StatelessWidget {
  final int compatibility;
  final bool isSelected;
  final bool isAnticretico;

  const _MarkerBadge({
    required this.compatibility,
    required this.isSelected,
    this.isAnticretico = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = compatibilityColor(compatibility);
    final showStar = compatibility >= 85;

    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          padding: EdgeInsets.symmetric(
            horizontal: isSelected ? 10 : 8,
            vertical: isSelected ? 5 : 4,
          ),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(HitoTokens.r2xl),
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: const [
              BoxShadow(
                color: Color.fromRGBO(13, 27, 42, 0.25),
                blurRadius: 5,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showStar) ...[
                Icon(
                  Icons.star_rounded,
                  size: isSelected ? 14 : 12,
                  color: Colors.white,
                ),
                const SizedBox(width: 3),
              ],
              Text(
                '$compatibility',
                style: GoogleFonts.geist(
                  fontSize: isSelected ? 14 : 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  height: 1.0,
                ),
              ),
            ],
          ),
        ),
        if (isAnticretico) ...[
          const SizedBox(height: 2),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: HitoTokens.paper,
              borderRadius: BorderRadius.circular(HitoTokens.rXs),
              border: Border.all(color: HitoTokens.borderStrong),
            ),
            child: Text(
              'ANTI',
              style: GoogleFonts.geist(
                fontSize: 8,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
                color: HitoTokens.teal2,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
