import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/match_result.dart';
import '../models/property.dart';
import '../providers.dart';

/// Bottom sheet con AI streaming explanation del match.
/// Stream char-by-char tipo "AI typing" (Sprint 2.3).
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
          _streamedText = '$_streamedText\n\n❌ Error: $e';
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
        if (property == null) {
          return const SizedBox(height: 100);
        }
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
            return _SheetBody(
              property: property,
              match: match,
              streamedText: _streamedText,
              streaming: _streaming,
            );
          },
        );
      },
    );
  }
}

class _SheetBody extends StatelessWidget {
  final Property property;
  final MatchResult match;
  final String streamedText;
  final bool streaming;

  const _SheetBody({
    required this.property,
    required this.match,
    required this.streamedText,
    required this.streaming,
  });

  Color _bucketColor() {
    switch (match.colorBucket) {
      case 'green':
        return Colors.green.shade600;
      case 'amber':
        return Colors.orange.shade600;
      default:
        return Colors.grey.shade500;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bucketColor = _bucketColor();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    property.type == 'casa' ? Icons.home : Icons.apartment,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        property.address,
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '${(property.priceBob / 1000).toStringAsFixed(0)}K Bs · '
                        '${property.bedrooms} dorm · ${property.areaM2} m²',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.grey.shade600,
                            ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: bucketColor,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${match.compatibilityPercent}%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(
                  Icons.auto_awesome,
                  size: 16,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  'AI análisis',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 80),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(10),
              ),
              child: _StreamingText(
                text: streamedText,
                isStreaming: streaming,
              ),
            ),
            if (match.tagsMatched.isNotEmpty) ...[
              const SizedBox(height: 14),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: match.tagsMatched
                    .map(
                      (t) => Chip(
                        avatar: Icon(
                          Icons.check_circle,
                          size: 16,
                          color: Colors.green.shade700,
                        ),
                        label: Text(t.replaceAll('_', ' ')),
                        padding: EdgeInsets.zero,
                        materialTapTargetSize:
                            MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                        labelStyle: const TextStyle(fontSize: 11),
                      ),
                    )
                    .toList(),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton.tonalIcon(
              onPressed: null,
              icon: const Icon(Icons.calculate),
              label: const Text('Ver valuación (Sprint 3)'),
            ),
          ],
        ),
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
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.5),
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
      duration: const Duration(milliseconds: 600),
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
        width: 10,
        height: 18,
        color: Theme.of(context).colorScheme.primary,
        margin: const EdgeInsets.only(left: 2),
      ),
    );
  }
}
