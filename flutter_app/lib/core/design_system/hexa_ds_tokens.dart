import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/hexa_colors.dart';

/// Hexa reusable SaaS design tokens (8px grid, Plus Jakarta Sans, Harisree palette).
///
/// Use [HexaDsSpace], [HexaDsRadii], [HexaDsGradients], [HexaDsType], and [HexaGlassTheme] via
/// `context.hx` for surfaces and text that follow light/dark. [HexaDsColors] keeps shared brand accents.
abstract final class HexaDsColors {
  /// Light-mode defaults — aligned with Harisree [HexaColors] + [HexaGlassTheme].
  static const Color surfaceCanvas = Color(0xFFECEFF1);
  static const Color surfaceCard = Color(0xFFFFFFFF);
  static const Color inputFill = Color(0xFFFFFFFF);
  static const Color borderSubtle = HexaColors.inputBorderGrey;
  static const Color textPrimary = HexaColors.textOnLightSurface;
  static const Color textBody = HexaColors.textBody;
  static const Color textMuted = HexaColors.neutral;
  static const Color error = Color(0xFFDC2626);
  /// Borders / accents for valid input (meets contrast on light surfaces).
  static const Color success = Color(0xFF059669);
  static const Color successForeground = Color(0xFF065F46);
  static const Color successSurface = Color(0xFFECFDF5);
  static const Color indigo = Color(0xFF6366F1);
  static const Color blue = Color(0xFF2563EB);
  static const Color violet = Color(0xFF7C3AED);
}

/// Multiples of **8px** — prefer these over magic numbers.
abstract final class HexaDsSpace {
  /// 4px — hairline rhythm (half-step).
  static const double xs = 4;
  static const double s1 = 8;
  static const double s2 = 16;
  static const double s3 = 24;
  static const double s4 = 32;
  static const double s5 = 40;
  static const double s6 = 48;

  static double grid(int units) => 8.0 * units;
}

/// Horizontal page gutter + vertical rhythm for scroll pages and cards.
abstract final class HexaDsLayout {
  /// Screen edge inset for primary content (home, lists).
  static const double pageGutter = 24;
  /// Space between major stacked blocks (sections).
  static const double sectionGap = 24;
  /// Related groups (card internals, chip row to hero).
  static const double blockGap = 16;
  /// Tight vertical rhythm (chips, subtitles).
  static const double tightGap = 12;
  /// Inline / dense (icon to label).
  static const double inlineGap = 8;
}

/// Shared motion — subtle, fast; prefer ease curves over bounce.
abstract final class HexaDsMotion {
  static const Duration instant = Duration(milliseconds: 90);
  static const Duration fast = Duration(milliseconds: 180);
  static const Duration medium = Duration(milliseconds: 280);
  static const Duration slow = Duration(milliseconds: 420);
  static const Duration authPage = Duration(milliseconds: 400);
  static const Duration authPageReverse = Duration(milliseconds: 320);
  static const Duration pushPage = Duration(milliseconds: 180);
  static const Duration pushPageReverse = Duration(milliseconds: 150);

  static const Curve enter = Curves.easeOutCubic;
  static const Curve exit = Curves.easeInCubic;
}

/// Corner radii — minimum **12px** for SaaS surfaces.
abstract final class HexaDsRadii {
  static const double sm = 10;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;

  static BorderRadius get input => BorderRadius.circular(md);
  static BorderRadius get button => BorderRadius.circular(md);
  static BorderRadius get card => BorderRadius.circular(xl);
  static BorderRadius get fieldShell => BorderRadius.circular(lg);
}

abstract final class HexaDsShadows {
  static List<BoxShadow> get card => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.06),
          blurRadius: 32,
          offset: const Offset(0, 12),
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.03),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ];

  static List<BoxShadow> get inputRest => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.05),
          blurRadius: 10,
          offset: const Offset(0, 3),
        ),
      ];

  static List<BoxShadow> get inputFocus => [
        const BoxShadow(
          color: HexaColors.inputFocusRing,
          blurRadius: 0,
          spreadRadius: 3,
          offset: Offset.zero,
        ),
      ];
}

abstract final class HexaDsGradients {
  static const List<Color> primaryStops = [
    HexaColors.brandPrimary,
    HexaColors.brandAccent,
    Color(0xFF0E7669),
  ];

  static const LinearGradient primaryCta = LinearGradient(
    colors: primaryStops,
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    stops: [0.0, 0.48, 1.0],
  );
}

/// **Plus Jakarta Sans** — matches [buildHexaTheme] app typography.
abstract final class HexaDsType {
  static TextStyle heading(double size, {Color? color}) =>
      GoogleFonts.plusJakartaSans(
        fontSize: size,
        fontWeight: FontWeight.w700,
        color: color ?? HexaDsColors.textPrimary,
        height: 1.2,
      );

  static TextStyle body(double size, {Color? color, FontWeight? weight}) =>
      GoogleFonts.plusJakartaSans(
        fontSize: size,
        fontWeight: weight ?? FontWeight.w500,
        color: color ?? HexaDsColors.textBody,
        height: 1.45,
      );

  static TextStyle label(double size, {Color? color}) =>
      GoogleFonts.plusJakartaSans(
        fontSize: size,
        fontWeight: FontWeight.w600,
        color: color ?? HexaDsColors.textMuted,
        height: 1.35,
      );

  /// Section titles on dashboards / cards (T — small caps feel via weight).
  static TextStyle sectionTitle({Color? color}) =>
      GoogleFonts.plusJakartaSans(
        fontSize: 14,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.15,
        height: 1.25,
        color: color ?? HexaDsColors.textPrimary,
      );

  /// Overline / meta (uppercase optional at call site).
  static TextStyle overline({Color? color}) =>
      GoogleFonts.plusJakartaSans(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.35,
        height: 1.25,
        color: color ?? HexaDsColors.textMuted,
      );

  static TextStyle button({Color color = Colors.white}) =>
      GoogleFonts.plusJakartaSans(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: color,
        letterSpacing: 0.2,
      );
}
