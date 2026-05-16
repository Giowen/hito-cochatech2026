import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers.dart';
import '../theme.dart';

/// RoleSelectorScreen — entry point sin fricción (no auth, no signup).
/// Phase B.2: dos botones grandes para entrar como María (agente) o Juan (cliente).
/// La selección setea viewModeProvider global + confirma hasSelectedRoleProvider →
/// MaterialApp swap automático a MatchesScreen.
class RoleSelectorScreen extends ConsumerWidget {
  const RoleSelectorScreen({super.key});

  void _select(BuildContext context, WidgetRef ref, ViewMode mode) {
    ref.read(viewModeProvider.notifier).set(mode);
    ref.read(hasSelectedRoleProvider.notifier).confirm();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: HitoTokens.bone,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 24),
                  _BrandHeader(),
                  const SizedBox(height: 48),
                  Text(
                    '¿Cómo quieres entrar?',
                    style: GoogleFonts.instrumentSerif(
                      fontSize: 32,
                      color: HitoTokens.ink2,
                      height: 1.1,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Sin signup, sin fricción. Elige el rol con el que quieres probar Hito.',
                    style: GoogleFonts.geist(
                      fontSize: 13,
                      color: HitoTokens.ink3,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final narrow = constraints.maxWidth < 560;
                      final card1 = _RoleCard(
                        avatar: 'M',
                        avatarColor: HitoTokens.teal,
                        roleLabel: 'AGENTE INMOBILIARIO',
                        name: 'María',
                        description:
                            'Gestiona tus listings, califica leads en 60 segundos, revisa contratos con AI.',
                        bullets: const [
                          'Crear y editar propiedades',
                          'Ver clientes con matchscoring',
                          'Auditar contratos con tu copiloto legal',
                        ],
                        onTap: () => _select(context, ref, ViewMode.agent),
                      );
                      final card2 = _RoleCard(
                        avatar: 'J',
                        avatarColor: HitoTokens.navy,
                        roleLabel: 'CLIENTE FAMILIAR',
                        name: 'Juan',
                        description:
                            'Busca casa con criterios reales, valuación dinámica con TC paralelo, due diligence sin abogado.',
                        bullets: const [
                          'Búsqueda por voz natural',
                          'Comparables vendidos en tu zona',
                          'Alertas de gravamen en contratos',
                        ],
                        onTap: () => _select(context, ref, ViewMode.client),
                      );
                      if (narrow) {
                        return Column(
                          children: [
                            card1,
                            const SizedBox(height: 14),
                            card2,
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: card1),
                          const SizedBox(width: 16),
                          Expanded(child: card2),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 28),
                  Text(
                    'Puedes cambiar de rol en cualquier momento desde el toggle del top bar.',
                    style: GoogleFonts.geist(
                      fontSize: 11,
                      color: HitoTokens.ink4,
                      fontStyle: FontStyle.italic,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BrandHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 56,
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: HitoTokens.teal,
            borderRadius: BorderRadius.circular(HitoTokens.rMd),
          ),
          child: const Icon(Icons.home_outlined, color: Colors.white, size: 30),
        ),
        const SizedBox(height: 20),
        Text(
          'Hito',
          style: GoogleFonts.instrumentSerif(
            fontSize: 72,
            color: HitoTokens.ink1,
            height: 1.0,
            letterSpacing: -1,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'INTELIGENCIA INMOBILIARIA',
          style: GoogleFonts.geist(
            fontSize: 12,
            letterSpacing: 5,
            color: HitoTokens.ink3,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _RoleCard extends StatefulWidget {
  final String avatar;
  final Color avatarColor;
  final String roleLabel;
  final String name;
  final String description;
  final List<String> bullets;
  final VoidCallback onTap;

  const _RoleCard({
    required this.avatar,
    required this.avatarColor,
    required this.roleLabel,
    required this.name,
    required this.description,
    required this.bullets,
    required this.onTap,
  });

  @override
  State<_RoleCard> createState() => _RoleCardState();
}

class _RoleCardState extends State<_RoleCard> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      cursor: SystemMouseCursors.click,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(HitoTokens.rLg),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: HitoTokens.paper,
              borderRadius: BorderRadius.circular(HitoTokens.rLg),
              border: Border.all(
                color: _hovering ? widget.avatarColor : HitoTokens.border,
                width: _hovering ? 2 : 1,
              ),
              boxShadow: _hovering
                  ? [
                      BoxShadow(
                        color: widget.avatarColor.withAlpha(40),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: widget.avatarColor,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    widget.avatar,
                    style: GoogleFonts.geist(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  widget.roleLabel,
                  style: GoogleFonts.geist(
                    fontSize: 10,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w700,
                    color: HitoTokens.ink4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.name,
                  style: GoogleFonts.instrumentSerif(
                    fontSize: 40,
                    color: HitoTokens.ink1,
                    height: 1.0,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  widget.description,
                  style: GoogleFonts.geist(
                    fontSize: 13,
                    color: HitoTokens.ink2,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 14),
                for (final b in widget.bullets) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.check_rounded,
                        size: 14,
                        color: widget.avatarColor,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          b,
                          style: GoogleFonts.geist(
                            fontSize: 12,
                            color: HitoTokens.ink3,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                ],
                const SizedBox(height: 14),
                Row(
                  children: [
                    Text(
                      'Entrar como ${widget.name}',
                      style: GoogleFonts.geist(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: widget.avatarColor,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      Icons.arrow_forward_rounded,
                      size: 16,
                      color: widget.avatarColor,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
