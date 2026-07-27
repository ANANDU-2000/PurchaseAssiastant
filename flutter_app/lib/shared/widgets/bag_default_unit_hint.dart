import 'package:flutter/material.dart';

double? parseOptionalKgPerBag(String s) {
  final t = s.trim();
  if (t.isEmpty) return null;
  final v = double.tryParse(t);
  if (v == null || v <= 0) return null;
  return v;
}

/// Shown when catalog default unit is **bag** — kg/bag is entered on purchase lines;
/// a default weight can be stored on a **variant** from the item detail screen.
class BagDefaultUnitHint extends StatelessWidget {
  const BagDefaultUnitHint({super.key, required this.kgAlreadySet});

  final bool kgAlreadySet;

  @override
  Widget build(BuildContext context) {
    if (kgAlreadySet) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline_rounded, size: 20, color: cs.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Used when you pick this item on a purchase. Optional: set kg/bag above.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      height: 1.35,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
