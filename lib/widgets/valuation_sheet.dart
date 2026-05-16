import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/property.dart';
import '../models/valuation_report.dart';
import '../providers.dart';
import '../utils/tc_paralelo.dart';

/// ValuationSheet — Sprint 3.2 (UI) + 3.3 (vista dual María/Juan).
/// Trigger desde MatchExplanationSheet botón "Ver valuación".
/// Cuando se abre, activa activeValuationPropertyIdProvider para que el
/// mapa highlightee los 4 comparables como pins grises.
class ValuationSheet extends ConsumerStatefulWidget {
  final String propertyId;
  const ValuationSheet({super.key, required this.propertyId});

  @override
  ConsumerState<ValuationSheet> createState() => _ValuationSheetState();
}

class _ValuationSheetState extends ConsumerState<ValuationSheet> {
  bool _agentView = false;

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
    // Clear on dismiss so map stops highlighting comparables
    Future.microtask(() {
      if (!mounted) {
        // ignore: invalid_use_of_protected_member
      }
      try {
        ref.read(activeValuationPropertyIdProvider.notifier).set(null);
      } catch (_) {
        // ref may be invalidated; safe to ignore on dispose
      }
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final valuationAsync = ref.watch(valuationProvider(widget.propertyId));
    final propertiesAsync = ref.watch(propertiesProvider);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: valuationAsync.when(
          loading: () => const SizedBox(
            height: 200,
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => SizedBox(
            height: 200,
            child: Center(child: Text('Error: $e')),
          ),
          data: (valuation) => propertiesAsync.when(
            loading: () => const SizedBox(
              height: 200,
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => SizedBox(
              height: 200,
              child: Center(child: Text('Error: $e')),
            ),
            data: (properties) {
              final propMap = {for (final p in properties) p.id: p};
              final property = propMap[widget.propertyId];
              if (property == null) return const SizedBox.shrink();
              return _Body(
                property: property,
                valuation: valuation,
                comparables: valuation.comparables
                    .map((id) => propMap[id])
                    .whereType<Property>()
                    .toList(),
                agentView: _agentView,
                onViewChanged: (v) => setState(() => _agentView = v),
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
  final List<Property> comparables;
  final bool agentView;
  final ValueChanged<bool> onViewChanged;

  const _Body({
    required this.property,
    required this.valuation,
    required this.comparables,
    required this.agentView,
    required this.onViewChanged,
  });

  Color _deltaColor() {
    if (valuation.deltaPercent < -5) return Colors.red.shade700;
    if (valuation.deltaPercent > 5) return Colors.green.shade700;
    return Colors.blueGrey.shade700;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final deltaColor = _deltaColor();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.calculate, color: scheme.primary, size: 24),
            const SizedBox(width: 8),
            Text(
              'Valuación dinámica',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          property.address,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey.shade700,
              ),
        ),
        const SizedBox(height: 16),
        _ValueComparison(
          estimated: valuation.estimatedValueBob,
          estimatedUsd: valuation.estimatedValueUsdParalelo,
          listed: valuation.listedValueBob,
          deltaPercent: valuation.deltaPercent,
          deltaColor: deltaColor,
          label: valuation.label,
        ),
        const SizedBox(height: 14),
        _TcParaleloPill(rate: valuation.usdParaleloRateUsed),
        if (comparables.isNotEmpty) ...[
          const SizedBox(height: 14),
          _ComparablesSection(comparables: comparables),
        ],
        const SizedBox(height: 18),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment<bool>(
              value: false,
              label: Text('Para Juan'),
              icon: Icon(Icons.person, size: 18),
            ),
            ButtonSegment<bool>(
              value: true,
              label: Text('Para María'),
              icon: Icon(Icons.work, size: 18),
            ),
          ],
          selected: {agentView},
          onSelectionChanged: (s) => onViewChanged(s.first),
          style: SegmentedButton.styleFrom(
            visualDensity: VisualDensity.compact,
          ),
        ),
        const SizedBox(height: 10),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: Container(
            key: ValueKey(agentView),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withAlpha(70),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: scheme.primary, width: 1.2),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  agentView ? Icons.work : Icons.person,
                  color: scheme.primary,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    agentView
                        ? valuation.recommendationForAgent
                        : valuation.recommendationForClient,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (valuation.reasoning.isNotEmpty) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.info_outline, size: 14, color: Colors.grey.shade600),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  valuation.reasoning,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey.shade700,
                        fontStyle: FontStyle.italic,
                      ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _ValueComparison extends StatelessWidget {
  final int estimated;
  final int estimatedUsd;
  final int listed;
  final double deltaPercent;
  final Color deltaColor;
  final String label;

  const _ValueComparison({
    required this.estimated,
    required this.estimatedUsd,
    required this.listed,
    required this.deltaPercent,
    required this.deltaColor,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Estimado',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey.shade700,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${(estimated / 1000).toStringAsFixed(0)}K Bs',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                ),
                Text(
                  '\$${(estimatedUsd / 1000).toStringAsFixed(0)}K USD paralelo',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey.shade600,
                      ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'Listado',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade700,
                    ),
              ),
              const SizedBox(height: 2),
              Text(
                '${(listed / 1000).toStringAsFixed(0)}K Bs',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      decoration: TextDecoration.lineThrough,
                      color: Colors.grey.shade700,
                    ),
              ),
              const SizedBox(height: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: deltaColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$label ${deltaPercent.toStringAsFixed(1)}%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
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
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            Icons.currency_exchange,
            size: 16,
            color: Theme.of(context).colorScheme.onSecondaryContainer,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Ajustado por TC paralelo: ${rate.toStringAsFixed(1)} Bs/USD '
              '(oficial ${TcParalelo.oficial})',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSecondaryContainer,
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ComparablesSection extends StatelessWidget {
  final List<Property> comparables;
  const _ComparablesSection({required this.comparables});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.location_searching,
              size: 14,
              color: Colors.grey.shade700,
            ),
            const SizedBox(width: 6),
            Text(
              '${comparables.length} comparables visibles en el mapa',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: comparables
              .map(
                (p) => Chip(
                  avatar: Icon(
                    Icons.location_on,
                    size: 14,
                    color: Colors.grey.shade700,
                  ),
                  label: Text(
                    '${p.address.split(',').first} · ${(p.priceBob / 1000).toStringAsFixed(0)}K',
                  ),
                  padding: EdgeInsets.zero,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                  labelStyle: const TextStyle(fontSize: 11),
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}
