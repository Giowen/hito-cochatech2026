import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/lead.dart';
import '../models/match_result.dart';
import '../providers.dart';
import '../theme.dart';
import '../widgets/top_banner.dart';
import '../widgets/ai_thinking_panel.dart';
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
    // Si ya hay un sheet abierto (canPop=true), lo cerramos antes para no stackear.
    ref.listen<String?>(selectedPropertyIdProvider, (prev, current) {
      if (current == null || current == prev) return;
      final nav = Navigator.of(context, rootNavigator: true);
      if (nav.canPop()) {
        nav.pop();
      }
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => MatchExplanationSheet(propertyId: current),
      ).whenComplete(() {
        ref.read(selectedPropertyIdProvider.notifier).clear();
      });
    });

    return LayoutBuilder(
      builder: (context, constraints) {
        // <900px (mobile/tablet portrait): el sidebar fijo de 240px sería
        // mitad de pantalla. Lo movemos a un Drawer + agregamos botón menu en
        // el AppBar (HitoTopBar muestra el icono cuando recibe onOpenDrawer).
        final isCompact = constraints.maxWidth < 900;
        if (isCompact) {
          return Scaffold(
            drawer: const Drawer(
              width: HitoSidebar.width,
              backgroundColor: HitoTokens.bone,
              child: HitoSidebar(),
            ),
            body: Builder(
              builder: (innerCtx) => Column(
                children: [
                  HitoTopBar(
                    onOpenDrawer: () => Scaffold.of(innerCtx).openDrawer(),
                  ),
                  const Expanded(child: _MainContent()),
                ],
              ),
            ),
          );
        }
        return const Scaffold(
          body: Row(
            children: [
              HitoSidebar(),
              VerticalDivider(
                  width: 1, color: HitoTokens.border, thickness: 1),
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
      },
    );
  }
}

class _MainContent extends ConsumerWidget {
  const _MainContent();

  /// Layout responsive:
  ///  - >=1300px: lista (357) | mapa flex | AI panel (300)
  ///  - 900-1300: lista (357) | mapa flex (AI panel hidden — toggle pendiente)
  ///  - <900:     lista (single column)
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        if (w < 900) return const _LeftContentPanel();

        final showAiPanel = w >= 1300;
        return Row(
          children: [
            const SizedBox(width: 357, child: _LeftContentPanel()),
            const VerticalDivider(
                width: 1, color: HitoTokens.border, thickness: 1),
            const Expanded(child: PropertiesMap()),
            if (showAiPanel) ...[
              const VerticalDivider(
                  width: 1, color: HitoTokens.border, thickness: 1),
              const SizedBox(width: 300, child: AiThinkingPanel()),
            ],
          ],
        );
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
          _RoleBanner(viewMode: viewMode, hasProfile: profile != null),
          _SearchQueryCard(
            transcript: profile?.voiceInputTranscript,
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
  final bool hasProfile;
  const _RoleBanner({required this.viewMode, required this.hasProfile});

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
                              : hasProfile
                                  ? 'Hola, Juan'
                                  : '¿Qué casa buscas?',
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
                              ? '12 listings · matchmaking AI · 1 contrato pendiente'
                              : hasProfile
                                  ? 'Búsqueda activa · perfil estructurado por AI'
                                  : 'Toca el micrófono y describe tu búsqueda',
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

class _SearchQueryCard extends ConsumerStatefulWidget {
  final String? transcript;
  final ViewMode viewMode;
  const _SearchQueryCard({required this.transcript, required this.viewMode});

  @override
  ConsumerState<_SearchQueryCard> createState() => _SearchQueryCardState();
}

class _SearchQueryCardState extends ConsumerState<_SearchQueryCard> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  bool _processing = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.transcript ?? '');
    _focusNode = FocusNode();
  }

  @override
  void didUpdateWidget(covariant _SearchQueryCard old) {
    super.didUpdateWidget(old);
    if (old.transcript != widget.transcript &&
        widget.transcript != null &&
        widget.transcript != _controller.text) {
      _controller.text = widget.transcript!;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _submitText() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _processing) return;
    setState(() => _processing = true);
    try {
      final svc = ref.read(voiceToProfileServiceProvider);
      final profile = await svc.extractProfile(text);
      if (!mounted) return;
      ref.read(clientProfileProvider.notifier).update(profile);
      ref.invalidate(matchResultsProvider);

      // Si está en vista cliente, esta búsqueda crea un lead en el inbox de
      // María. Igual que voice_input_sheet — el flujo "ecosistema dual".
      final viewMode = ref.read(viewModeProvider);
      if (viewMode == ViewMode.client) {
        final shareSource = ref.read(shareLinkOriginProvider);
        // ignore: discarded_futures
        ref.read(leadsProvider.notifier).addFromVoice(
              profile: profile,
              source:
                  shareSource ? LeadSource.shareLink : LeadSource.organic,
            );
        if (mounted) {
          TopBanner.show(
            context,
            message: 'Tu búsqueda se envió a María. Te contactará pronto.',
            icon: Icons.send_rounded,
          );
        }
      }
      _focusNode.unfocus();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: HitoTokens.danger,
          content: Text(
            'Error procesando búsqueda: $e',
            style: GoogleFonts.geist(color: Colors.white),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  void _openVoiceInput() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const VoiceInputSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isAgent = widget.viewMode == ViewMode.agent;
    final hasContent = _controller.text.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 6, left: 4),
            child: Text(
              isAgent ? 'BÚSQUEDA DEL CLIENTE' : 'TU BÚSQUEDA',
              style: GoogleFonts.geist(
                fontSize: 10,
                letterSpacing: 1.0,
                fontWeight: FontWeight.w700,
                color: HitoTokens.ink4,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
            decoration: BoxDecoration(
              color: HitoTokens.paper,
              borderRadius: BorderRadius.circular(HitoTokens.rXl),
              border: Border.all(
                color: _focusNode.hasFocus
                    ? HitoTokens.teal
                    : HitoTokens.border,
                width: _focusNode.hasFocus ? 1.5 : 1,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(Icons.search, size: 18, color: HitoTokens.ink3),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    enabled: !_processing,
                    minLines: 1,
                    maxLines: 3,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _submitText(),
                    onChanged: (_) => setState(() {}),
                    style: GoogleFonts.geist(
                      fontSize: 13,
                      color: HitoTokens.ink1,
                      height: 1.5,
                    ),
                    decoration: InputDecoration(
                      hintText:
                          'Describe lo que buscas — casa, depto, terreno, anticrético...',
                      hintStyle: GoogleFonts.geist(
                        fontSize: 13,
                        color: HitoTokens.ink4,
                        fontStyle: FontStyle.italic,
                      ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                if (hasContent && !_processing)
                  IconButton(
                    onPressed: _submitText,
                    tooltip: 'Buscar',
                    icon: Icon(Icons.arrow_forward_rounded,
                        size: 18, color: HitoTokens.teal),
                    style: IconButton.styleFrom(
                      backgroundColor: HitoTokens.teal.withAlpha(30),
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(HitoTokens.r2xl),
                      ),
                    ),
                  ),
                if (_processing)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                if (!hasContent && !_processing)
                  IconButton(
                    onPressed: _openVoiceInput,
                    tooltip: 'Buscar por voz',
                    icon: Icon(Icons.mic_rounded,
                        size: 18, color: Colors.white),
                    style: IconButton.styleFrom(
                      backgroundColor: HitoTokens.teal,
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(HitoTokens.r2xl),
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
                    ? (count > 0 ? 'Matches para tu cliente' : 'Listings')
                    : (count > 0 ? '$count propiedades' : 'Inventario'),
                style: hitoDisplay(
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
                    ? (count > 0
                        ? '$count propiedades · ordenadas por compat'
                        : 'Sin búsqueda activa — el cliente debe hablar')
                    : (count > 0
                        ? 'Ordenadas por compatibilidad'
                        : 'Aún sin búsqueda · toca el micrófono'),
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
        if (widget.matches.isEmpty) {
          return _EmptyMatchesCta(propertyCount: properties.length);
        }
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

/// Estado vacío para el lado izquierdo cuando no hay matches (profile null).
/// CTA visible: tap mic. Muestra count de propiedades disponibles en el mapa
/// para que el usuario sepa qué hay para explorar.
class _EmptyMatchesCta extends ConsumerWidget {
  final int propertyCount;
  const _EmptyMatchesCta({required this.propertyCount});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 0, 28, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(
              Icons.mic_none_rounded,
              size: 56,
              color: HitoTokens.teal,
            ),
            const SizedBox(height: 12),
            Text(
              'Cuéntanos lo que buscas',
              textAlign: TextAlign.center,
              style: hitoDisplay(
                fontSize: 22,
                color: HitoTokens.ink1,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Toca el micrófono y describe la casa que necesitas. '
              'La IA escucha, estructura tu perfil, y rankea las '
              '$propertyCount propiedades disponibles.',
              textAlign: TextAlign.center,
              style: GoogleFonts.geist(
                fontSize: 12.5,
                color: HitoTokens.ink3,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: () {
                showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  showDragHandle: true,
                  builder: (_) => const VoiceInputSheet(),
                );
              },
              style: FilledButton.styleFrom(
                backgroundColor: HitoTokens.teal,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              icon: const Icon(Icons.mic_rounded, size: 18),
              label: Text(
                'Iniciar búsqueda por voz',
                style: GoogleFonts.geist(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'O explora las propiedades directamente en el mapa →',
              textAlign: TextAlign.center,
              style: GoogleFonts.geist(
                fontSize: 11,
                color: HitoTokens.ink4,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
