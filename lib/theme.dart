import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Hito Design System tokens (light).
/// Source of truth: `Design/index.html` :root CSS variables.
/// Spec del claude-design — premium proptech editorial style.
class HitoTokens {
  HitoTokens._();

  // ── Surfaces ──────────────────────────────────────────────
  /// Scaffold background. Cream warm off-white.
  static const bone = Color(0xFFFAF9F5);

  /// Cards, panels, raised surfaces.
  static const paper = Color(0xFFFFFFFF);

  /// Subtle background tier (search input, chips).
  static const paper2 = Color(0xFFF4F1EA);

  /// Deeper tier (selected/hovered subtle).
  static const paper3 = Color(0xFFECE7DC);

  /// Standard border.
  static const border = Color(0xFFE6E1D4);

  /// Emphasized border (input focus, divider).
  static const borderStrong = Color(0xFFC9C1AD);

  // ── Text scale ────────────────────────────────────────────
  /// Headings, primary text.
  static const ink1 = Color(0xFF0D1B2A);

  /// Body text.
  static const ink2 = Color(0xFF2C3E50);

  /// Secondary text, captions.
  static const ink3 = Color(0xFF5B6571);

  /// Muted, placeholders, disabled.
  static const ink4 = Color(0xFF8B8F95);

  /// Subtle dividers, very disabled.
  static const ink5 = Color(0xFFB4B6B9);

  // ── Brand ─────────────────────────────────────────────────
  static const navy = Color(0xFF0D2C54);
  static const navy2 = Color(0xFF081D3A);
  static const navy3 = Color(0xFF1A4480);

  /// Primary accent — teal. Logo, selected nav, compatibility badges.
  static const teal = Color(0xFF0A7C70);
  static const teal2 = Color(0xFF086D62);

  static const gold = Color(0xFFB8893D);
  static const gold2 = Color(0xFF97712F);

  // ── Semantic ──────────────────────────────────────────────
  static const success = Color(0xFF15803D);
  static const successBg = Color(0xFFECFDF3);
  static const warning = Color(0xFFC2790A);
  static const warningBg = Color(0xFFFEF7E6);
  static const danger = Color(0xFFB42318);
  static const dangerBg = Color(0xFFFEF2F2);
  static const info = Color(0xFF0A558C);
  static const infoBg = Color(0xFFEFF7FC);

  // ── Compatibility scale ───────────────────────────────────
  // Drives compatibility badges en property cards y map markers.
  static const comp95 = Color(0xFF0A7C70); // deep teal — 85+
  static const comp80 = Color(0xFF4A9D57); // green — 70+
  static const comp65 = Color(0xFFB8893D); // gold — 55+
  static const comp50 = Color(0xFFC2790A); // amber — 40+
  static const comp35 = Color(0xFFB42318); // red — <40

  // ── Radii ─────────────────────────────────────────────────
  static const rXs = 4.0;
  static const rSm = 6.0;
  static const rMd = 10.0;
  static const rLg = 14.0;
  static const rXl = 18.0;
  static const r2xl = 24.0;

  // ── Spacing scale (8/16/24 grid) ──────────────────────────
  static const s1 = 4.0;
  static const s2 = 8.0;
  static const s3 = 12.0;
  static const s4 = 16.0;
  static const s5 = 24.0;
  static const s6 = 32.0;
  static const s7 = 48.0;
}

/// Hito Design System tokens (dark mode). Same semantic structure as light.
class HitoTokensDark {
  HitoTokensDark._();

  static const bone = Color(0xFF0B1118);
  static const paper = Color(0xFF131A23);
  static const paper2 = Color(0xFF1B232D);
  static const paper3 = Color(0xFF232D39);
  static const border = Color(0xFF2A3543);
  static const borderStrong = Color(0xFF384556);

  static const ink1 = Color(0xFFF3F0E6);
  static const ink2 = Color(0xFFD8D3C3);
  static const ink3 = Color(0xFFA5ACB6);
  static const ink4 = Color(0xFF7A8290);
  static const ink5 = Color(0xFF525A66);

  static const navy = Color(0xFF6BA4E8);
  static const navy2 = Color(0xFF88B8EC);
  static const navy3 = Color(0xFF95C2F2);

  static const teal = Color(0xFF4EC9B8);
  static const teal2 = Color(0xFF6DD6C5);

  static const gold = Color(0xFFD4A564);
  static const gold2 = Color(0xFFE1B377);

  static const success = Color(0xFF4ADE80);
  static const warning = Color(0xFFF59E0B);
  static const danger = Color(0xFFF87171);
  static const info = Color(0xFF60A5FA);

