import 'package:flutter/material.dart';
import 'map_test.dart';
import 'voice_test.dart';
import 'groq_test.dart';
import 'heatmap_test.dart';

/// Index para los 4 tests de stack validation (Phase 0 del roadmap).
/// Cada card abre una página dedicada para validar manualmente.
class StackValidationIndex extends StatelessWidget {
  const StackValidationIndex({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hito — Stack Validation'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Text(
              'Valida los 4 tests obligatorios del §12 del PRD. Cada uno debe pasar antes de avanzar a Phase 1.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey.shade700,
              ),
            ),
          ),
          const SizedBox(height: 8),
          _TestCard(
            icon: Icons.map,
            title: 'Test 1: flutter_map + OSM',
            subtitle: 'Validar tiles OSM en Cochabamba',
            destination: const MapTestPage(),
          ),
          _TestCard(
            icon: Icons.mic,
            title: 'Test 2: record audio HTTPS',
            subtitle: 'Validar captura de audio en navegador',
            destination: const VoiceTestPage(),
          ),
          _TestCard(
            icon: Icons.bolt,
            title: 'Test 3: Groq streaming',
            subtitle: 'Validar Llama 3.3 first token <2s',
            destination: const GroqTestPage(),
          ),
          _TestCard(
            icon: Icons.gradient,
            title: 'Test 4: flutter_map_heatmap',
            subtitle: 'Validar overlay sin glitches',
            destination: const HeatmapTestPage(),
          ),
        ],
      ),
    );
  }
}

class _TestCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget destination;

  const _TestCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.destination,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: Icon(
            icon,
            color: Theme.of(context).colorScheme.onPrimaryContainer,
          ),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => destination),
        ),
      ),
    );
  }
}
