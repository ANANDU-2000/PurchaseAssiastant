import 'package:flutter/material.dart';

import '../../core/unit_engine/stock_tracking_profile.dart';

/// Warehouse stock type picker — KG / BAG / BOX / TIN / PC only.
class PackagingTypeSelector extends StatelessWidget {
  const PackagingTypeSelector({
    super.key,
    required this.selectedMode,
    required this.onModeChanged,
  });

  final String? selectedMode;
  final ValueChanged<String> onModeChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Stock type',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final m in StockTrackingMode.pickerModes)
              ChoiceChip(
                label: Text(StockTrackingMode.labelForMode(m)),
                selected: selectedMode == m,
                onSelected: (_) => onModeChanged(m),
              ),
          ],
        ),
      ],
    );
  }
}
