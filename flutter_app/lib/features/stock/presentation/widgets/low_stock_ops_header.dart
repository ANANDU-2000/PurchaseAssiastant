import 'package:flutter/material.dart';

import '../../../../core/design_system/hexa_ds_tokens.dart';
import '../../../../core/theme/hexa_colors.dart';

class LowStockOpsHeader extends StatelessWidget {
  const LowStockOpsHeader({
    super.key,
    required this.totalAttention,
    required this.outCount,
    required this.pendingCount,
    required this.delayedCount,
    required this.mismatchCount,
    required this.pendingVerificationCount,
    required this.estimatedImpactLabel,
  });

  final int totalAttention;
  final int outCount;
  final int pendingCount;
  final int delayedCount;
  final int mismatchCount;
  final int pendingVerificationCount;
  final String estimatedImpactLabel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$totalAttention items need attention',
                  style: HexaDsType.heading(14, color: HexaColors.brandPrimary),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 10,
                  runSpacing: 6,
                  children: [
                    _Metric(value: outCount, label: 'OUT', color: const Color(0xFFC62828)),
                    _Metric(
                      value: pendingCount,
                      label: 'PENDING',
                      color: const Color(0xFF3B82F6),
                    ),
                    _Metric(
                      value: delayedCount,
                      label: 'DELAYED',
                      color: const Color(0xFFBA7517),
                    ),
                    _Metric(
                      value: mismatchCount,
                      label: 'DISPUTED',
                      color: const Color(0xFFA32D2D),
                    ),
                    _Metric(
                      value: pendingVerificationCount,
                      label: 'VERIFICATION',
                      color: const Color(0xFF0EA5E9),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 200),
            child: Text(
              estimatedImpactLabel,
              style: HexaDsType.label(12).copyWith(fontWeight: FontWeight.w800),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.value,
    required this.label,
    required this.color,
  });

  final int value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: 22,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
          ),
          alignment: Alignment.center,
          child: Text(
            '$value',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: Colors.black54,
          ),
        ),
      ],
    );
  }
}

