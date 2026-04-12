import 'package:flutter/material.dart';

/// Premium dark UI tokens — deep charcoal, blue–white CTAs, purple glow accents.
abstract final class HexaColors {
  // === DARK THEME BACKGROUNDS ===
  static const canvas = Color(0xFF07080D);
  static const surfaceCard = Color(0xFF12141C);
  static const surfaceElevated = Color(0xFF1A1D28);
  static const surfaceMuted = Color(0xFF242833);

  // === BRAND (blue + purple, replaces legacy teal) ===
  static const primaryDeep = Color(0xFF2563EB);
  static const primaryMid = Color(0xFF7EB8FF);
  static const primaryLight = Color(0xFF1A2233);
  static const accentPurple = Color(0xFFA78BFA);
  static const accentBlue = Color(0xFF60A5FA);
  static const brand = primaryMid;
  static const brandHover = Color(0xFF93C5FD);

  // === SEMANTIC ===
  static const profit = Color(0xFF34D399);
  static const loss = Color(0xFFF87171);
  static const warning = Color(0xFFFBBF24);
  static const accentAmber = Color(0xFFF59E0B);

  // === CHART COLORS ===
  static const chartLandingCost = Color(0xFF60A5FA);
  static const chartSellingCost = Color(0xFF34D399);
  static const chartPurple = Color(0xFFA78BFA);
  static const chartOrange = Color(0xFFFB923C);
  static const chartPink = Color(0xFFF472B6);

  static const List<Color> chartPalette = [
    Color(0xFF60A5FA),
    Color(0xFFA78BFA),
    Color(0xFF34D399),
    Color(0xFFFB923C),
    Color(0xFFFBBF24),
    Color(0xFFF472B6),
    Color(0xFF94A3B8),
    Color(0xFFF87171),
  ];

  // === TEXT ===
  static const textPrimary = Color(0xFFF8FAFC);
  static const textSecondary = Color(0xFF94A3B8);
  static const border = Color(0x14FFFFFF);
  static const borderSubtle = Color(0x0AFFFFFF);
  static const textOnLightSurface = Color(0xFF0F172A);

  static const accentLine = primaryMid;
  static const cost = Color(0xFF94A3B8);
  static const costMuted = Color(0xFF64748B);
  static const heroGradientEnd = Color(0xFF312E81);

  /// Primary CTA: blue → white-ish → purple (premium glow feel).
  static LinearGradient get ctaGradient => const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFFE8F0FF),
          Color(0xFF6366F1),
          Color(0xFF9333EA),
        ],
        stops: [0.0, 0.55, 1.0],
      );

  /// Softer hero card / balance card gradient.
  static LinearGradient get heroCardGradient => const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFF1E3A5F),
          Color(0xFF312E81),
          Color(0xFF4C1D95),
        ],
      );

  /// FAB / small accent glow (purple haze).
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
