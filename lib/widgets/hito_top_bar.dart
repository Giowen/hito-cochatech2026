import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers.dart';
import '../screens/add_property_screen.dart';
import '../theme.dart';

/// Top bar global — ubicación + mercado activo + vista María/Juan + actions.
/// Vista global afecta todos los flows (matchmaking/valuación/copiloto legal).
///
/// [onOpenDrawer] se pasa en layouts mobile/compact donde el sidebar vive en
/// un Drawer en vez de fijo. Cuando es null, no se renderiza el botón menu.
class HitoTopBar extends ConsumerWidget {
  final VoidCallback? onOpenDrawer;
  const HitoTopBar({super.key, this.onOpenDrawer});

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
              if (onOpenDrawer != null) ...[
                IconButton(
                  icon: Icon(Icons.menu_rounded, color: HitoTokens.ink2),
                  tooltip: 'Menú',
                  onPressed: onOpenDrawer,
                ),
                const SizedBox(width: 4),
              ],
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
              if (viewMode == ViewMode.agent) ...[
                _ShareLinkButton(compact: !wide),
                const SizedBox(width: 6),
                _NewPropertyButton(compact: !wide),
                const SizedBox(width: 8),
              ],
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

/// Botón "Mi link" — abre un modal con la URL pública que María comparte por
/// WhatsApp con sus clientes. Cualquier cliente que entre a esa URL es
/// taggeado con `LeadSource.shareLink` cuando crea un lead vía voice query.
///
/// **Por qué importa para el demo**: el desafío exige "ecosistema dual".
/// Sin un mecanismo de captura el ecosistema queda manco. Este botón es el
/// puente: María comparte el link, el cliente busca, el lead aparece en el
/// inbox de María con badge especial.
class _ShareLinkButton extends StatelessWidget {
  final bool compact;
  const _ShareLinkButton({required this.compact});

  static const _agentSlug = 'maria-quiroga';
  static const _baseUrl = 'https://hito.app/a/';

  void _openModal(BuildContext context) {
    final url = '$_baseUrl$_agentSlug';
    final waMsg = Uri.encodeComponent(
      'Hola! Soy María Quiroga, agente inmobiliaria. '
      'Te paso mi link para que me cuentes qué casa buscas — la AI ya '
      'estructura tu perfil y yo te respondo con opciones puntuales: $url',
    );
    final waUrl = 'https://wa.me/?text=$waMsg';

    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        insetPadding:
            const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        backgroundColor: HitoTokens.paper,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(HitoTokens.rLg),
        ),
        child: ConstrainedBox(
          // Antes era ancho default del Dialog (>600px). Esto lo deja
          // proporcional al contenido — typical card-like en lugar de hoja.
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: HitoTokens.teal,
                      borderRadius: BorderRadius.circular(HitoTokens.rMd),
                    ),
                    child: const Icon(Icons.link,
                        color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Tu link de captura',
                          style: hitoDisplay(
                            fontSize: 22,
                            color: HitoTokens.ink1,
                            height: 1.1,
                          ),
                        ),
                        Text(
                          'Cuando un cliente lo abre y hace su búsqueda, '
                          'aparece como lead en tu inbox.',
                          style: GoogleFonts.geist(
                            fontSize: 11.5,
                            color: HitoTokens.ink3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  color: HitoTokens.paper2,
                  borderRadius: BorderRadius.circular(HitoTokens.rMd),
                  border: Border.all(color: HitoTokens.border),
                ),
                child: SelectableText(
                  url,
                  style: GoogleFonts.geistMono(
                    fontSize: 12.5,
                    color: HitoTokens.ink1,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        // Copy real al clipboard + feedback.
                        await Clipboard.setData(ClipboardData(text: url));
                        if (!context.mounted) return;
                        Navigator.of(context).pop();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: HitoTokens.ink2,
                            duration: const Duration(seconds: 2),
                            content: Text(
                              'Link copiado al portapapeles',
                              style: GoogleFonts.geist(color: Colors.white),
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.copy_rounded, size: 16),
                      label: const Text('Copiar link'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () async {
                        // Abre WhatsApp Web/app en pestaña nueva con mensaje
                        // pre-armado para reenviar al cliente.
                        final ok = await launchUrl(
                          Uri.parse(waUrl),
                          mode: LaunchMode.externalApplication,
                        );
                        if (!context.mounted) return;
                        Navigator.of(context).pop();
                        if (!ok) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              backgroundColor: HitoTokens.danger,
                              content: Text(
                                'No se pudo abrir WhatsApp',
                                style: GoogleFonts.geist(color: Colors.white),
                              ),
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.chat_rounded, size: 16),
                      label: const Text('Compartir WhatsApp'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF25D366),
                      ),
                    ),
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

  @override
  Widget build(BuildContext context) {
    return Material(
      color: HitoTokens.paper,
      borderRadius: BorderRadius.circular(HitoTokens.r2xl),
      child: InkWell(
        borderRadius: BorderRadius.circular(HitoTokens.r2xl),
        onTap: () => _openModal(context),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 10 : 12,
            vertical: 7,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.link, size: 16, color: HitoTokens.teal),
              if (!compact) ...[
                const SizedBox(width: 4),
                Text(
                  'Mi link',
                  style: GoogleFonts.geist(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: HitoTokens.teal,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _NewPropertyButton extends StatelessWidget {
  final bool compact;
  const _NewPropertyButton({required this.compact});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: HitoTokens.teal,
      borderRadius: BorderRadius.circular(HitoTokens.r2xl),
      child: InkWell(
        borderRadius: BorderRadius.circular(HitoTokens.r2xl),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<bool>(
              builder: (_) => const AddPropertyScreen(),
              fullscreenDialog: true,
            ),
          );
        },
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 10 : 12,
            vertical: 7,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.add, size: 16, color: Colors.white),
              if (!compact) ...[
                const SizedBox(width: 4),
                Text(
                  'Nueva propiedad',
                  style: GoogleFonts.geist(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ],
            ],
          ),
        ),
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
