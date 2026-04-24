import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../theme/hexa_colors.dart';

/// Glass + gradient tokens for premium SaaS surfaces (light / dark).
///
/// Registered on [ThemeData.extensions]; read via [HexaGlassContext.hx] on [BuildContext].
@immutable
class HexaGlassTheme extends ThemeExtension<HexaGlassTheme> {
  const HexaGlassTheme({
    required this.surfaceCanvas,
    required this.surfaceCard,
    required this.glassFill,
    required this.glassStroke,
    required this.inputFill,
    required this.borderSubtle,
    required this.textPrimary,
    required this.textBody,
    required this.textMuted,
    required this.success,
    required this.successForeground,
    required this.canvasGradient,
    required this.glassBlurSigma,
    required this.cardShadow,
    required this.inputRestShadow,
    required this.inputFocusShadow,
    required this.segmentTrack,
    required this.segmentSelected,
  });

  final Color surfaceCanvas;
  final Color surfaceCard;
  final Color glassFill;
  final Color glassStroke;
  final Color inputFill;
  final Color borderSubtle;
  final Color textPrimary;
  final Color textBody;
  final Color textMuted;
  final Color success;
  final Color successForeground;
  final Gradient canvasGradient;
  final double glassBlurSigma;
  final List<BoxShadow> cardShadow;
  final List<BoxShadow> inputRestShadow;
  final List<BoxShadow> inputFocusShadow;
  final Color segmentTrack;
  final Color segmentSelected;

