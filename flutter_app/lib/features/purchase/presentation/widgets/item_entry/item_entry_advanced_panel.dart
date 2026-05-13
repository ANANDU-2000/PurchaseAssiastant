import 'package:flutter/material.dart';

import '../../../domain/purchase_draft.dart' show RateTaxBasis;

/// GST Extra / Included basis (legacy accountant mode), shown only under Advanced.
class GstRateBasisSegmentColumn extends StatelessWidget {
  const GstRateBasisSegmentColumn({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    required this.helperExtra,
    required this.helperIncluded,
  });

  final String title;
  final RateTaxBasis value;
  final ValueChanged<RateTaxBasis> onChanged;
  final String helperExtra;
  final String helperIncluded;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: cs.onSurface.withValues(alpha: 0.9),
          ),
        ),
        const SizedBox(height: 6),
        SegmentedButton<RateTaxBasis>(
          segments: const [
            ButtonSegment(
              value: RateTaxBasis.taxExtra,
              label: Text('GST Extra'),
            ),
            ButtonSegment(
              value: RateTaxBasis.includesTax,
              label: Text('GST Included'),
            ),
          ],
          selected: {value},
          onSelectionChanged: (s) {
            if (s.isEmpty) return;
            onChanged(s.first);
          },
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            value == RateTaxBasis.taxExtra ? helperExtra : helperIncluded,
            style: TextStyle(
              fontSize: 12,
              height: 1.3,
              fontWeight: FontWeight.w600,
              color: cs.onSurface.withValues(alpha: 0.78),
            ),
          ),
        ),
      ],
    );
  }
}
