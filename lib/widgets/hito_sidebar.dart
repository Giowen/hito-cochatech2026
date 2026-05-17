import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers.dart';
import '../screens/contract_analysis_screen.dart';
import '../screens/leads_inbox_screen.dart';
import '../theme.dart';
import 'valuation_sheet.dart';

/// Sidebar 240px — branding + flujos principales nav + agente footer.
/// Spec: Design/screenshots/v8.png + Design/screenshots/matchmaking-v2.png.
class HitoSidebar extends ConsumerWidget {
  static const double width = 240;

  const HitoSidebar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeFlow = ref.watch(activeFlowProvider);
    final viewMode = ref.watch(viewModeProvider);
    final pendingLeads = ref.watch(pendingLeadsCountProvider);
    final isAgent = viewMode == ViewMode.agent;
    return Container(
      width: width,
      color: HitoTokens.bone,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _LogoHeader(),
          const SizedBox(height: 16),
          const _SectionLabel(label: 'FLUJOS PRINCIPALES'),
          if (isAgent)
            _NavItem(
              icon: Icons.inbox_rounded,
              label: 'Mis leads',
              count: pendingLeads > 0 ? '$pendingLeads' : null,
              selected: activeFlow == HitoFlow.leads,
              onTap: () {
                ref.read(activeFlowProvider.notifier).set(HitoFlow.leads);
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const LeadsInboxScreen(),
                  ),
                );
              },
            ),
          _NavItem(
            icon: Icons.search_rounded,
            label: 'Matchmaking',
            count: '12',
            selected: activeFlow == HitoFlow.matchmaking,
            onTap: () =>
                ref.read(activeFlowProvider.notifier).set(HitoFlow.matchmaking),
          ),
          _NavItem(
            icon: Icons.trending_up_rounded,
            label: 'Valuación',
            selected: activeFlow == HitoFlow.valuacion,
            onTap: () {
              ref.read(activeFlowProvider.notifier).set(HitoFlow.valuacion);
              final propertyId = _topMatchPropertyId(ref);
              if (propertyId == null) {
                _showNoSelectionSnack(
                  context,
                  'Seleccioná una propiedad primero — del mapa o de la lista.',
                );
                return;
              }
              showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                showDragHandle: true,
                builder: (_) => ValuationSheet(propertyId: propertyId),
              );
            },
          ),
          _NavItem(
            icon: Icons.shield_outlined,
            label: 'Copiloto Legal',
            selected: activeFlow == HitoFlow.copilotoLegal,
            onTap: () {
              ref.read(activeFlowProvider.notifier)
                  .set(HitoFlow.copilotoLegal);
              final propertyId = _topMatchPropertyId(ref);
              if (propertyId == null) {
                _showNoSelectionSnack(
                  context,
                  'Seleccioná una propiedad primero — del mapa o de la lista.',
                );
                return;
              }
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      ContractAnalysisScreen(propertyId: propertyId),
                ),
              );
            },
          ),
          const SizedBox(height: 18),
          const _SectionLabel(label: 'PRÓXIMAMENTE'),
          const _NavItem(
            icon: Icons.person_outline_rounded,
            label: 'Mi CRM',
            disabled: true,
          ),
          const _NavItem(
            icon: Icons.description_outlined,
            label: 'Documentos',
            disabled: true,
          ),
          const _NavItem(
            icon: Icons.calendar_today_outlined,
            label: 'Agenda',
            disabled: true,
          ),
          const Spacer(),
          const _AgentFooter(),
        ],
      ),
    );
  }
}

/// Devuelve el property_id del top match (mejor compatibility) o null si no hay.
/// Si selectedPropertyIdProvider tiene algo, prioriza esa selección — útil cuando
/// el usuario ya clickó una card y luego va a Valuación / Copiloto Legal.
String? _topMatchPropertyId(WidgetRef ref) {
  final selected = ref.read(selectedPropertyIdProvider);
  if (selected != null) return selected;
  final matches = ref.read(matchResultsProvider).value;
  if (matches == null || matches.isEmpty) return null;
  return matches.first.propertyId;
}

