import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/property.dart';
import '../models/valuation_report.dart';
import '../providers.dart';
import '../screens/contract_analysis_screen.dart';
import '../theme.dart';
import '../utils/tc_paralelo.dart';

/// ValuationSheet — claude-design canonical layout.
/// Low/mid/high range + confidence + 7 factors ponderados + 5 comparables + recommendation
/// según viewMode global (María/Juan toggle del top bar).
class ValuationSheet extends ConsumerStatefulWidget {
  final String propertyId;
  const ValuationSheet({super.key, required this.propertyId});

  @override
  ConsumerState<ValuationSheet> createState() => _ValuationSheetState();
}

class _ValuationSheetState extends ConsumerState<ValuationSheet> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(activeValuationPropertyIdProvider.notifier)
          .set(widget.propertyId);
    });
  }

  @override
  void dispose() {
    Future.microtask(() {
      try {
        ref.read(activeValuationPropertyIdProvider.notifier).set(null);
      } catch (_) {}
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final valuationAsync = ref.watch(valuationProvider(widget.propertyId));
    final propertiesAsync = ref.watch(propertiesProvider);
    final viewMode = ref.watch(viewModeProvider);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: valuationAsync.when(
          loading: () => const SizedBox(
            height: 220,
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => SizedBox(
            height: 220,
            child: Center(child: Text('Error: $e')),
          ),
          data: (valuation) => propertiesAsync.when(
            loading: () => const SizedBox(
              height: 220,
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => SizedBox(
              height: 220,
              child: Center(child: Text('Error: $e')),
            ),
            data: (properties) {
              final propMap = {for (final p in properties) p.id: p};
              final property = propMap[widget.propertyId];
              if (property == null) return const SizedBox.shrink();
              return _Body(
                property: property,
                valuation: valuation,
                viewMode: viewMode,
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  final Property property;
  final ValuationReport valuation;
  final ViewMode viewMode;

  const _Body({
    required this.property,
    required this.valuation,
    required this.viewMode,
  });

  Color _deltaColor() {
    if (valuation.deltaPercent < -5) return HitoTokens.danger;
    if (valuation.deltaPercent > 5) return HitoTokens.success;
    return HitoTokens.info;
  }

  String _deltaLabel() {
    if (valuation.deltaPercent < -5) return 'Sobrevalorada';
    if (valuation.deltaPercent > 5) return 'Subvalorada';
    return 'A precio';
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _Header(property: property, confidence: valuation.confidenceScore),
          const SizedBox(height: 18),
          _PriceRange(
            low: valuation.estimatedValueUsdLow ??
                valuation.estimatedValueUsdParalelo,
            mid: valuation.estimatedValueUsdParalelo,
            high: valuation.estimatedValueUsdHigh ??
                valuation.estimatedValueUsdParalelo,
            listedUsd: property.priceUsdParalelo,
          ),
          const SizedBox(height: 12),
          _DeltaBadge(
            deltaPercent: valuation.deltaPercent,
            color: _deltaColor(),
            label: _deltaLabel(),
            listedUsd: property.priceUsdParalelo,
            estimatedUsd: valuation.estimatedValueUsdParalelo,
          ),
          const SizedBox(height: 14),
          _TcParaleloPill(rate: valuation.usdParaleloRateUsed),
          if (valuation.factors.isNotEmpty) ...[
            const SizedBox(height: 18),
            _SectionLabel(label: 'FACTORES PONDERADOS'),
            const SizedBox(height: 8),
            ...valuation.factors.map((f) => _FactorRow(text: f)),
          ],
          if (valuation.comparableDetails.isNotEmpty) ...[
            const SizedBox(height: 18),
            _SectionLabel(
                label:
                    '${valuation.comparableDetails.length} COMPARABLES VENDIDOS / ACTIVOS'),
            const SizedBox(height: 8),
            ...valuation.comparableDetails.map((c) => _ComparableRow(text: c)),
          ],
          const SizedBox(height: 18),
          _RecommendationCard(
            viewMode: viewMode,
            forAgent: valuation.recommendationForAgent,
            forClient: valuation.recommendationForClient,
          ),
          if (valuation.reasoning.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.info_outline,
                    size: 14, color: HitoTokens.ink4),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    valuation.reasoning,
                    style: GoogleFonts.geist(
                      fontSize: 11,
                      color: HitoTokens.ink3,
                      fontStyle: FontStyle.italic,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      ContractAnalysisScreen(propertyId: property.id),
                ),
              );
            },
            icon: const Icon(Icons.shield_outlined),
            label: const Text(
                'Revisar contrato anticrético con tu copiloto legal'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final Property property;
  final double confidence;
  const _Header({required this.property, required this.confidence});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: HitoTokens.paper2,
            borderRadius: BorderRadius.circular(HitoTokens.rMd),
          ),
          child: Icon(Icons.calculate, color: HitoTokens.teal, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Valuación dinámica',
                style: GoogleFonts.instrumentSerif(
                  fontSize: 22,
                  color: HitoTokens.ink1,
                  height: 1.0,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                property.displayTitle,
                style: GoogleFonts.geist(
                  fontSize: 12,
                  color: HitoTokens.ink3,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        _ConfidencePill(confidence: confidence),
      ],
    );
  }
}

class _ConfidencePill extends StatelessWidget {
  final double confidence;
  const _ConfidencePill({required this.confidence});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: HitoTokens.successBg,
        borderRadius: BorderRadius.circular(HitoTokens.rMd),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified, size: 12, color: HitoTokens.success),
          const SizedBox(width: 4),
          Text(
            '${(confidence * 100).round()}% confianza',
            style: GoogleFonts.geist(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: HitoTokens.success,
            ),
          ),
        ],
      ),
    );
  }
}

class _PriceRange extends StatelessWidget {
  final int low;
  final int mid;
  final int high;
  final int listedUsd;

  const _PriceRange({
    required this.low,
    required this.mid,
    required this.high,
    required this.listedUsd,
  });

  String _fmtK(int v) =>
      '\$${(v / 1000).toStringAsFixed(0)}k';

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: HitoTokens.paper,
        borderRadius: BorderRadius.circular(HitoTokens.rLg),
        border: Border.all(color: HitoTokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'RANGO ESTIMADO DE MERCADO',
            style: GoogleFonts.geist(
              fontSize: 10,
              letterSpacing: 1.0,
              fontWeight: FontWeight.w600,
              color: HitoTokens.ink4,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _PricePoint(label: 'Bajo', value: _fmtK(low), emphasized: false),
              const Spacer(),
              _PricePoint(label: 'Estimado', value: _fmtK(mid), emphasized: true),
              const Spacer(),
              _PricePoint(label: 'Alto', value: _fmtK(high), emphasized: false),
            ],
          ),
          const SizedBox(height: 14),
          _RangeBar(low: low, mid: mid, high: high, listed: listedUsd),
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: HitoTokens.ink2,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'Listado: ${_fmtK(listedUsd)} USD',
                style: GoogleFonts.geist(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: HitoTokens.ink2,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PricePoint extends StatelessWidget {
  final String label;
  final String value;
  final bool emphasized;
  const _PricePoint({
    required this.label,
    required this.value,
    required this.emphasized,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          label,
          style: GoogleFonts.geist(
            fontSize: 10,
            color: HitoTokens.ink4,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: GoogleFonts.geist(
            fontSize: emphasized ? 22 : 16,
            fontWeight: emphasized ? FontWeight.w700 : FontWeight.w600,
            color: emphasized ? HitoTokens.teal : HitoTokens.ink2,
          ),
        ),
      ],
    );
  }
}

class _RangeBar extends StatelessWidget {
  final int low;
  final int mid;
  final int high;
  final int listed;

  const _RangeBar({
    required this.low,
    required this.mid,
    required this.high,
    required this.listed,
  });

  @override
  Widget build(BuildContext context) {
    // Use a fixed display range slightly broader than low..high
    final span = (high - low).clamp(1, 1 << 31);
    final extendedLow = (low - span * 0.15).round();
    final extendedHigh = (high + span * 0.15).round();
    final extSpan = (extendedHigh - extendedLow).clamp(1, 1 << 31);

    double pct(int v) =>
        ((v - extendedLow) / extSpan).clamp(0.0, 1.0);

    return SizedBox(
      height: 28,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final lowPx = pct(low) * w;
          final highPx = pct(high) * w;
          final midPx = pct(mid) * w;
          final listedPx = pct(listed) * w;

          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                top: 12,
                left: 0,
                right: 0,
                child: Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: HitoTokens.paper3,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Positioned(
                top: 12,
                left: lowPx,
                width: (highPx - lowPx).clamp(0.0, w),
                child: Container(
                  height: 4,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [
                      HitoTokens.teal2,
                      HitoTokens.teal,
                    ]),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Positioned(
                top: 8,
                left: midPx - 6,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: HitoTokens.teal,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),
              Positioned(
                top: 6,
                left: listedPx - 7,
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: HitoTokens.ink2,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DeltaBadge extends StatelessWidget {
  final double deltaPercent;
  final Color color;
  final String label;
  final int listedUsd;
  final int estimatedUsd;

  const _DeltaBadge({
    required this.deltaPercent,
    required this.color,
    required this.label,
    required this.listedUsd,
    required this.estimatedUsd,
  });

  @override
  Widget build(BuildContext context) {
    final diff = (estimatedUsd - listedUsd).abs();
    final sign = deltaPercent > 0 ? '+' : '−';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(HitoTokens.rMd),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Icon(
              deltaPercent > 0
                  ? Icons.trending_up
                  : (deltaPercent < 0 ? Icons.trending_down : Icons.trending_flat),
              size: 16,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$label  $sign${deltaPercent.abs().toStringAsFixed(1)}%',
                  style: GoogleFonts.geist(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                Text(
                  '$sign\$${(diff / 1000).toStringAsFixed(0)}k USD vs mid de mercado',
                  style: GoogleFonts.geist(
                    fontSize: 11,
                    color: HitoTokens.ink3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TcParaleloPill extends StatelessWidget {
  final double rate;
  const _TcParaleloPill({required this.rate});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: HitoTokens.paper2,
        borderRadius: BorderRadius.circular(HitoTokens.rMd),
      ),
      child: Row(
        children: [
          Icon(Icons.currency_exchange, size: 14, color: HitoTokens.gold),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'TC paralelo ${rate.toStringAsFixed(2)} Bs/USD (oficial ${TcParalelo.oficial})',
              style: GoogleFonts.geist(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: HitoTokens.ink2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: GoogleFonts.geist(
        fontSize: 10,
        letterSpacing: 1.0,
        fontWeight: FontWeight.w600,
        color: HitoTokens.ink4,
      ),
    );
  }
}

class _FactorRow extends StatelessWidget {
  final String text;
  const _FactorRow({required this.text});

  @override
  Widget build(BuildContext context) {
    final positive = text.startsWith('+');
    final color = positive ? HitoTokens.success : HitoTokens.danger;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.geist(
                fontSize: 12,
                color: HitoTokens.ink2,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ComparableRow extends StatelessWidget {
  final String text;
  const _ComparableRow({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(Icons.location_on_outlined, size: 14, color: HitoTokens.ink4),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.geist(
                fontSize: 11,
                color: HitoTokens.ink2,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecommendationCard extends StatelessWidget {
  final ViewMode viewMode;
  final String forAgent;
  final String forClient;

  const _RecommendationCard({
    required this.viewMode,
    required this.forAgent,
    required this.forClient,
  });

  @override
  Widget build(BuildContext context) {
    final agent = viewMode == ViewMode.agent;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: Container(
        key: ValueKey(agent),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: HitoTokens.paper2,
          borderRadius: BorderRadius.circular(HitoTokens.rLg),
          border: Border.all(color: HitoTokens.teal2),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: HitoTokens.teal,
                shape: BoxShape.circle,
              ),
              child: Text(
                agent ? 'M' : 'J',
                style: GoogleFonts.geist(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    agent
                        ? 'Recomendación para María (agente)'
                        : 'Recomendación para Juan (cliente)',
                    style: GoogleFonts.geist(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: HitoTokens.teal2,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    agent ? forAgent : forClient,
                    style: GoogleFonts.geist(
                      fontSize: 13,
                      color: HitoTokens.ink1,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
