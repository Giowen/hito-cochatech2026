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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startStream());
  }

  // No dispose extra — el _typeOut chequea `mounted` en cada iteración y se
  // detiene solo cuando el widget muere.

  Future<void> _startStream() async {
    final propertiesAsync = ref.read(propertiesProvider);
    final properties = propertiesAsync.value;
    if (properties == null) {
      if (mounted) {
        setState(() {
          _streamedText =
              'Cargando inventario… volvé a abrir esta tarjeta en un momento.';
          _streaming = false;
        });
      }
      return;
    }

    final property =
        {for (final p in properties) p.id: p}[widget.propertyId];
    if (property == null) {
      if (mounted) {
        setState(() {
          _streamedText = 'Propiedad no encontrada (id: ${widget.propertyId}).';
          _streaming = false;
        });
      }
      return;
    }

    final profile = ref.read(clientProfileProvider);
    if (profile == null) {
      if (mounted) {
        setState(() {
          _streamedText =
              'Aún no has definido qué buscas. Toca el micrófono o '
              'escribe tu búsqueda para que la IA evalúe esta propiedad.';
          _streaming = false;
        });
      }
      return;
    }

    final matchesAsync = ref.read(matchResultsProvider);
    final matches = matchesAsync.value ?? const [];
    final match = matches
        .where((m) => m.propertyId == widget.propertyId)
        .firstOrNull;

    // Si la propiedad fue descartada por el prefilter (no está en
    // matchResults), no streameamos un score falseado. Mostramos mensaje
    // claro: no pasó los criterios duros.
    if (match == null) {
      if (mounted) {
        setState(() {
          _streamedText =
              'Esta propiedad no pasó tus filtros iniciales — la modalidad, '
              'el tipo de propiedad, o el mínimo de dormitorios no coinciden '
              'con lo que pediste. Está visible en el mapa para que la '
              'puedas explorar, pero no es un match recomendado.';
          _streaming = false;
        });
      }
      return;
    }

    // Animar SIEMPRE localmente desde el match ya scoreado.
    //
    // Antes: explainStreaming consultaba el cache → si miss, abría stream a
    // Groq cuyos chunks llegan en bursts grandes (5-30 chars por chunk) → el
    // efecto "typing" se rompía y el texto aparecía de golpe. Ahora siempre
    // tenemos match.explanation en memoria (lo trae el matchResultsProvider).
    // Animamos char-by-char con un delay constante para una sensación
    // consistente sin importar cache hit/miss.
    final text = match.explanation.isEmpty
        ? '${match.compatibilityPercent}% compatible contigo.'
        : '${match.compatibilityPercent}% compatible contigo. ${match.explanation}';
    _typeOut(text);
  }

  /// Anima [text] char-by-char en `_streamedText`. Cancela limpiamente si
  /// el widget se unmonta.
  Future<void> _typeOut(String text) async {
    final buffer = StringBuffer();
    for (var i = 0; i < text.length; i++) {
      if (!mounted) return;
      buffer.write(text[i]);
      setState(() => _streamedText = buffer.toString());
      // Pause ligeramente más en puntuación para sensación "human-like".
      final c = text[i];
      final delay = (c == '.' || c == ',' || c == ';') ? 60 : 12;
      await Future<void>.delayed(Duration(milliseconds: delay));
    }
    if (mounted) setState(() => _streaming = false);
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
            if (match.recommended.isNotEmpty) ...[
              const SizedBox(height: 16),
              _FactorSection(
                label: 'RECOMENDADO',
                icon: Icons.check_circle_rounded,
                color: HitoTokens.success,
                items: match.recommended,
              ),
            ],
            if (match.considerations.isNotEmpty) ...[
              const SizedBox(height: 12),
              _FactorSection(
                label: 'A TENER EN CUENTA',
                icon: Icons.info_outline_rounded,
                color: HitoTokens.warning,
                items: match.considerations,
              ),
            ],
            if (match.risks.isNotEmpty) ...[
              const SizedBox(height: 12),
              _FactorSection(
                label: 'RIESGO',
                icon: Icons.warning_amber_rounded,
                color: HitoTokens.danger,
                items: match.risks,
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
              const SizedBox(height: 3),
              // Línea 1: bedrooms · baños · área construida · parqueos · precio
              Text(
                [
                  if (neighborhood.isNotEmpty) neighborhood,
                  '\$${(property.priceUsdParalelo / 1000).toStringAsFixed(0)}k USD',
                ].join(' · '),
                style: GoogleFonts.geist(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: HitoTokens.ink2,
                ),
              ),
              const SizedBox(height: 2),
              // Línea 2: dormitorios + baños + parqueos
              Text(
                [
                  '${property.bedrooms} dorm',
                  '${property.bathrooms} baños',
                  if (property.parking > 0) '${property.parking} parqueo${property.parking > 1 ? "s" : ""}',
                ].join(' · '),
                style: GoogleFonts.geist(
                  fontSize: 11,
                  color: HitoTokens.ink3,
                ),
              ),
              const SizedBox(height: 1),
              // Línea 3: superficie + año
              Text(
                [
                  '${property.areaM2}m² construido',
                  if (property.lotM2 != null) 'lote ${property.lotM2}m²',
                  if (property.yearBuilt != null) 'año ${property.yearBuilt}',
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

/// Sección con header (label + color) y lista vertical de items con bullet
/// teñido. Reemplaza al viejo `_ChipFactor` para dar jerarquía visual clara
/// entre recommended/considerations/risks.
class _FactorSection extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final List<String> items;

  const _FactorSection({
    required this.label,
    required this.icon,
    required this.color,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: color.withAlpha(14),
        borderRadius: BorderRadius.circular(HitoTokens.rMd),
        border: Border.all(color: color.withAlpha(60)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.geist(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 6, right: 8),
                    child: Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      item,
                      style: GoogleFonts.geist(
                        fontSize: 12.5,
                        color: HitoTokens.ink1,
                        height: 1.5,
                      ),
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
