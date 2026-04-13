import 'package:flutter/material.dart';

/// Premium light UI — navy primary text, semantic profit/loss, blue accent only where needed.
abstract final class HexaColors {
  // === LIGHT SURFACES (production palette) ===
  static const surfaceApp = Color(0xFFFFFFFF);
  static const surfaceCardLight = Color(0xFFF8FAFC);
  static const neutral = Color(0xFF64748B);

  /// Headlines, app identity — not for full-screen fills of interactive blue.
  static const primaryNavy = Color(0xFF0F172A);

  /// Links, info, selected tab accent — use sparingly.
  static const accentInfo = Color(0xFF2563EB);

  // === DARK THEME BACKGROUNDS (settings / rare) ===
  static const canvas = Color(0xFF0B0F1A);
  static const surfaceCard = Color(0xFF141929);
  static const surfaceElevated = Color(0xFF1C2235);
  static const surfaceMuted = Color(0xFF232A3E);

  // === BRAND (legacy + charts) ===
  static const brandTeal = Color(0xFF17A8A7);

  /// Prefer [accentInfo] for interactive blue. Kept as alias for existing call sites.
  static const primaryMid = accentInfo;
  static const primaryDeep = Color(0xFF1D4ED8);

  /// Soft wash for chips / selected rows (neutral slate, not loud blue).
  static const primaryLight = Color(0xFFF1F5F9);
  static const accentPurple = Color(0xFF9B79E8);

  static const accentBlue = accentInfo;
  static const brand = primaryNavy;
  static const brandHover = Color(0xFF1E293B);

  // === SEMANTIC (strict) ===
  static const profit = Color(0xFF16A34A);
  static const loss = Color(0xFFDC2626);
  static const warning = Color(0xFFF0A500);
  static const accentAmber = Color(0xFFF59E0B);

  // === CHART COLORS ===
  static const chartLandingCost = Color(0xFF2563EB);
  static const chartSellingCost = Color(0xFF6366F1);
  static const chartPurple = Color(0xFF9B79E8);
  static const chartOrange = Color(0xFFFB923C);
  static const chartPink = Color(0xFFF472B6);

  static const List<Color> chartPalette = [
    primaryNavy,
    accentInfo,
    Color(0xFF8B5CF6),
    brandTeal,
    Color(0xFFF59E0B),
    Color(0xFFF472B6),
    Color(0xFF94A3B8),
    loss,
  ];

  // === TEXT ===
  static const textPrimary = Color(0xFFF0F4FF);
  static const textSecondary = Color(0xFF8993A9);
  static const border = Color(0x18FFFFFF);
  static const borderSubtle = Color(0x0AFFFFFF);
  static const textOnLightSurface = primaryNavy;

  static const accentLine = accentInfo;
  static const cost = Color(0xFF94A3B8);
  static const costMuted = neutral;
  static const heroGradientEnd = Color(0xFF1E3A5F);

  /// Primary CTA — navy tones (not blue wash).
  static LinearGradient get ctaGradient => const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFF334155),
          primaryNavy,
          Color(0xFF0F172A),
        ],
        stops: [0.0, 0.55, 1.0],
      );

  /// Hero / balance card — navy depth.
  static LinearGradient get heroCardGradient => const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFF0F172A),
          Color(0xFF1E293B),
          Color(0xFF334155),
        ],
      );

  static List<BoxShadow> glowShadow(Color color, {double blur = 18}) => [
        BoxShadow(
          color: color.withValues(alpha: 0.35),
          blurRadius: blur,
          spreadRadius: 0,
          offset: const Offset(0, 4),
        ),
      ];

  static List<BoxShadow> cardShadow(BuildContext context) => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.06),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ];
}
