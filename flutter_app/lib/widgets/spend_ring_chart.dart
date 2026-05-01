import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import '../core/theme/hexa_colors.dart';

/// Donut ring: optional center content. If [centerChild] and all [centerLine]s
/// are absent/empty, the center shows an empty [SizedBox] (no crash, no fake text).
class SpendRingChart extends StatelessWidget {
  const SpendRingChart({
    super.key,
    required this.diameter,
    required this.values,
    required this.colors,
    this.trackColor = const Color(0xFFE2E8F0),
    this.strokeWidth = 17,
    this.centerChild,
    this.centerLine1,
    this.centerLine2,
    this.centerLine3,
    this.centerLine4,
    this.onSectionTap,
  });

  final double diameter;
  final List<double> values;
  final List<Color> colors;
  final Color trackColor;
  final double strokeWidth;
  final Widget? centerChild;
  final String? centerLine1;
  final String? centerLine2;
  final String? centerLine3;
  final String? centerLine4;
  final void Function(int index)? onSectionTap;

  bool get _hasLineText {
    bool ne(String? s) => s != null && s.trim().isNotEmpty;
    return ne(centerLine1) ||
        ne(centerLine2) ||
        ne(centerLine3) ||
        ne(centerLine4);
  }

  @override
  Widget build(BuildContext context) {
    final sum = values.fold<double>(0, (a, b) => a + b);
    return GestureDetector(
      onTapUp: (d) {
        if (sum <= 0 || onSectionTap == null) return;
        final box = context.findRenderObject() as RenderBox?;
        if (box == null) return;
        final local = box.globalToLocal(d.globalPosition);
        final c = Offset(diameter / 2, diameter / 2);
        final v = local - c;
        final r = (diameter - strokeWidth) / 2;
        final dist = v.distance;
        if (dist < r - strokeWidth * 1.1 || dist > r + strokeWidth * 1.1) {
          return;
        }
        final ang = math.atan2(v.dy, v.dx);
        final sumV = values.fold<double>(0, (a, b) => a + b);
        var start = -math.pi / 2;
        for (var i = 0; i < values.length; i++) {
          final val = values[i];
          if (val <= 0) continue;
          final sweep = 2 * math.pi * (val / sumV);
          final end = start + sweep;
          if (ang >= start && ang < end) {
            onSectionTap?.call(i);
            return;
          }
          start = end;
        }
      },
      child: SizedBox(
        width: diameter,
        height: diameter,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CustomPaint(
              size: Size(diameter, diameter),
              painter: _RingPainter(
                values: values,
                colors: colors,
                trackColor: trackColor,
                strokeWidth: strokeWidth,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: _buildCenter(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCenter(BuildContext context) {
    if (centerChild != null) {
      return FittedBox(
        fit: BoxFit.scaleDown,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: diameter * 0.72),
          child: centerChild!,
        ),
      );
    }
    if (!_hasLineText) {
      return const SizedBox.shrink();
    }
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: diameter * 0.62),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (centerLine1 != null && centerLine1!.trim().isNotEmpty) ...[
              Text(
                centerLine1!,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: HexaColors.brandPrimary,
                      fontSize: 20,
                      height: 1.05,
                    ),
              ),
              const SizedBox(height: 3),
            ],
            if (centerLine2 != null && centerLine2!.trim().isNotEmpty) ...[
              Text(
                centerLine2!,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF334155),
                ),
              ),
              const SizedBox(height: 4),
            ],
            if (centerLine3 != null && centerLine3!.trim().isNotEmpty)
              Text(
                centerLine3!,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF0F172A),
                ),
              ),
            if (centerLine4 != null && centerLine4!.trim().isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                centerLine4!,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF64748B),
                  height: 1.1,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.values,
    required this.colors,
    required this.trackColor,
    required this.strokeWidth,
  });

  final List<double> values;
  final List<Color> colors;
  final Color trackColor;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = (size.width / 2) - strokeWidth / 2;
    final rect = Rect.fromCircle(center: c, radius: r);
    final bg = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, 2 * math.pi, false, bg);

    final sum = values.fold<double>(0, (a, b) => a + b);
    if (sum <= 0) return;

    var start = -math.pi / 2;
    for (var i = 0; i < values.length; i++) {
      final v = values[i];
      if (v <= 0) continue;
      final sweep = 2 * math.pi * (v / sum);
      if (sweep <= 0) continue;
      final p = Paint()
        ..color = colors[i % colors.length]
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..isAntiAlias = true;
      canvas.drawArc(rect, start, sweep, false, p);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter o) {
    return !listEquals(o.values, values) ||
        !listEquals(o.colors, colors) ||
        o.trackColor != trackColor ||
        o.strokeWidth != strokeWidth;
  }
}
