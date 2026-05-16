import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/match_result.dart';
import '../models/property.dart';
import '../providers.dart';
import '../theme.dart';
import 'valuation_sheet.dart';

/// Bottom sheet con AI streaming explanation. Acto 1 wow #4 del pitch.
/// Streamed char-by-char tipo "AI typing" desde property.aiNotes.
class MatchExplanationSheet extends ConsumerStatefulWidget {
  final String propertyId;
  const MatchExplanationSheet({super.key, required this.propertyId});

  @override
  ConsumerState<MatchExplanationSheet> createState() =>
      _MatchExplanationSheetState();
}

class _MatchExplanationSheetState
    extends ConsumerState<MatchExplanationSheet> {
  String _streamedText = '';
  bool _streaming = true;
  StreamSubscription<String>? _subscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startStream());
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _startStream() async {
    final propertiesAsync = ref.read(propertiesProvider);
    final properties = propertiesAsync.value;
    if (properties == null) return;

    final property =
        {for (final p in properties) p.id: p}[widget.propertyId];
    if (property == null) return;

    final profile = ref.read(clientProfileProvider);
    final service = ref.read(matchingServiceProvider);

    final buffer = StringBuffer();
    _subscription = service
        .explainStreaming(profile: profile, property: property)
        .listen(
      (delta) {
        if (!mounted) return;
        buffer.write(delta);
        setState(() => _streamedText = buffer.toString());
      },
      onDone: () {
        if (!mounted) return;
        setState(() => _streaming = false);
      },
      onError: (e) {
        if (!mounted) return;
        setState(() {
          _streamedText = '$_streamedText\n\nError: $e';
          _streaming = false;
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final propertiesAsync = ref.watch(propertiesProvider);
    final matchesAsync = ref.watch(matchResultsProvider);

    return propertiesAsync.when(
      loading: () => const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => SizedBox(
        height: 200,
        child: Center(child: Text('Error: $e')),
      ),
      data: (properties) {
        final property =
            {for (final p in properties) p.id: p}[widget.propertyId];
        if (property == null) return const SizedBox(height: 100);
        return matchesAsync.when(
          loading: () => const SizedBox(
            height: 200,
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => SizedBox(
            height: 200,
            child: Center(child: Text('Error: $e')),
          ),
          data: (matches) {
            final match = matches.firstWhere(
              (m) => m.propertyId == widget.propertyId,
              orElse: () => MatchResult(
                propertyId: widget.propertyId,
                clientProfileId: '',
                compatibilityPercent: 0,
                explanation: '',
                positiveFactors: const [],
                negativeFactors: const [],
                tagsMatched: const [],
                tagsMissing: const [],
              ),
            );
            return _Body(
              property: property,
              match: match,
              streamedText: _streamedText,
              streaming: _streaming,
              onOpenValuation: () {
                Navigator.of(context).pop();
                showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  showDragHandle: true,
                  builder: (_) =>
                      ValuationSheet(propertyId: widget.propertyId),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _Body extends StatelessWidget {
  final Property property;
  final MatchResult match;
  final String streamedText;
  final bool streaming;
  final VoidCallback onOpenValuation;

  const _Body({
    required this.property,
    required this.match,
    required this.streamedText,
    required this.streaming,
    required this.onOpenValuation,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(property: property, score: match.compatibilityPercent),
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(Icons.auto_awesome, size: 14, color: HitoTokens.teal),
                const SizedBox(width: 6),
                Text(
                  'AI análisis',
                  style: GoogleFonts.geist(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: HitoTokens.teal2,
                    letterSpacing: 0.6,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 80),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: HitoTokens.paper2,
                borderRadius: BorderRadius.circular(HitoTokens.rLg),
                border: Border.all(color: HitoTokens.border),
              ),
              child: _StreamingText(
                text: streamedText,
                isStreaming: streaming,
              ),
            ),
            if (match.positiveFactors.isNotEmpty) ...[
              const SizedBox(height: 14),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: match.positiveFactors
                    .map(
                      (f) => _ChipFactor(
                        icon: Icons.check_circle_rounded,
                        color: HitoTokens.success,
                        label: f,
                      ),
                    )
                    .toList(),
              ),
            ],
            if (match.negativeFactors.isNotEmpty) ...[
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: match.negativeFactors
                    .map(
                      (f) => _ChipFactor(
                        icon: Icons.remove_circle_rounded,
                        color: HitoTokens.warning,
                        label: f,
                      ),
                    )
                    .toList(),
              ),
            ],
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onOpenValuation,
              icon: const Icon(Icons.trending_up_rounded),
              label: const Text('Ver valuación dinámica'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final Property property;
  final int score;
  const _Header({required this.property, required this.score});

  @override
  Widget build(BuildContext context) {
    final color = compatibilityColor(score);
    final neighborhood = (property.neighborhood ?? '')
        .split('_')
        .map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');

    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: Text(
            '$score',
            style: GoogleFonts.geist(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                property.displayTitle,
                style: GoogleFonts.geist(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: HitoTokens.ink1,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                [
                  if (neighborhood.isNotEmpty) neighborhood,
                  '\$${(property.priceUsdParalelo / 1000).toStringAsFixed(0)}k USD',
                  '${property.bedrooms}d',
                  '${property.areaM2} m²',
                ].join(' · '),
                style: GoogleFonts.geist(
                  fontSize: 11,
                  color: HitoTokens.ink3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ChipFactor extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;

  const _ChipFactor({
    required this.icon,
    required this.color,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(18),
        borderRadius: BorderRadius.circular(HitoTokens.rMd),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.geist(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _StreamingText extends StatelessWidget {
  final String text;
  final bool isStreaming;
  const _StreamingText({required this.text, required this.isStreaming});

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: GoogleFonts.geist(
          fontSize: 14,
          color: HitoTokens.ink1,
          height: 1.55,
        ),
        children: [
          TextSpan(text: text),
          if (isStreaming)
            const WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: _BlinkingCursor(),
            ),
        ],
      ),
    );
  }
}

class _BlinkingCursor extends StatefulWidget {
  const _BlinkingCursor();

  @override
  State<_BlinkingCursor> createState() => _BlinkingCursorState();
}

class _BlinkingCursorState extends State<_BlinkingCursor>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller,
      child: Container(
        width: 6,
        height: 16,
        color: HitoTokens.teal,
        margin: const EdgeInsets.only(left: 2),
      ),
    );
  }
}