/// SnackBar consistente para flujos que requieren una propiedad seleccionada.
void _showNoSelectionSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      backgroundColor: HitoTokens.ink2,
      duration: const Duration(seconds: 3),
      content: Text(
        message,
        style: GoogleFonts.geist(color: Colors.white),
      ),
    ),
  );
}

class _LogoHeader extends StatelessWidget {
  const _LogoHeader();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 6),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        decoration: BoxDecoration(
          // Background OSCURO (ink1 navy) sobre el bone cream del sidebar —
          // contraste real, no white-sobre-white. Da peso editorial al
          // header de marca.
          color: HitoTokens.ink1,
          borderRadius: BorderRadius.circular(HitoTokens.rMd),
          boxShadow: const [
            BoxShadow(
              color: Color.fromRGBO(13, 27, 42, 0.18),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [HitoTokens.teal, HitoTokens.teal2],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(HitoTokens.rSm),
              ),
              child: const Icon(
                Icons.home_outlined,
                color: Colors.white,
                size: 22,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Hito',
                    style: hitoDisplay(
                      fontSize: 28,
                      color: HitoTokens.bone, // cream sobre navy
                      height: 1.0,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'INTELIGENCIA\nINMOBILIARIA',
                    style: GoogleFonts.geist(
                      fontSize: 9,
                      letterSpacing: 1.4,
                      fontWeight: FontWeight.w600,
                      // Teal claro como accent para el subtítulo.
                      color: const Color(0xFF7FCBC1),
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 16, 6),
      child: Row(
        children: [
          // Accent bar — da peso visual sin meter background completo.
          Container(
            width: 3,
            height: 12,
            decoration: BoxDecoration(
              color: HitoTokens.teal,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.geist(
                fontSize: 10,
                letterSpacing: 1.3,
                fontWeight: FontWeight.w700,
                color: HitoTokens.ink3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? count;
  final bool selected;
  final bool disabled;
  final VoidCallback? onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    this.count,
    this.selected = false,
    this.disabled = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final foregroundColor = disabled
        ? HitoTokens.ink4
        : (selected ? Colors.white : HitoTokens.ink2);
    final bgColor = selected ? HitoTokens.navy2 : Colors.transparent;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: disabled ? null : onTap,
          borderRadius: BorderRadius.circular(HitoTokens.rMd),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(HitoTokens.rMd),
            ),
            child: Row(
              children: [
                Icon(icon, size: 18, color: foregroundColor),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    style: GoogleFonts.geist(
                      fontSize: 14,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: foregroundColor,
                    ),
                  ),
                ),
                if (count != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: selected
                          ? Colors.white.withAlpha(40)
                          : HitoTokens.paper3,
                      borderRadius: BorderRadius.circular(HitoTokens.rSm),
                    ),
                    child: Text(
                      count!,
                      style: GoogleFonts.geist(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: selected ? Colors.white : HitoTokens.ink2,
                      ),
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

class _AgentFooter extends StatelessWidget {
  const _AgentFooter();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        // paper3 (#ECE7DC) es notoriamente más oscuro que el bone (#FAF9F5)
        // del sidebar — contraste real. Antes usaba paper (FFFFFF) que sobre
        // bone se veía igual.
        color: HitoTokens.paper3,
        borderRadius: BorderRadius.circular(HitoTokens.rMd),
        border: Border.all(color: HitoTokens.borderStrong),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [HitoTokens.teal, HitoTokens.teal2],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
              ),
              child: Text(
                'MQ',
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'María Quiroga',
                    style: GoogleFonts.geist(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: HitoTokens.ink1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: HitoTokens.teal.withAlpha(28),
                          borderRadius:
                              BorderRadius.circular(HitoTokens.rXs),
                        ),
                        child: Text(
                          'PRO',
                          style: GoogleFonts.geist(
                            fontSize: 9,
                            letterSpacing: 0.4,
                            fontWeight: FontWeight.w700,
                            color: HitoTokens.teal2,
                          ),
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'Agente',
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
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: HitoTokens.ink4,
            ),
          ],
        ),
      ),
    );
  }
}
