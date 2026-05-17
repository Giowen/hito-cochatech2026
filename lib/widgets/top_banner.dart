import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme.dart';

/// Notificación in-app que aparece **arriba** del contenido con slide
/// animation. Reemplaza al SnackBar (que va abajo y se oculta detrás de
/// bottom sheets / drawer) para notificaciones críticas tipo
/// "Lead enviado a María" que el usuario tiene que ver sí o sí.
///
/// **Implementación**: Overlay positioned top-center con padding del SafeArea.
/// Auto-dismiss a los `duration` segundos. Tap para cerrar manualmente.
class TopBanner {
  static OverlayEntry? _current;

  /// Muestra la notificación. Si ya hay una visible, la reemplaza (no stack).
  ///
  /// **Cómo resuelve el Overlay**: `Navigator.of(context, rootNavigator: true)
  /// .overlay` retorna el OverlayState del Navigator raíz directo. Es más
  /// confiable que `Overlay.maybeOf(context)` porque el último busca hacia
  /// arriba desde `context` y puede fallar si `context` está fuera del
  /// subtree del Overlay (ej. cuando se pasa un context del Navigator que
  /// vive ABOVE el Overlay).
  static void show(
    BuildContext context, {
    required String message,
    Duration duration = const Duration(seconds: 3),
    Color background = const Color(0xFF086D62), // teal2
    IconData icon = Icons.check_circle_rounded,
  }) {
    OverlayState? overlay;
    // Intentar primero el Overlay del root Navigator (más estable cuando
    // el caller acaba de hacer Navigator.pop).
    final navState = Navigator.maybeOf(context, rootNavigator: true);
    overlay = navState?.overlay ?? Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) {
      // Last-resort log para que se vea en debug si llega a fallar.
      // ignore: avoid_print
      print('[TopBanner] no overlay available, skipping banner: "$message"');
      return;
    }

    // Si hay una notificación previa, la quitamos antes de mostrar la nueva.
    _current?.remove();

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _TopBannerWidget(
        message: message,
        background: background,
        icon: icon,
        onDismiss: () {
          if (_current == entry) _current = null;
          if (entry.mounted) entry.remove();
        },
      ),
    );
    _current = entry;
    overlay.insert(entry);

    Future.delayed(duration, () {
      if (_current == entry && entry.mounted) {
        entry.remove();
        _current = null;
      }
    });
  }
}

class _TopBannerWidget extends StatefulWidget {
  final String message;
  final Color background;
  final IconData icon;
  final VoidCallback onDismiss;

  const _TopBannerWidget({
    required this.message,
    required this.background,
    required this.icon,
    required this.onDismiss,
  });

  @override
  State<_TopBannerWidget> createState() => _TopBannerWidgetState();
}

class _TopBannerWidgetState extends State<_TopBannerWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<Offset> _slide;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, -1.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _dismiss() async {
    if (_ctrl.isDismissed) return widget.onDismiss();
    await _ctrl.reverse();
    widget.onDismiss();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: SlideTransition(
            position: _slide,
            child: FadeTransition(
              opacity: _fade,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Material(
                  color: widget.background,
                  borderRadius: BorderRadius.circular(HitoTokens.r2xl),
                  elevation: 8,
                  shadowColor: Colors.black.withAlpha(60),
                  child: InkWell(
                    onTap: _dismiss,
                    borderRadius: BorderRadius.circular(HitoTokens.r2xl),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 14),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(widget.icon, color: Colors.white, size: 20),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Text(
                              widget.message,
                              style: GoogleFonts.geist(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
