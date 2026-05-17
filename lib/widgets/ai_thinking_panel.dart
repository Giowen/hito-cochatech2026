import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/match_result.dart';
import '../models/property.dart';
import '../providers.dart';
import '../theme.dart';

/// AiThinkingPanel — panel lateral derecho que muestra el pipeline de la IA
/// en vivo: interpretación de criterios, filtrado, scoring, explicación.
///
/// States derived from providers:
///   - profile null → todos pasos pending (gris)
///   - profile set + matches loading → step1 done, resto en progreso
///   - matches ready → todos pasos done, render preview de matches
///
/// Tono: como "ChatGPT thinking" — el cliente ve qué hace la IA en cada
/// momento, no es una caja negra. Aumenta confianza vs scores opacos.
class AiThinkingPanel extends ConsumerWidget {
  const AiThinkingPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(clientProfileProvider);
    final matchesAsync = ref.watch(matchResultsProvider);
    final propertiesAsync = ref.watch(propertiesProvider);

    final hasProfile = profile != null;
    final isLoading = matchesAsync.isLoading;
    final hasMatches = matchesAsync.hasValue && (matchesAsync.value?.isNotEmpty ?? false);

    return Container(
      color: HitoTokens.bone,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(
            isLoading: isLoading,
            isDone: hasMatches,
            propCount: matchesAsync.value?.length ?? 0,
          ),
          const SizedBox(height: 14),
          if (hasProfile && profile.voiceInputTranscript != null)
            _TranscriptQuote(transcript: profile.voiceInputTranscript!),
          if (hasProfile && profile.voiceInputTranscript != null)
            const SizedBox(height: 14),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _PipelineSteps(
                    profile: profile,
                    matchesAsync: matchesAsync,
                    totalProperties: propertiesAsync.value?.length ?? 0,
                  ),
                  if (hasMatches) ...[
                    const SizedBox(height: 18),
                    _MatchesPreview(matches: matchesAsync.value!),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          _Footer(),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final bool isLoading;
  final bool isDone;
  final int propCount;
  const _Header({
    required this.isLoading,
    required this.isDone,
    required this.propCount,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: HitoTokens.teal,
            borderRadius: BorderRadius.circular(HitoTokens.rMd),
          ),
          child: Icon(
            isLoading
                ? Icons.auto_awesome
                : isDone
                    ? Icons.check_rounded
                    : Icons.auto_awesome,
            color: Colors.white,
            size: 18,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Hito IA',
                style: GoogleFonts.instrumentSerif(
                  fontSize: 22,
                  color: HitoTokens.ink1,
                  height: 1.0,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  if (isLoading)
                    const SizedBox(
                      width: 10,
                      height: 10,
                      child: CircularProgressIndicator(strokeWidth: 1.5),
                    )
                  else if (isDone)
                    Icon(Icons.verified_rounded,
                        size: 12, color: HitoTokens.success)
                  else
                    Icon(Icons.circle_outlined,
                        size: 12, color: HitoTokens.ink4),
                  const SizedBox(width: 6),
                  Text(
                    isLoading
                        ? 'Pensando...'
                        : isDone
                            ? 'Análisis completo · $propCount propiedades'
                            : 'Esperando tu búsqueda',
                    style: GoogleFonts.geist(
                      fontSize: 11,
                      color: HitoTokens.ink3,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TranscriptQuote extends StatelessWidget {
  final String transcript;
  const _TranscriptQuote({required this.transcript});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: HitoTokens.paper2,
        borderRadius: BorderRadius.circular(HitoTokens.rMd),
        border: Border.all(color: HitoTokens.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.format_quote_rounded,
              size: 14, color: HitoTokens.ink4),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              transcript,
              style: GoogleFonts.geist(
                fontSize: 11.5,
                color: HitoTokens.ink2,
                fontStyle: FontStyle.italic,
                height: 1.5,
              ),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _PipelineSteps extends StatelessWidget {
  final dynamic profile;
  final AsyncValue<List<MatchResult>> matchesAsync;
  final int totalProperties;
  const _PipelineSteps({
    required this.profile,
    required this.matchesAsync,
    required this.totalProperties,
  });

  @override
  Widget build(BuildContext context) {
    final hasProfile = profile != null;
    final isLoading = matchesAsync.isLoading;
    final hasMatches = matchesAsync.hasValue && (matchesAsync.value?.isNotEmpty ?? false);
    final matchCount = matchesAsync.value?.length ?? 0;

    // Step 1: Interpretando criterios
    final step1Done = hasProfile;
    final step1Subtitle = hasProfile
        ? _formatProfileSummary(profile)
        : 'Esperando query del cliente';

    // Step 2: Filtrando propiedades
    final step2Done = hasMatches || (!isLoading && hasProfile);
    final step2Active = hasProfile && isLoading;
    final step2Subtitle = hasMatches && totalProperties > 0
        ? '$totalProperties → $matchCount (top matches por algoritmo)'
        : (step2Active ? 'Aplicando filtros duros: modalidad, tipo, dormitorios...' : 'Sin búsqueda activa');

    // Step 3: Calculando compatibilidad
    final step3Done = hasMatches;
    final step3Active = hasProfile && isLoading;
    final step3Subtitle = hasMatches
        ? 'Ponderado: presupuesto 35% · distancia 25% · modalidad 15% · dormitorios 15% · tags 10%'
        : (step3Active ? 'Llama 3.3 70B evaluando cada candidato...' : 'Pendiente');

    // Step 4: Generando explicaciones
    final step4Done = hasMatches;
    final step4Active = hasProfile && isLoading;
    final step4Subtitle = hasMatches
        ? 'Caps aplicados client-side: presupuesto, distancia, modalidad'
        : (step4Active ? 'Conectando criterios con cada propiedad...' : 'Pendiente');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StepRow(
          icon: Icons.psychology_outlined,
          title: 'Interpretando criterios',
          subtitle: step1Subtitle,
          done: step1Done,
          active: !step1Done && !hasProfile,
        ),
        _StepRow(
          icon: Icons.filter_alt_outlined,
          title: 'Filtrando propiedades',
          subtitle: step2Subtitle,
          done: step2Done,
          active: step2Active,
        ),
        _StepRow(
          icon: Icons.calculate_outlined,
          title: 'Calculando compatibilidad',
          subtitle: step3Subtitle,
          done: step3Done,
          active: step3Active,
        ),
        _StepRow(
          icon: Icons.auto_stories_outlined,
          title: 'Generando explicaciones',
          subtitle: step4Subtitle,
          done: step4Done,
          active: step4Active,
        ),
      ],
    );
  }

  String _formatProfileSummary(dynamic profile) {
    final parts = <String>[];
    if (profile.transactionType != null) {
      parts.add(profile.transactionType.toString());
    }
    if (profile.minBedrooms != null && profile.minBedrooms > 0) {
      parts.add('${profile.minBedrooms}+ dorm');
    }
    final usdMax = profile.budgetMax / 12.20;
    if (usdMax > 0) {
      parts.add('máx \$${(usdMax / 1000).toStringAsFixed(0)}k USD');
    }
    if (profile.requiredTags != null &&
        (profile.requiredTags as List).isNotEmpty) {
      final tags = (profile.requiredTags as List<String>).take(2).join(', ');
      parts.add(tags);
    }
    return parts.join(' · ');
  }
}

class _StepRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool done;
  final bool active;

  const _StepRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.done,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    final color = done
        ? HitoTokens.success
        : active
            ? HitoTokens.teal
            : HitoTokens.ink4;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: active
                ? const Padding(
                    padding: EdgeInsets.all(2),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    done ? Icons.check_circle_rounded : icon,
                    size: 20,
                    color: color,
                  ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.geist(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: done ? HitoTokens.ink1 : HitoTokens.ink2,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: GoogleFonts.geist(
                    fontSize: 11,
                    color: HitoTokens.ink3,
                    height: 1.45,
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

class _MatchesPreview extends ConsumerWidget {
  final List<MatchResult> matches;
  const _MatchesPreview({required this.matches});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final propertiesAsync = ref.watch(propertiesProvider);
    final properties = propertiesAsync.value;
    if (properties == null) return const SizedBox.shrink();

    final propMap = {for (final p in properties) p.id: p};
    final top = matches.take(5).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8, left: 4),
          child: Text(
            'MEJORES COINCIDENCIAS',
            style: GoogleFonts.geist(
              fontSize: 10,
              letterSpacing: 1.0,
              fontWeight: FontWeight.w700,
              color: HitoTokens.ink4,
            ),
          ),
        ),
        for (var i = 0; i < top.length; i++)
          _MatchPreviewCard(
            n: i + 1,
            match: top[i],
            property: propMap[top[i].propertyId],
            isSelected: ref.watch(selectedPropertyIdProvider) ==
                top[i].propertyId,
          ),
      ],
    );
  }
}

class _MatchPreviewCard extends ConsumerWidget {
  final int n;
  final MatchResult match;
  final Property? property;
  final bool isSelected;
  const _MatchPreviewCard({
    required this.n,
    required this.match,
    required this.property,
    required this.isSelected,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (property == null) return const SizedBox.shrink();
    final p = property!;
    final score = match.compatibilityPercent;
    final color = compatibilityColor(score);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: HitoTokens.paper,
        borderRadius: BorderRadius.circular(HitoTokens.rMd),
        child: InkWell(
          borderRadius: BorderRadius.circular(HitoTokens.rMd),
          onTap: () => ref
              .read(selectedPropertyIdProvider.notifier)
              .select(p.id),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(HitoTokens.rMd),
              border: Border.all(
                color: isSelected ? color : HitoTokens.border,
                width: isSelected ? 1.5 : 1,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: HitoTokens.paper2,
                    borderRadius: BorderRadius.circular(HitoTokens.rSm),
                  ),
                  child: Text(
                    '$n.',
                    style: GoogleFonts.geist(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: HitoTokens.ink3,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              p.title ?? p.address,
                              style: GoogleFonts.geist(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: HitoTokens.ink1,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius:
                                  BorderRadius.circular(HitoTokens.rSm),
                            ),
                            child: Text(
                              '$score%',
                              style: GoogleFonts.geist(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        match.explanation.isEmpty
                            ? 'Sin explicación disponible'
                            : match.explanation,
                        style: GoogleFonts.geist(
                          fontSize: 11,
                          color: HitoTokens.ink3,
                          height: 1.4,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: HitoTokens.paper2,
        borderRadius: BorderRadius.circular(HitoTokens.rMd),
        border: Border.all(color: HitoTokens.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.verified_user_outlined,
              size: 12, color: HitoTokens.teal),
          const SizedBox(width: 6),
          Text(
            'Verificado contra Derechos Reales · DDRR',
            style: GoogleFonts.geist(
              fontSize: 10,
              color: HitoTokens.ink3,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
