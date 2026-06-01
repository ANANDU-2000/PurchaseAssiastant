import 'package:flutter/material.dart';

import '../../../core/theme/hexa_colors.dart';
import '../reports_bi_tab.dart';

/// Single row of four primary Reports tabs.
class ReportsPrimaryTabs extends StatelessWidget {
  const ReportsPrimaryTabs({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final ReportsBiTab selected;
  final ValueChanged<ReportsBiTab> onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: SegmentedButton<ReportsBiTab>(
        segments: [
          for (final t in ReportsBiTabX.primaryTabs)
            ButtonSegment(
              value: t,
              label: Text(
                t.shortLabel,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
              ),
            ),
        ],
        selected: {selected},
        onSelectionChanged: (s) {
          if (s.isNotEmpty) onSelected(s.first);
        },
        style: ButtonStyle(
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.padded,
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return HexaColors.brandPrimary.withValues(alpha: 0.12);
            }
            return HexaColors.brandCard;
          }),
        ),
      ),
    );
  }
}
