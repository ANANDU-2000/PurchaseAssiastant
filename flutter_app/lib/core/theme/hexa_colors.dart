import 'package:flutter/material.dart';

/// Premium trader UI — dark navy canvas, muted teal accent, restrained purple secondary.
abstract final class HexaColors {
  // === DARK THEME BACKGROUNDS ===
  static const canvas = Color(0xFF0B0F1A);
  static const surfaceCard = Color(0xFF141929);
  static const surfaceElevated = Color(0xFF1C2235);
  static const surfaceMuted = Color(0xFF232A3E);

  // === BRAND (teal primary; purple as secondary accent) ===
  static const primaryDeep = Color(0xFF0E7C7B);
  static const primaryMid = Color(0xFF17A8A7);
  static const primaryLight = Color(0xFF102827);
  static const accentPurple = Color(0xFF9B79E8);

  /// Kept for gradual migration — maps to the teal accent, not legacy blue.
  static const accentBlue = primaryMid;
  static const brand = primaryMid;
  static const brandHover = Color(0xFF35C4C3);

  // === SEMANTIC ===
  static const profit = Color(0xFF2ECC71);
  static const loss = Color(0xFFE74C3C);
  static const warning = Color(0xFFF0A500);
  static const accentAmber = Color(0xFFF59E0B);

  // === CHART COLORS ===
  static const chartLandingCost = Color(0xFF5B8DEF);
  static const chartSellingCost = Color(0xFF34C99A);
  static const chartPurple = Color(0xFF9B79E8);
  static const chartOrange = Color(0xFFFB923C);
  static const chartPink = Color(0xFFF472B6);

  static const List<Color> chartPalette = [
    Color(0xFF17A8A7),
    Color(0xFF5B8DEF),
    Color(0xFF34C99A),
    Color(0xFF9B79E8),
    Color(0xFFF0A500),
    Color(0xFFF472B6),
    Color(0xFF94A3B8),
    Color(0xFFE74C3C),
  ];

  // === TEXT ===
  static const textPrimary = Color(0xFFF0F4FF);
  static const textSecondary = Color(0xFF8993A9);
  static const border = Color(0x18FFFFFF);
  static const borderSubtle = Color(0x0AFFFFFF);
  static const textOnLightSurface = Color(0xFF0F172A);

  static const accentLine = primaryMid;
  static const cost = Color(0xFF94A3B8);
  static const costMuted = Color(0xFF64748B);
  static const heroGradientEnd = Color(0xFF1C4A48);

  /// Primary CTA: light teal → deep teal → subtle purple.
  static LinearGradient get ctaGradient => const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFF5EEAD4),
          Color(0xFF17A8A7),
          Color(0xFF6B4FB8),
        ],
        stops: [0.0, 0.5, 1.0],
      );

  /// Hero / balance card — navy into deep teal.
  static LinearGradient get heroCardGradient => const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFF0E2A35),
          Color(0xFF123D3C),
          Color(0xFF1C4A48),
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
          color: Colors.black.withValues(alpha: 0.35),
          blurRadius: 20,
          offset: const Offset(0, 8),
        ),
        BoxShadow(
          color: accentPurple.withValues(alpha: 0.08),
          blurRadius: 24,
          offset: const Offset(0, 4),
        ),
      ];
}
