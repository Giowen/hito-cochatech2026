import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/client_profile.dart';
import '../providers.dart';
import '../widgets/property_card.dart';

/// MatchesScreen — pantalla principal con lista de propiedades scoreadas.
/// Sprint 1.3 del roadmap.
class MatchesScreen extends ConsumerWidget {
  const MatchesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final matchesAsync = ref.watch(matchResultsProvider);
    final profile = ref.watch(clientProfileProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Hito · Matches'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.map_outlined),
            tooltip: 'Vista mapa (Sprint 2.1)',
            onPressed: null, // TODO: Sprint 2.1
          ),
        ],
      ),
      body: Column(
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
      ),
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
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
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
          const SizedBox(height: 8),
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

class _MatchesList extends ConsumerWidget {
  final List matches;
  const _MatchesList({required this.matches});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final propertiesAsync = ref.watch(propertiesProvider);
    return propertiesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (properties) {
        final propMap = {for (final p in properties) p.id: p};
        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: matches.length,
          itemBuilder: (context, index) {
            final match = matches[index];
            final property = propMap[match.propertyId];
            if (property == null) return const SizedBox.shrink();
            return PropertyCard(
              property: property,
              match: match,
              onTap: () {
                // TODO Sprint 2.3: navegar a detail con AI streaming explanation
              },
            );
          },
        );
      },
    );
  }
}
