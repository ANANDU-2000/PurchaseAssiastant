import 'package:flutter/material.dart';

import '../../../../core/theme/hexa_colors.dart';

/// Client-side warehouse health KPI (0–100) from alert counts.
class StockHealthScore {
  StockHealthScore({
    required this.score,
    required this.label,
    required this.color,
    required this.lowCount,
    required this.criticalCount,
    required this.outCount,
  });

  final int score;
  final String label;
  final Color color;
  final int lowCount;
  final int criticalCount;
  final int outCount;

  factory StockHealthScore.compute({
    required int lowCount,
    required int criticalCount,
    required int outCount,
  }) {
    var s = 100;
    s -= lowCount;
    s -= criticalCount * 3;
    s -= outCount * 5;
    if (s < 40) s = 40;
    if (s > 100) s = 100;
    final (label, color) = switch (s) {
      >= 90 => ('Excellent', const Color(0xFF2E7D32)),
      >= 75 => ('Good', const Color(0xFF388E3C)),
      >= 60 => ('Fair', const Color(0xFFF59E0B)),
      >= 40 => ('Low', const Color(0xFFE65100)),
      _ => ('Critical', const Color(0xFFC62828)),
    };
    return StockHealthScore(
      score: s,
      label: label,
      color: color,
      lowCount: lowCount,
      criticalCount: criticalCount,
      outCount: outCount,
    );
  }
}

class StockHealthScoreBadge extends StatelessWidget {
  const StockHealthScoreBadge({super.key, required this.health, this.compact = false});

  final StockHealthScore health;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: health.color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: health.color.withValues(alpha: 0.35)),
        ),
        child: Text(
          '${health.score}',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 13,
            color: health.color,
          ),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: HexaColors.brandBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: health.color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 44,
            height: 44,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: health.score / 100,
                  strokeWidth: 4,
                  color: health.color,
                  backgroundColor: health.color.withValues(alpha: 0.15),
                ),
                Text(
                  '${health.score}',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    color: health.color,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Stock health',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade600,
                ),
              ),
              Text(
                health.label,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  color: health.color,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