  static const comp95 = Color(0xFF4EC9B8);
  static const comp80 = Color(0xFF7ED580);
  static const comp65 = Color(0xFFD4A564);
  static const comp50 = Color(0xFFF59E0B);
  static const comp35 = Color(0xFFF87171);
}

/// Map a 0-100 compatibility score to its design-system color (light mode).
Color compatibilityColor(int score, {Brightness brightness = Brightness.light}) {
  final isDark = brightness == Brightness.dark;
  if (score >= 85) return isDark ? HitoTokensDark.comp95 : HitoTokens.comp95;
  if (score >= 70) return isDark ? HitoTokensDark.comp80 : HitoTokens.comp80;
  if (score >= 55) return isDark ? HitoTokensDark.comp65 : HitoTokens.comp65;
  if (score >= 40) return isDark ? HitoTokensDark.comp50 : HitoTokens.comp50;
  return isDark ? HitoTokensDark.comp35 : HitoTokens.comp35;
}

/// Compatibility legend label for a 0-100 score (e.g. "85+", "70+", ...).
String compatibilityLabel(int score) {
  if (score >= 85) return '85+';
  if (score >= 70) return '70+';
  if (score >= 55) return '55+';
  if (score >= 40) return '40+';
  return '<40';
}

/// Builds the textTheme using Geist (body) + Instrument Serif (display).
/// Both fonts via google_fonts package — runtime cached for offline use post-first-load.
TextTheme _buildHitoTextTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final inkColor = isDark ? HitoTokensDark.ink1 : HitoTokens.ink1;
  final ink3Color = isDark ? HitoTokensDark.ink3 : HitoTokens.ink3;

  TextStyle display(double size, {double letterSpacing = -0.01, double height = 1.1}) =>
      GoogleFonts.instrumentSerif(
        fontSize: size,
        color: inkColor,
        letterSpacing: letterSpacing,
        height: height,
      );

  TextStyle body(
    double size, {
    FontWeight weight = FontWeight.w400,
    Color? color,
    double height = 1.5,
    double letterSpacing = 0,
  }) =>
      GoogleFonts.geist(
        fontSize: size,
        fontWeight: weight,
        color: color ?? inkColor,
        height: height,
        letterSpacing: letterSpacing,
      );

  return TextTheme(
    displayLarge: display(56),
    displayMedium: display(44),
    displaySmall: display(32),
    headlineLarge: display(28),
    headlineMedium: display(24),
    headlineSmall: display(20),
    titleLarge: body(18, weight: FontWeight.w600, height: 1.3),
    titleMedium: body(15, weight: FontWeight.w600, height: 1.3),
    titleSmall: body(13, weight: FontWeight.w600, height: 1.3),
    bodyLarge: body(15),
    bodyMedium: body(14),
    bodySmall: body(12, color: ink3Color),
    labelLarge: body(13, weight: FontWeight.w500, height: 1.2),
    labelMedium: body(11, weight: FontWeight.w500, height: 1.2),
    labelSmall: body(10, weight: FontWeight.w500, color: ink3Color, letterSpacing: 0.5),
  );
}

