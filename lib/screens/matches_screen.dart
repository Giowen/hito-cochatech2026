import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/match_result.dart';
import '../providers.dart';
import '../theme.dart';
import '../widgets/hito_sidebar.dart';
import '../widgets/hito_top_bar.dart';
import '../widgets/match_explanation_sheet.dart';
import '../widgets/properties_map.dart';
import '../widgets/property_card.dart';
import '../widgets/voice_input_sheet.dart';

/// MatchesScreen — pantalla principal con layout sidebar + content + map.
/// Phase A.3: 3-column layout adoptando claude-design canonical.
class MatchesScreen extends ConsumerWidget {
  const MatchesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Cuando se selecciona propiedad (mapa o lista) → abrir match explanation sheet.
    ref.listen<String?>(selectedPropertyIdProvider, (prev, current) {
      if (current == null || current == prev) return;
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => MatchExplanationSheet(propertyId: current),
      ).whenComplete(() {
        ref.read(selectedPropertyIdProvider.notifier).clear();
      });
    });

    return Scaffold(
      body: Row(
        children: const [
          HitoSidebar(),
          VerticalDivider(width: 1, color: HitoTokens.border, thickness: 1),
          Expanded(
            child: Column(
              children: [
                HitoTopBar(),
                Expanded(child: _MainContent()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MainContent extends ConsumerWidget {
  const _MainContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 900;
        if (isWide) {
          return Row(
            children: const [
              SizedBox(width: 420, child: _LeftContentPanel()),
              VerticalDivider(width: 1, color: HitoTokens.border, thickness: 1),
              Expanded(child: PropertiesMap()),
            ],
          );
        }
        return const _LeftContentPanel();
      },
    );
  }
}

class _LeftContentPanel extends ConsumerWidget {
  const _LeftContentPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final matchesAsync = ref.watch(matchResultsProvider);
    final profile = ref.watch(clientProfileProvider);
    final viewMode = ref.watch(viewModeProvider);

    return Container(
      color: HitoTokens.bone,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _RoleBanner(viewMode: viewMode),
          _SearchQueryCard(
            transcript: profile.voiceInputTranscript,
            viewMode: viewMode,
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _ResultsHeader(viewMode: viewMode),
          ),
          const SizedBox(height: 8),
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

/// Banner role-specific arriba del search card.
/// Vista María (agente): contexto de lead activo, métricas de productividad.
/// Vista Juan (cliente): contexto de búsqueda personal, presupuesto.
class _RoleBanner extends StatelessWidget {
  final ViewMode viewMode;
  const _RoleBanner({required this.viewMode});

  @override
  Widget build(BuildContext context) {
    final isAgent = viewMode == ViewMode.agent;
    final accent = isAgent ? HitoTokens.teal : HitoTokens.navy;
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      decoration: BoxDecoration(
        color: HitoTokens.paper,
        borderRadius: BorderRadius.circular(HitoTokens.rMd),
        border: Border.all(color: HitoTokens.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          // Left accent stripe (3px) — usando Container interno en vez de
          // BorderSide para evitar conflicto con borderRadius del parent.
          Container(width: 3, height: 60, color: accent),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: accent,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      isAgent ? 'M' : 'J',
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
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isAgent
                              ? 'Bienvenida, María · Agente Pro'
                              : 'Hola, Juan · Familia García-López',
                          style: GoogleFonts.geist(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: HitoTokens.ink1,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isAgent
                              ? '12 listings · 3 leads · 1 contrato pendiente'
                              : 'Casa familia · hasta \$220k USD · Recoleta',
                          style: GoogleFonts.geist(
                            fontSize: 11,
                            color: HitoTokens.ink3,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchQueryCard extends ConsumerWidget {
  final String? transcript;
  final ViewMode viewMode;
  const _SearchQueryCard({required this.transcript, required this.viewMode});

  void _openVoiceInput(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const VoiceInputSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAgent = viewMode == ViewMode.agent;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 6, left: 4),
            child: Text(
              isAgent
                  ? 'BÚSQUEDA DEL CLIENTE'
                  : 'TU BÚSQUEDA POR VOZ',
              style: GoogleFonts.geist(
                fontSize: 10,
                letterSpacing: 1.0,
                fontWeight: FontWeight.w700,
                color: HitoTokens.ink4,
              ),
            ),
          ),
          Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _openVoiceInput(context),
          borderRadius: BorderRadius.circular(HitoTokens.rXl),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: HitoTokens.paper,
              borderRadius: BorderRadius.circular(HitoTokens.rXl),
              border: Border.all(color: HitoTokens.border),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(
                    Icons.search,
                    size: 18,
                    color: HitoTokens.ink3,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    transcript ??
                        'Toca el micrófono para buscar por voz...',
                    style: GoogleFonts.geist(
                      fontSize: 13,
                      color: transcript != null
                          ? HitoTokens.ink1
                          : HitoTokens.ink4,
                      height: 1.5,
                      fontStyle: transcript != null
                          ? FontStyle.normal
                          : FontStyle.italic,
                    ),
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: HitoTokens.paper2,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.mic_none_rounded,
                    size: 18,
                    color: HitoTokens.ink2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
        ],
      ),
    );
  }
}

class _ResultsHeader extends ConsumerWidget {
  final ViewMode viewMode;
  const _ResultsHeader({required this.viewMode});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final matchesAsync = ref.watch(matchResultsProvider);
    final count = matchesAsync.value?.length ?? 0;
    final isAgent = viewMode == ViewMode.agent;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isAgent
                    ? (count > 0 ? 'Matches para tu cliente' : 'Matches')
                    : (count > 0 ? '$count propiedades' : 'Resultados'),
                style: GoogleFonts.instrumentSerif(
                  fontSize: 26,
                  color: HitoTokens.ink1,
                  height: 1.0,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                isAgent
                    ? '$count propiedades · 4 con 85%+ compat · 1 con gravamen'
                    : 'Ordenadas por compatibilidad',
                style: GoogleFonts.geist(
                  fontSize: 12,
                  color: HitoTokens.ink3,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: HitoTokens.paper,
            border: Border.all(color: HitoTokens.border),
            borderRadius: BorderRadius.circular(HitoTokens.rMd),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Compatibilidad',
                style: GoogleFonts.geist(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: HitoTokens.ink2,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.expand_more_rounded,
                size: 16,
                color: HitoTokens.ink3,
              ),
            ],
          ),
        ),
      ],
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
    final index =
        widget.matches.indexWhere((m) => m.propertyId == propertyId);
    if (index < 0) return;
    const cardHeight = 130.0;
    if (!_scrollController.hasClients) return;
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

    ref.listen<String?>(selectedPropertyIdProvider, (prev, current) {
      if (current != null) _scrollTo(current);
    });

    return propertiesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (properties) {
        final propMap = {for (final p in properties) p.id: p};
        return ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
