import 'package:flutter/material.dart';

/// Collapsed summary of supplier freight defaults; tap to edit rates.
class DefaultsAppliedCard extends StatelessWidget {
  const DefaultsAppliedCard({
    super.key,
    required this.supplierLabel,
    required this.freightType,
    required this.onFreightTypeChanged,
    required this.deliveredController,
    required this.billtyController,
    required this.freightController,
    required this.freightReadOnly,
    required this.onDeliveredChanged,
    required this.onBilltyChanged,
    required this.onFreightChanged,
  });

  final String supplierLabel;
  final String freightType;
  final ValueChanged<String> onFreightTypeChanged;
  final TextEditingController deliveredController;
  final TextEditingController billtyController;
  final TextEditingController freightController;
  final bool freightReadOnly;
  final ValueChanged<String> onDeliveredChanged;
  final ValueChanged<String> onBilltyChanged;
  final ValueChanged<String> onFreightChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: ExpansionTile(
        title: Text(
          supplierLabel.isEmpty ? 'Defaults applied' : 'Defaults applied · $supplierLabel',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
        subtitle: const Text('Delivered / Billty / Freight', style: TextStyle(fontSize: 12)),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'included', label: Text('Freight included')),
              ButtonSegment(value: 'separate', label: Text('Freight separate')),
            ],
            selected: {freightType},
            onSelectionChanged: (v) => onFreightTypeChanged(v.first),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: deliveredController,
            decoration: const InputDecoration(labelText: 'Delivered rate', isDense: true),
            keyboardType: TextInputType.number,
            onChanged: onDeliveredChanged,
          ),
          const SizedBox(height: 6),
          TextField(
            controller: billtyController,
            decoration: const InputDecoration(labelText: 'Billty rate', isDense: true),
            keyboardType: TextInputType.number,
            onChanged: onBilltyChanged,
          ),
          const SizedBox(height: 6),
          TextField(
            controller: freightController,
            readOnly: freightReadOnly,
            decoration: InputDecoration(
              labelText: freightReadOnly ? 'Freight (included)' : 'Freight amount',
              isDense: true,
            ),
            keyboardType: TextInputType.number,
            onChanged: onFreightChanged,
          ),
        ],
      ),
    );
  }
}
