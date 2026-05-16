import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers.dart';
import '../theme.dart';

/// Sidebar 240px — branding + flujos principales nav + agente footer.
/// Spec: Design/screenshots/v8.png + Design/screenshots/matchmaking-v2.png.
class HitoSidebar extends ConsumerWidget {
  static const double width = 240;

  const HitoSidebar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeFlow = ref.watch(activeFlowProvider);
    return Container(
      width: width,
      color: HitoTokens.bone,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _LogoHeader(),
          const SizedBox(height: 16),
          const _SectionLabel(label: 'FLUJOS PRINCIPALES'),
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
            onTap: () =>
                ref.read(activeFlowProvider.notifier).set(HitoFlow.valuacion),
          ),
          _NavItem(
            icon: Icons.shield_outlined,
            label: 'Copiloto Legal',
            badge: '1',
            selected: activeFlow == HitoFlow.copilotoLegal,
            onTap: () =>
                ref.read(activeFlowProvider.notifier).set(HitoFlow.copilotoLegal),
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

class _LogoHeader extends StatelessWidget {
  const _LogoHeader();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: HitoTokens.teal,
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
                  style: GoogleFonts.instrumentSerif(
                    fontSize: 26,
                    color: HitoTokens.ink1,
                    height: 1.0,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'INTELIGENCIA\nINMOBILIARIA',
                  style: GoogleFonts.geist(
                    fontSize: 9,
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w500,
                    color: HitoTokens.ink3,
                    height: 1.3,
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

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 16, 6),
      child: Text(
        label,
        style: GoogleFonts.geist(
          fontSize: 10,
          letterSpacing: 1.2,
          fontWeight: FontWeight.w600,
          color: HitoTokens.ink4,
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? count;
  final String? badge;
  final bool selected;
  final bool disabled;
  final VoidCallback? onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    this.count,
    this.badge,
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
                if (badge != null)
                  Container(
                    width: 18,
                    height: 18,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: HitoTokens.danger,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      badge!,
                      style: GoogleFonts.geist(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: HitoTokens.paper2,
        borderRadius: BorderRadius.circular(HitoTokens.rMd),
        border: Border.all(color: HitoTokens.border),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: HitoTokens.teal,
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
                    fontWeight: FontWeight.w600,
                    color: HitoTokens.ink1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Agente · Plan Pro',
                  style: GoogleFonts.geist(
                    fontSize: 11,
                    color: HitoTokens.ink3,
                  ),
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
    );
  }
}
