import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import '../../../core/theme/hexa_colors.dart';

/// Ring chart: round stroke, grey track, colored segments. Center shows label + value only.
class SpendRingChart extends StatelessWidget {
  const SpendRingChart({
    super.key,
    required this.diameter,
    required this.values,
    required this.colors,
    this.trackColor = const Color(0xFFE2E8F0),
    this.strokeWidth = 18,
    required this.centerLabel,
    required this.centerValue,
    this.onSectionTap,
  });

  final double diameter;
  final List<double> values;
  final List<Color> colors;
  final Color trackColor;
  final double strokeWidth;
  final String centerLabel;
  final String centerValue;
  final void Function(int index)? onSectionTap;

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
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: diameter * 0.55),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        centerLabel,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: const Color(0xFF64748B),
                              fontWeight: FontWeight.w600,
                              fontSize: 11,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        centerValue,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: HexaColors.brandPrimary,
                              fontSize: 20,
                              height: 1.05,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
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
