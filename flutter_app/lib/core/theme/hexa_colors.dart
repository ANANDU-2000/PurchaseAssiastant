import 'package:flutter/material.dart';

/// HEXA semantic + brand palette — deep ocean teal + warm amber (trader / premium SaaS).
abstract final class HexaColors {
  static const primaryDeep = Color(0xFF0D3D56);
  static const primaryMid = Color(0xFF1A6B8A);
  static const primaryLight = Color(0xFFE8F4F8);

  /// Legacy aliases (wide codebase) — map to new brand.
  static const brand = primaryMid;
  static const brandHover = Color(0xFF155A73);

  static const accentAmber = Color(0xFFFF9800);
  static const canvas = Color(0xFFF4F7FB);
  static const surfaceCard = Color(0xFFFFFFFF);
  static const surfaceMuted = Color(0xFFEEF2F7);
  static const border = Color(0xFFD8E0EA);
  static const borderSubtle = Color(0xFFE8EEF4);

  /// Premium accent line (tabs, focus rings).
  static const accentLine = Color(0xFF2A8EAF);

  static const profit = Color(0xFF2E7D32);
  static const loss = Color(0xFFE53935);
  static const warning = Color(0xFFFF9800);
  static const cost = Color(0xFF94A3B8);
  static const costMuted = Color(0xFF64748B);

  static const textPrimary = Color(0xFF0F1923);
  static const textSecondary = Color(0xFF64748B);

  /// Hero gradient end (rich green) for profit stories.
  static const heroGradientEnd = Color(0xFF14532D);

  static List<BoxShadow> cardShadow(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (isDark) {
      return [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.35),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ];
    }
    return [
      BoxShadow(
        color: primaryDeep.withValues(alpha: 0.06),
        blurRadius: 12,
        offset: const Offset(0, 4),
      ),
    ];
  }
}
