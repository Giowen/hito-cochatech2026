import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/client_profile.dart';
import '../models/match_result.dart';
import '../providers.dart';
import '../widgets/properties_map.dart';
import '../widgets/property_card.dart';

/// MatchesScreen — pantalla principal con layout side-by-side (lista + mapa).
/// Sprint 1.3 (lista) + Sprint 2.1 (mapa).
class MatchesScreen extends ConsumerWidget {
  const MatchesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hito · Matches'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth > 800;
          if (isWide) {
            return const Row(
              children: [
                SizedBox(width: 400, child: _LeftPanel()),
                VerticalDivider(width: 1),
                Expanded(child: PropertiesMap()),
              ],
            );
          }
          return const _LeftPanel();
        },
      ),
    );
  }
}

class _LeftPanel extends ConsumerWidget {
  const _LeftPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final matchesAsync = ref.watch(matchResultsProvider);
    final profile = ref.watch(clientProfileProvider);

    return Column(
      children: [
        _ProfileHeader(profile: profile),
        Expanded(
          child: matchesAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Error cargando matches:\n$e',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            data: (matches) => _MatchesList(matches: matches),
          ),
        ),
      ],
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  final ClientProfile profile;
  const _ProfileHeader({required this.profile});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      color: scheme.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: scheme.primaryContainer,
                child: Icon(Icons.person, color: scheme.onPrimaryContainer),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Juan',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    Text(
                      '${profile.budgetMin ~/ 1000}K - ${profile.budgetMax ~/ 1000}K Bs · ${profile.transactionType} · ≥${profile.minBedrooms} dorm',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.grey.shade700,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: profile.requiredTags
                .map(
                  (t) => Chip(
                    label: Text(t.replaceAll('_', ' ')),
                    padding: EdgeInsets.zero,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    labelStyle: const TextStyle(fontSize: 11),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _MatchesList extends ConsumerStatefulWidget {
  final List<MatchResult> matches;
  const _MatchesList({required this.matches});

  @override
  ConsumerState<_MatchesList> createState() => _MatchesListState();
}

class _MatchesListState extends ConsumerState<_MatchesList> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollTo(String propertyId) {
    final index = widget.matches.indexWhere((m) => m.propertyId == propertyId);
    if (index < 0) return;
    // Approximate card height + margin; tune if needed
    const cardHeight = 270.0;
    final offset = (index * cardHeight).clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );
    _scrollController.animateTo(
      offset,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final propertiesAsync = ref.watch(propertiesProvider);

    // Auto-scroll list when marker is selected from map
    ref.listen<String?>(selectedPropertyIdProvider, (prev, current) {
      if (current != null && _scrollController.hasClients) {
        _scrollTo(current);
      }
    });

    return propertiesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (properties) {
        final propMap = {for (final p in properties) p.id: p};
        return ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: widget.matches.length,
          itemBuilder: (context, index) {
            final match = widget.matches[index];
            final property = propMap[match.propertyId];
            if (property == null) return const SizedBox.shrink();
            return PropertyCard(property: property, match: match);
          },
        );
      },
    );
  }
}
