import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers.dart';
import '../theme.dart';

/// Top bar global — ubicación + mercado activo + vista María/Juan + actions.
/// Vista global afecta todos los flows (matchmaking/valuación/copiloto legal).
class HitoTopBar extends ConsumerWidget {
  const HitoTopBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewMode = ref.watch(viewModeProvider);
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: HitoTokens.bone,
        border: Border(bottom: BorderSide(color: HitoTokens.border)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Responsive: en pantallas estrechas (<600px del panel main), ocultamos
          // el location meta y el dark mode icon para que el toggle María/Juan
          // y notificaciones siempre quepan sin overflow.
          final wide = constraints.maxWidth >= 600;
          return Row(
            children: [
              Icon(
                Icons.location_on_outlined,
                size: 16,
                color: HitoTokens.ink2,
              ),
              if (wide) ...[
                const SizedBox(width: 6),
                Text(
                  'Cochabamba',
                  style: GoogleFonts.geist(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: HitoTokens.ink1,
                  ),
                ),
                const SizedBox(width: 10),
                _MarketActivePill(),
              ],
              const Spacer(),
              _ViewToggle(viewMode: viewMode),
              const SizedBox(width: 8),
              if (wide)
                _IconAction(
                  icon: Icons.dark_mode_outlined,
                  tooltip: 'Modo oscuro (próximamente)',
                  onTap: () {},
                ),
              _IconAction(
                icon: Icons.notifications_none_rounded,
                tooltip: 'Notificaciones',
                badge: true,
                onTap: () {},
              ),
            ],
          );
        },
      ),
    );
  }
}

class _MarketActivePill extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: HitoTokens.successBg,
        borderRadius: BorderRadius.circular(HitoTokens.rXl),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: HitoTokens.success,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            'Mercado activo',
            style: GoogleFonts.geist(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: HitoTokens.success,
            ),
          ),
        ],
      ),
    );
  }
}

class _ViewToggle extends ConsumerWidget {
  final ViewMode viewMode;
  const _ViewToggle({required this.viewMode});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final agent = viewMode == ViewMode.agent;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: HitoTokens.paper2,
        borderRadius: BorderRadius.circular(HitoTokens.r2xl),
        border: Border.all(color: HitoTokens.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ToggleSide(
            avatar: 'M',
            label: 'María',
            active: agent,
            onTap: () =>
                ref.read(viewModeProvider.notifier).set(ViewMode.agent),
          ),
          _ToggleSide(
            avatar: 'J',
            label: 'Juan',
            active: !agent,
            onTap: () =>
                ref.read(viewModeProvider.notifier).set(ViewMode.client),
          ),
        ],
      ),
    );
  }
}

class _ToggleSide extends StatelessWidget {
  final String avatar;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _ToggleSide({
    required this.avatar,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(HitoTokens.rXl),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: active ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(HitoTokens.rXl),
            boxShadow: active
                ? const [
                    BoxShadow(
                      color: Color.fromRGBO(13, 27, 42, 0.06),
                      blurRadius: 4,
                      offset: Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: active ? HitoTokens.teal : HitoTokens.paper3,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  avatar,
                  style: GoogleFonts.geist(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: active ? Colors.white : HitoTokens.ink3,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.geist(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: active ? HitoTokens.ink1 : HitoTokens.ink3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IconAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool badge;
  final VoidCallback onTap;

  const _IconAction({
    required this.icon,
    required this.tooltip,
    this.badge = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(HitoTokens.r2xl),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              child: Icon(icon, size: 18, color: HitoTokens.ink2),
            ),
            if (badge)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: HitoTokens.danger,
                    shape: BoxShape.circle,
                    border: Border.all(color: HitoTokens.bone, width: 1.5),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