  static HexaGlassTheme light() {
    return HexaGlassTheme(
      surfaceCanvas: const Color(0xFFECEFF1),
      surfaceCard: HexaColors.surfaceCardLight,
      glassFill: const Color(0xB8FFFFFF),
      glassStroke: const Color(0x99FFFFFF),
      inputFill: Colors.white,
      borderSubtle: HexaColors.inputBorderGrey,
      textPrimary: HexaColors.textOnLightSurface,
      textBody: HexaColors.textBody,
      textMuted: HexaColors.neutral,
      success: const Color(0xFF059669),
      successForeground: const Color(0xFF065F46),
      canvasGradient: HexaColors.appShellGradient,
      glassBlurSigma: 28,
      cardShadow: HexaColors.premiumCardShadow,
      inputRestShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.05),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ],
      inputFocusShadow: [
        const BoxShadow(
          color: HexaColors.inputFocusRing,
          blurRadius: 0,
          spreadRadius: 3,
          offset: Offset.zero,
        ),
      ],
      segmentTrack: const Color(0xE6EDEBEC),
      segmentSelected: const Color(0xF2FFFFFF),
    );
  }

  static HexaGlassTheme dark() {
    return HexaGlassTheme(
      surfaceCanvas: const Color(0xFF070B14),
      surfaceCard: const Color(0xFF12182A),
      glassFill: const Color(0x3DFFFFFF),
      glassStroke: const Color(0x33FFFFFF),
      inputFill: const Color(0xFF1E293B),
      borderSubtle: const Color(0xFF475569),
      textPrimary: const Color(0xFFF1F5F9),
      textBody: const Color(0xFFCBD5E1),
      textMuted: const Color(0xFF94A3B8),
      success: const Color(0xFF34D399),
      successForeground: const Color(0xFF6EE7B7),
      canvasGradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFF070B14),
          Color(0xFF0F172A),
          Color(0xFF1E1B4B),
          Color(0xFF111827),
        ],
        stops: [0.0, 0.38, 0.72, 1.0],
      ),
      glassBlurSigma: 32,
      cardShadow: [
        BoxShadow(
          color: const Color(0xFF6366F1).withValues(alpha: 0.15),
          blurRadius: 48,
          offset: const Offset(0, 20),
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.45),
          blurRadius: 32,
          offset: const Offset(0, 12),
        ),
      ],
      inputRestShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.35),
          blurRadius: 14,
          offset: const Offset(0, 6),
        ),
      ],
      inputFocusShadow: [
        BoxShadow(
          color: HexaColors.brandAccent.withValues(alpha: 0.35),
          blurRadius: 0,
          spreadRadius: 3,
          offset: Offset.zero,
        ),
      ],
      segmentTrack: const Color(0x45101828),
      segmentSelected: const Color(0x5CFFFFFF),
    );
  }

  @override
  HexaGlassTheme copyWith({
    Color? surfaceCanvas,
    Color? surfaceCard,
    Color? glassFill,
    Color? glassStroke,
    Color? inputFill,
    Color? borderSubtle,
    Color? textPrimary,
    Color? textBody,
    Color? textMuted,
    Color? success,
    Color? successForeground,
    Gradient? canvasGradient,
    double? glassBlurSigma,
    List<BoxShadow>? cardShadow,
    List<BoxShadow>? inputRestShadow,
    List<BoxShadow>? inputFocusShadow,
    Color? segmentTrack,
    Color? segmentSelected,
  }) {
    return HexaGlassTheme(
      surfaceCanvas: surfaceCanvas ?? this.surfaceCanvas,
      surfaceCard: surfaceCard ?? this.surfaceCard,
      glassFill: glassFill ?? this.glassFill,
      glassStroke: glassStroke ?? this.glassStroke,
      inputFill: inputFill ?? this.inputFill,
      borderSubtle: borderSubtle ?? this.borderSubtle,
      textPrimary: textPrimary ?? this.textPrimary,
      textBody: textBody ?? this.textBody,
      textMuted: textMuted ?? this.textMuted,
      success: success ?? this.success,
      successForeground: successForeground ?? this.successForeground,
      canvasGradient: canvasGradient ?? this.canvasGradient,
      glassBlurSigma: glassBlurSigma ?? this.glassBlurSigma,
      cardShadow: cardShadow ?? this.cardShadow,
      inputRestShadow: inputRestShadow ?? this.inputRestShadow,
      inputFocusShadow: inputFocusShadow ?? this.inputFocusShadow,
      segmentTrack: segmentTrack ?? this.segmentTrack,
      segmentSelected: segmentSelected ?? this.segmentSelected,
    );
  }

  static List<BoxShadow> _lerpShadows(List<BoxShadow> a, List<BoxShadow> b, double t) {
    final n = a.length > b.length ? a.length : b.length;
    final out = <BoxShadow>[];
    for (var i = 0; i < n; i++) {
      final sa = i < a.length ? a[i] : a.last;
      final sb = i < b.length ? b[i] : b.last;
      out.add(BoxShadow(
        color: Color.lerp(sa.color, sb.color, t)!,
        blurRadius: lerpDouble(sa.blurRadius, sb.blurRadius, t)!,
        spreadRadius: lerpDouble(sa.spreadRadius, sb.spreadRadius, t)!,
        offset: Offset.lerp(sa.offset, sb.offset, t)!,
      ));
    }
    return out;
  }

  @override
  HexaGlassTheme lerp(ThemeExtension<HexaGlassTheme>? other, double t) {
    if (other is! HexaGlassTheme) return this;
    return HexaGlassTheme(
      surfaceCanvas: Color.lerp(surfaceCanvas, other.surfaceCanvas, t)!,
      surfaceCard: Color.lerp(surfaceCard, other.surfaceCard, t)!,
      glassFill: Color.lerp(glassFill, other.glassFill, t)!,
      glassStroke: Color.lerp(glassStroke, other.glassStroke, t)!,
      inputFill: Color.lerp(inputFill, other.inputFill, t)!,
      borderSubtle: Color.lerp(borderSubtle, other.borderSubtle, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textBody: Color.lerp(textBody, other.textBody, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      success: Color.lerp(success, other.success, t)!,
      successForeground: Color.lerp(successForeground, other.successForeground, t)!,
      canvasGradient: t < 0.5 ? canvasGradient : other.canvasGradient,
      glassBlurSigma: lerpDouble(glassBlurSigma, other.glassBlurSigma, t)!,
      cardShadow: _lerpShadows(cardShadow, other.cardShadow, t),
      inputRestShadow: _lerpShadows(inputRestShadow, other.inputRestShadow, t),
      inputFocusShadow: _lerpShadows(inputFocusShadow, other.inputFocusShadow, t),
      segmentTrack: Color.lerp(segmentTrack, other.segmentTrack, t)!,
      segmentSelected: Color.lerp(segmentSelected, other.segmentSelected, t)!,
    );
  }
}

extension HexaGlassContext on BuildContext {
  HexaGlassTheme get hx =>
      Theme.of(this).extension<HexaGlassTheme>() ??
      (Theme.of(this).brightness == Brightness.dark
          ? HexaGlassTheme.dark()
          : HexaGlassTheme.light());
}
