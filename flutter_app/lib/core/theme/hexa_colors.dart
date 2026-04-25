import 'package:flutter/material.dart';

/// Premium green + gold brand palette — Harisree Purchases.
abstract final class HexaColors {
  // ── BRAND ──────────────────────────────────────────────────────────────────
  static const brandPrimary    = Color(0xFF0E4F46);
  static const brandSecondary  = Color(0xFF065F4F);
  static const brandAccent     = Color(0xFF159A8A);
  static const brandGold       = Color(0xFFD4AF37);
  static const brandGoldLight  = Color(0xFFF5E4A0);
  /// Page chrome behind transparent [Scaffold]s (auth sheets stay solid white).
  static const brandBackground = Color(0xFFF7F9F6);
  static const brandCard       = Color(0xFFFFFFFF);
  static const brandBorder     = Color(0xFFE2E8E6);

  /// Global text fields — neutral chrome (Tailwind gray-200).
  static const inputBorderGrey = Color(0xFFE5E7EB);
  /// Primary field text (#111).
  static const inputText = Color(0xFF111111);
  /// Placeholder / hint — light grey, still readable on white.
  static const inputHint = Color(0xFF9CA3AF);
  /// Focus ring `rgba(21,154,138,0.2)` (same hue as [brandAccent]).
  static const inputFocusRing = Color(0x33159A8A);
  /// Error focus ring `rgba(220,38,38,0.2)`.
  static const inputErrorFocusRing = Color(0x33DC2626);

  /// Soft fintech shell — cool grey → white (used by [MaterialApp] builder).
  static LinearGradient get appShellGradient => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFFECEFF1),
          Color(0xFFF5F7F6),
          Color(0xFFFFFFFF),
        ],
        stops: [0.0, 0.42, 1.0],
      );

  static const brandDisabledBg   = Color(0xFFD1E8E3);
  static const brandDisabledText = Color(0xFF9CA3AF);

  // ── SURFACES ───────────────────────────────────────────────────────────────
  static const surfaceApp       = Color(0xFFFFFFFF);
  static const surfaceCardLight = Color(0xFFFFFFFF);
  static const surfaceCard      = Color(0xFF141929);
  static const surfaceElevated  = Color(0xFF1C2235);
  static const surfaceMuted     = Color(0xFF232A3E);
  static const canvas           = Color(0xFF0B0F1A);

  // ── TEXT ───────────────────────────────────────────────────────────────────
  static const textBody         = Color(0xFF475569);
  static const textOnLightSurface = Color(0xFF0F172A);
  static const neutral          = Color(0xFF64748B);
  static const primaryNavy      = Color(0xFF0F172A);
  static const textPrimary      = Color(0xFFF0F4FF);
  static const textSecondary    = Color(0xFF8993A9);

  // ── SEMANTIC ───────────────────────────────────────────────────────────────
  static const profit  = Color(0xFF16A34A);
  static const loss    = Color(0xFFE53935);
  static const warning = Color(0xFFF0A500);
  static const accentAmber = Color(0xFFF59E0B);

  // ── GRADIENTS ──────────────────────────────────────────────────────────────
  static const primaryLight = Color(0xFFE8F5F2);
  static const accentInfo   = Color(0xFF159A8A);     // kept for legacy references

  // Legacy aliases kept so existing call sites compile
  static const primaryMid  = brandAccent;
  static const primaryDeep = brandPrimary;
  static const brandHover  = Color(0xFF0A3D36);
  static const brand       = primaryNavy;
  static const brandTeal   = brandAccent;
  static const accentBlue  = brandAccent;
  static const accentPurple = Color(0xFF9B79E8);     // used by analytics
  static const accentLine   = brandAccent;
  static const cost         = Color(0xFF94A3B8);
  static const costMuted    = neutral;
  static const heroGradientEnd = Color(0xFF0A3D36);
  static const border          = Color(0x18FFFFFF);
  static const borderSubtle    = Color(0x0AFFFFFF);

  // ── CHARTS ─────────────────────────────────────────────────────────────────
  static const chartLandingCost  = Color(0xFF159A8A);
  static const chartSellingCost  = Color(0xFF16A34A);
  static const chartProfit       = Color(0xFFD4AF37);
  static const chartPurple       = Color(0xFF9B79E8);
  static const chartOrange       = Color(0xFFFB923C);
  static const chartPink         = Color(0xFFF472B6);

  static const List<Color> chartPalette = [
    brandPrimary,
    brandAccent,
    brandGold,
    Color(0xFF9B79E8),
    Color(0xFFFB923C),
    Color(0xFFF472B6),
    Color(0xFF94A3B8),
    loss,
  ];

  // ── GRADIENTS ──────────────────────────────────────────────────────────────
  /// Landing / auth scrim — no embedded photo text (replaces warehouse hero PNG).
  static LinearGradient get atmosphereGradient => const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFF062E28),
          brandPrimary,
          Color(0xFF0D5C50),
          primaryLight,
        ],
        stops: [0.0, 0.35, 0.72, 1.0],
      );

  /// Primary CTA gradient — deep green → teal.
  static LinearGradient get ctaGradient => const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [brandPrimary, brandAccent],
      );

  /// Hero / summary card — deep green → teal with gold highlight.
  static LinearGradient get heroCardGradient => const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF0E4F46), Color(0xFF0D6B5E), Color(0xFF159A8A)],
        stops: [0.0, 0.55, 1.0],
      );

  /// Subtle gold accent gradient for profit badges / chips.
  static LinearGradient get goldGradient => const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFD4AF37), Color(0xFFF0D060)],
      );

  static List<BoxShadow> glowShadow(Color color, {double blur = 18}) => [
        BoxShadow(
          color: color.withValues(alpha: 0.32),
          blurRadius: blur,
          spreadRadius: 0,
          offset: const Offset(0, 4),
        ),
      ];

  /// Premium card lift — teal-tinted umbra + soft ambient (context-free for themes).
  static List<BoxShadow> get premiumCardShadow => [
        BoxShadow(
          color: brandPrimary.withValues(alpha: 0.08),
          blurRadius: 28,
          offset: const Offset(0, 10),
          spreadRadius: 0,
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.06),
          blurRadius: 16,
          offset: const Offset(0, 4),
        ),
      ];

  static List<BoxShadow> cardShadow(BuildContext context) =>
      premiumCardShadow;

  static List<BoxShadow> heroShadow() => [
        BoxShadow(
          color: const Color(0xFF0E4F46).withValues(alpha: 0.30),
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
      ];
}