/// Build the Hito ThemeData for [brightness] (light by default).
/// Aplica design tokens, Geist + Instrument Serif fonts via google_fonts,
/// y component themes para cards, buttons, chips, inputs.
ThemeData buildHitoTheme({Brightness brightness = Brightness.light}) {
  final isDark = brightness == Brightness.dark;

  final colorScheme = ColorScheme(
    brightness: brightness,
    primary: isDark ? HitoTokensDark.teal : HitoTokens.teal,
    onPrimary: Colors.white,
    primaryContainer: isDark ? HitoTokensDark.paper3 : const Color(0xFFD7F0EA),
    onPrimaryContainer: isDark ? HitoTokensDark.teal2 : HitoTokens.teal2,
    secondary: isDark ? HitoTokensDark.navy : HitoTokens.navy,
    onSecondary: Colors.white,
    secondaryContainer: isDark ? HitoTokensDark.paper2 : HitoTokens.paper2,
    onSecondaryContainer: isDark ? HitoTokensDark.ink2 : HitoTokens.ink2,
    tertiary: isDark ? HitoTokensDark.gold : HitoTokens.gold,
    onTertiary: Colors.white,
    error: isDark ? HitoTokensDark.danger : HitoTokens.danger,
    onError: Colors.white,
    errorContainer: isDark
        ? const Color(0xFF3C1B1B)
        : HitoTokens.dangerBg,
    onErrorContainer: isDark ? HitoTokensDark.danger : HitoTokens.danger,
    surface: isDark ? HitoTokensDark.paper : HitoTokens.paper,
    onSurface: isDark ? HitoTokensDark.ink1 : HitoTokens.ink1,
    onSurfaceVariant: isDark ? HitoTokensDark.ink3 : HitoTokens.ink3,
    surfaceContainerLowest: isDark ? HitoTokensDark.bone : HitoTokens.bone,
    surfaceContainerLow: isDark ? HitoTokensDark.paper : HitoTokens.paper,
    surfaceContainer: isDark ? HitoTokensDark.paper2 : HitoTokens.paper2,
    surfaceContainerHigh: isDark ? HitoTokensDark.paper3 : HitoTokens.paper3,
    surfaceContainerHighest: isDark ? HitoTokensDark.paper3 : HitoTokens.paper3,
    outline: isDark ? HitoTokensDark.border : HitoTokens.border,
    outlineVariant: isDark ? HitoTokensDark.borderStrong : HitoTokens.borderStrong,
    shadow: const Color(0xFF0D1B2A),
  );

  final textTheme = _buildHitoTextTheme(brightness);

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: isDark ? HitoTokensDark.bone : HitoTokens.bone,
    canvasColor: isDark ? HitoTokensDark.bone : HitoTokens.bone,
    textTheme: textTheme,
    fontFamily: GoogleFonts.geist().fontFamily,
    appBarTheme: AppBarTheme(
      backgroundColor: isDark ? HitoTokensDark.bone : HitoTokens.bone,
      foregroundColor: isDark ? HitoTokensDark.ink1 : HitoTokens.ink1,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleTextStyle: GoogleFonts.geist(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: isDark ? HitoTokensDark.ink1 : HitoTokens.ink1,
      ),
      iconTheme: IconThemeData(
        color: isDark ? HitoTokensDark.ink2 : HitoTokens.ink2,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: isDark ? HitoTokensDark.paper : HitoTokens.paper,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(HitoTokens.rLg),
        side: BorderSide(
          color: isDark ? HitoTokensDark.border : HitoTokens.border,
          width: 1,
        ),
      ),
      margin: EdgeInsets.zero,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: isDark ? HitoTokensDark.teal : HitoTokens.teal,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(HitoTokens.rMd),
        ),
        textStyle: GoogleFonts.geist(
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        elevation: 0,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: isDark ? HitoTokensDark.ink1 : HitoTokens.ink1,
        side: BorderSide(
          color: isDark ? HitoTokensDark.border : HitoTokens.border,
          width: 1,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(HitoTokens.rMd),
        ),
        textStyle: GoogleFonts.geist(
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: isDark ? HitoTokensDark.teal : HitoTokens.teal,
        textStyle: GoogleFonts.geist(
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: isDark ? HitoTokensDark.paper2 : HitoTokens.paper2,
      side: BorderSide.none,
      labelStyle: GoogleFonts.geist(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        color: isDark ? HitoTokensDark.ink2 : HitoTokens.ink2,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(HitoTokens.rMd),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: isDark ? HitoTokensDark.paper : HitoTokens.paper,
      hintStyle: GoogleFonts.geist(
        color: isDark ? HitoTokensDark.ink4 : HitoTokens.ink4,
        fontSize: 14,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(HitoTokens.rXl),
        borderSide: BorderSide(
          color: isDark ? HitoTokensDark.border : HitoTokens.border,
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(HitoTokens.rXl),
        borderSide: BorderSide(
          color: isDark ? HitoTokensDark.border : HitoTokens.border,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(HitoTokens.rXl),
        borderSide: BorderSide(
          color: isDark ? HitoTokensDark.teal : HitoTokens.teal,
          width: 1.5,
        ),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: isDark ? HitoTokensDark.border : HitoTokens.border,
      thickness: 1,
      space: 0,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: isDark ? HitoTokensDark.paper : HitoTokens.paper,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(HitoTokens.rXl),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: isDark ? HitoTokensDark.paper : HitoTokens.paper,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(HitoTokens.rXl),
        ),
      ),
      modalBackgroundColor: isDark ? HitoTokensDark.paper : HitoTokens.paper,
      dragHandleColor: isDark ? HitoTokensDark.borderStrong : HitoTokens.borderStrong,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: isDark ? HitoTokensDark.teal : HitoTokens.teal,
      linearTrackColor: isDark ? HitoTokensDark.paper2 : HitoTokens.paper2,
      circularTrackColor: isDark ? HitoTokensDark.paper2 : HitoTokens.paper2,
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
      },
    ),
  );
}

/// Convenience: light theme builder (used by main.dart).
ThemeData buildHitoLightTheme() => buildHitoTheme(brightness: Brightness.light);

/// Convenience: dark theme builder (specced, swap in via MaterialApp.darkTheme).
ThemeData buildHitoDarkTheme() => buildHitoTheme(brightness: Brightness.dark);
