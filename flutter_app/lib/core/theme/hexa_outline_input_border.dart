import 'package:flutter/material.dart';

import 'hexa_colors.dart';

/// [OutlineInputBorder] that draws a CSS-style focus ring
/// `box-shadow: 0 0 0 3px rgba(21,154,138,0.2)` before the outline stroke.
class HexaOutlineInputBorder extends OutlineInputBorder {
  const HexaOutlineInputBorder({
    super.borderSide,
    super.borderRadius = const BorderRadius.all(Radius.circular(12)),
    super.gapPadding = 6,
    this.focusRing = false,
    this.ringColor = HexaColors.inputFocusRing,
    this.ringStrokeWidth = 3,
    this.ringOutset = 2,
  });

  /// When true, paints the outer glow ring (intended for focused / focusedError).
  final bool focusRing;

  /// Stroke color for the outer ring (default matches rgba(21,154,138,0.2)).
  final Color ringColor;

  final double ringStrokeWidth;
  final double ringOutset;

  @override
  void paint(
    Canvas canvas,
    Rect rect, {
    double? gapStart,
    double gapExtent = 0.0,
    double gapPercentage = 0.0,
    TextDirection? textDirection,
  }) {
    if (focusRing && borderSide.width > 0) {
      final dir = textDirection ?? TextDirection.ltr;
      final resolved = borderRadius.resolve(dir);
      final o = ringOutset;
      final outerRect = Rect.fromLTRB(
        rect.left - o,
        rect.top - o,
        rect.right + o,
        rect.bottom + o,
      );
      final maxR = outerRect.shortestSide / 2;
      final base = resolved.topLeft.x;
      final r = base + o > maxR ? maxR : base + o;
      final glowRRect = RRect.fromRectAndRadius(outerRect, Radius.circular(r));
      canvas.drawRRect(
        glowRRect,
        Paint()
          ..color = ringColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = ringStrokeWidth,
      );
    }
    super.paint(
      canvas,
      rect,
      gapStart: gapStart,
      gapExtent: gapExtent,
      gapPercentage: gapPercentage,
      textDirection: textDirection,
    );
  }

  @override
  HexaOutlineInputBorder copyWith({
    BorderSide? borderSide,
    BorderRadius? borderRadius,
    double? gapPadding,
    bool? focusRing,
    Color? ringColor,
    double? ringStrokeWidth,
    double? ringOutset,
  }) {
    return HexaOutlineInputBorder(
      borderSide: borderSide ?? this.borderSide,
      borderRadius: borderRadius ?? this.borderRadius,
      gapPadding: gapPadding ?? this.gapPadding,
      focusRing: focusRing ?? this.focusRing,
      ringColor: ringColor ?? this.ringColor,
      ringStrokeWidth: ringStrokeWidth ?? this.ringStrokeWidth,
      ringOutset: ringOutset ?? this.ringOutset,
    );
  }

  @override
  HexaOutlineInputBorder scale(double t) {
    final OutlineInputBorder scaled = super.scale(t);
    return HexaOutlineInputBorder(
      borderSide: scaled.borderSide,
      borderRadius: scaled.borderRadius,
      gapPadding: scaled.gapPadding,
      focusRing: focusRing,
      ringColor: ringColor,
      ringStrokeWidth: ringStrokeWidth,
      ringOutset: ringOutset,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other.runtimeType != runtimeType) return false;
    return other is HexaOutlineInputBorder &&
        other.borderSide == borderSide &&
        other.borderRadius == borderRadius &&
        other.gapPadding == gapPadding &&
        other.focusRing == focusRing &&
        other.ringColor == ringColor &&
        other.ringStrokeWidth == ringStrokeWidth &&
        other.ringOutset == ringOutset;
  }

  @override
  int get hashCode => Object.hash(
        borderSide,
        borderRadius,
        gapPadding,
        focusRing,
        ringColor,
        ringStrokeWidth,
        ringOutset,
      );
}
