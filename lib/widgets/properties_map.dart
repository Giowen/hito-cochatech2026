import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import '../models/property.dart';
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
  static final _defaultCenter = LatLng(-17.972, -67.113);

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
  }

  @override
  Widget build(BuildContext context) {
    final propertiesAsync = ref.watch(propertiesProvider);
    final batchAsync = ref.watch(matchingBatchProvider);
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
      data: (properties) {
        final batch = batchAsync.value;
        final matches = batch?.completed ?? const [];
        final matchMap = {for (final m in matches) m.propertyId: m};
        final pendingIds = batch?.pending.toSet() ?? <String>{};
        final isScoring =
            batch != null && batch.candidates.isNotEmpty && !batch.isComplete;

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
                // Radar pulse — un círculo expansivo + ping en cada candidate
                // todavía pendiente. Solo durante scoring.
                if (isScoring)
                  MarkerLayer(
                    markers: batch.candidates
                        .where((p) => pendingIds.contains(p.id))
                        .map(
                          (p) => Marker(
                            point: p.coords,
                            width: 80,
                            height: 80,
                            child: const _RadarPing(),
                          ),
                        )
                        .toList(),
                  ),
                MarkerLayer(
                  markers: properties.map((property) {
                    final match = matchMap[property.id];
                    final isSelected = property.id == selectedId;
                    final isPending = pendingIds.contains(property.id);
                    return Marker(
                      point: property.coords,
                      width: isSelected ? 92 : 78,
                      height: isSelected ? 56 : 46,
                      child: GestureDetector(
                        onTap: () {
                          ref
                              .read(selectedPropertyIdProvider.notifier)
                              .select(property.id);
                        },
                        child: _MarkerForState(
                          property: property,
                          match: match,
                          isSelected: isSelected,
                          isPending: isPending,
                        ),
                      ),
                    );
                  }).toList(),
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
            if (isScoring)
              Positioned(
                bottom: 16,
                left: 0,
                right: 0,
                child: Center(
                  child: _AiEvaluatingPill(
                    done: batch.done,
                    total: batch.total,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Decide qué tipo de marker mostrar según el estado del scoring:
/// - Si hay match completo → MarkerBadge con score
/// - Si está pending → BrowseMarker atenuado (con price)
/// - Si no es candidato → BrowseMarker normal
class _MarkerForState extends StatelessWidget {
  final Property property;
  final dynamic match;
  final bool isSelected;
  final bool isPending;
  const _MarkerForState({
    required this.property,
    required this.match,
    required this.isSelected,
    required this.isPending,
  });

  @override
  Widget build(BuildContext context) {
    if (match != null) {
      return TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutBack,
        builder: (context, t, child) {
          return Opacity(
            opacity: t.clamp(0.0, 1.0),
            child: Transform.scale(
              scale: 0.6 + 0.4 * t.clamp(0.0, 1.0),
              child: child,
            ),
          );
        },
        child: _MarkerBadge(
          compatibility: match.compatibilityPercent,
          isSelected: isSelected,
          isAnticretico: property.supportsAnticretico,
        ),
      );
    }
    return Opacity(
      opacity: isPending ? 0.45 : 1.0,
      child: _BrowseMarker(
        priceUsd: property.priceUsdParalelo,
        isAnticretico: property.supportsAnticretico,
        isSelected: isSelected,
      ),
    );
  }
}

/// Ping circular tipo radar — pulsa con expansión + fade hasta desaparecer.
/// Se renderiza sobre cada candidate pendiente para sugerir "evaluando aquí".
class _RadarPing extends StatefulWidget {
  const _RadarPing();

  @override
  State<_RadarPing> createState() => _RadarPingState();
}

class _RadarPingState extends State<_RadarPing>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          return CustomPaint(
            size: const Size(80, 80),
            painter: _RadarPainter(progress: _ctrl.value),
          );
        },
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  final double progress;
  _RadarPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final maxRadius = size.shortestSide / 2;
    // Dos ondas defasadas para mayor densidad visual.
    for (final phase in [0.0, 0.5]) {
      final t = (progress + phase) % 1.0;
      final radius = maxRadius * t;
      final opacity = (1.0 - t).clamp(0.0, 1.0);
      final paint = Paint()
        ..color = HitoTokens.teal.withValues(alpha: 0.45 * opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawCircle(center, radius, paint);
      // Disco interno suave.
      final fill = Paint()
        ..color = HitoTokens.teal.withValues(alpha: 0.08 * opacity)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(center, radius * 0.8, fill);
    }
    // Centro fijo.
    final core = Paint()
      ..color = HitoTokens.teal.withValues(alpha: 0.8)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 3, core);
  }

  @override
  bool shouldRepaint(covariant _RadarPainter old) =>
      old.progress != progress;
}

// avoid unused warnings for math (only used inside painter when we add sweep)
// ignore: unused_element
double _kIgnoreLint(double v) => math.max(v, 0);

/// Pill teal flotante en la base del mapa durante el scoring AI.
/// Muestra spinner + texto rotativo + contador real (X de Y).
class _AiEvaluatingPill extends StatefulWidget {
  final int done;
  final int total;
  const _AiEvaluatingPill({required this.done, required this.total});

  @override
  State<_AiEvaluatingPill> createState() => _AiEvaluatingPillState();
}

class _AiEvaluatingPillState extends State<_AiEvaluatingPill> {
  static const _messages = [
    'Filtrando inventario por tus requisitos...',
    'Calculando distancias a tu zona deseada...',
    'Evaluando cada propiedad con Llama 3.3...',
    'Aplicando caps por presupuesto y modalidad...',
    'Rankeando matches por compatibilidad...',
  ];
  int _index = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      if (!mounted) return;
      setState(() => _index = (_index + 1) % _messages.length);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final counter =
        widget.total > 0 ? '${widget.done}/${widget.total}' : '';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: HitoTokens.ink1,
        borderRadius: BorderRadius.circular(HitoTokens.r2xl),
        boxShadow: const [
          BoxShadow(
            color: Color.fromRGBO(0, 0, 0, 0.18),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 10),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: Text(
              _messages[_index],
              key: ValueKey(_index),
              style: GoogleFonts.geist(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Colors.white,
              ),
            ),
          ),
          if (counter.isNotEmpty) ...[
            const SizedBox(width: 10),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: HitoTokens.teal,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                counter,
                style: GoogleFonts.geist(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Marker neutral cuando todavía no hay scoring AI. Muestra el precio en USD
/// — el usuario puede explorar el inventario sin haber definido perfil aún.
class _BrowseMarker extends StatelessWidget {
  final int priceUsd;
  final bool isAnticretico;
  final bool isSelected;

  const _BrowseMarker({
    required this.priceUsd,
    required this.isAnticretico,
    required this.isSelected,
  });

  @override
  Widget build(BuildContext context) {
    final label = priceUsd > 0
        ? '\$${(priceUsd / 1000).toStringAsFixed(0)}k'
        : 'Anti.';
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: EdgeInsets.symmetric(
            horizontal: isSelected ? 10 : 8,
            vertical: isSelected ? 5 : 4,
          ),
          decoration: BoxDecoration(
            color: HitoTokens.paper,
            borderRadius: BorderRadius.circular(HitoTokens.r2xl),
            border: Border.all(
              color: isSelected ? HitoTokens.teal : HitoTokens.borderStrong,
              width: isSelected ? 2 : 1.2,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color.fromRGBO(13, 27, 42, 0.15),
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.home_rounded,
                size: isSelected ? 13 : 11,
                color: HitoTokens.teal,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: GoogleFonts.geist(
                  fontSize: isSelected ? 12 : 11,
                  fontWeight: FontWeight.w700,
                  color: HitoTokens.ink1,
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
