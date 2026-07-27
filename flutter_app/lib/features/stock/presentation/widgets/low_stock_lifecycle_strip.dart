import 'package:flutter/material.dart';

import '../../../../core/design_system/hexa_ds_tokens.dart';

/// Horizontal lifecycle chips for a low-stock operations row.
class LowStockLifecycleStrip extends StatelessWidget {
  const LowStockLifecycleStrip({
    super.key,
    required this.stage,
    this.reorderStatus,
    this.pendingDays,
  });

  final String stage;
  final String? reorderStatus;
  final int? pendingDays;

  static String labelForStage(String raw) {
    final s = raw.toLowerCase();
    return switch (s) {
      'out' => 'Out of stock',
      'ordered' => 'Ordered',
      'delayed' => 'Supplier delayed',
      'disputed' => 'Disputed',
      'verification' => 'Needs verification',
      'reorder_requested' => 'Reorder requested',
      'reorder_done' => 'On reorder list',
      'low' => 'Below reorder',
      _ => 'Attention',
    };
  }

  Color _colorForStage(String s) {
    return switch (s) {
      'out' => const Color(0xFFDC2626),
      'delayed' => const Color(0xFFBA7517),
      'disputed' => const Color(0xFFA32D2D),
      'verification' => const Color(0xFF0EA5E9),
      'ordered' => const Color(0xFF0F766E),
      'reorder_requested' => const Color(0xFFE65100),
      'reorder_done' => const Color(0xFF6366F1),
      'low' => const Color(0xFFE65100),
      _ => HexaDsColors.textMuted,
    };
  }

  @override
  Widget build(BuildContext context) {
    final normalized = stage.toLowerCase();
    final chips = <Widget>[
      _Chip(
        label: labelForStage(normalized),
        color: _colorForStage(normalized),
      ),
    ];
    if (reorderStatus != null && reorderStatus!.isNotEmpty) {
      chips.add(
        _Chip(
          label: 'Reorder: ${reorderStatus!.toUpperCase()}',
          color: const Color(0xFF6366F1),
        ),
      );
    }
    if (pendingDays != null) {
      chips.add(
        _Chip(
          label: '${pendingDays}d pending',
          color: const Color(0xFF0F766E),
        ),
      );
    }

    return Wrap(spacing: 6, runSpacing: 6, children: chips);
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }
}
