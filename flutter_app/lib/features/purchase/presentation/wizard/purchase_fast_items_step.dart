import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/strict_decimal.dart';
import '../../../../core/theme/hexa_colors.dart';
import '../../domain/purchase_draft.dart';
import '../../state/purchase_draft_provider.dart';

String _inr0(num n) =>
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0)
        .format(n);

typedef OpenAdvancedItemSheet = Future<void> Function({
  int? editIndex,
  Map<String, dynamic>? initialOverride,
});

/// Items step — list + advanced sheet only (no inline quick-add row).
class PurchaseFastItemsStep extends ConsumerStatefulWidget {
  const PurchaseFastItemsStep({
    super.key,
    required this.onDraftChanged,
    required this.openAdvancedItemEditor,
  });

  final VoidCallback onDraftChanged;
  final OpenAdvancedItemSheet openAdvancedItemEditor;

  @override
  ConsumerState<PurchaseFastItemsStep> createState() =>
      _PurchaseFastItemsStepState();
}

class _PurchaseFastItemsStepState extends ConsumerState<PurchaseFastItemsStep> {
  void _removeAt(int i) {
    ref.read(purchaseDraftProvider.notifier).removeLineAt(i);
    widget.onDraftChanged();
    setState(() {});
  }

  Future<void> _confirmClearAll() async {
    final ok = await showCupertinoDialog<bool>(
          context: context,
          builder: (ctx) => CupertinoAlertDialog(
            title: const Text('Clear all items?'),
            content: const Text(
              'This removes every line from this purchase.',
            ),
            actions: [
              CupertinoDialogAction(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              CupertinoDialogAction(
                isDestructiveAction: true,
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Clear all'),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok || !mounted) return;
    ref.read(purchaseDraftProvider.notifier).setLinesFromMaps([]);
    widget.onDraftChanged();
    setState(() {});
  }

  double _approxLinePurchase(PurchaseLineDraft l) {
    final kpu = l.kgPerUnit;
    final pk = l.landingCostPerKg;
    if (kpu != null && pk != null && kpu > 0 && pk > 0) {
      return l.qty * kpu * pk;
    }
    return l.qty * l.landingCost;
  }

  String _qtyHuman(PurchaseLineDraft l) {
    final u = l.unit.trim();
    final q = StrictDecimal.fromObject(l.qty).format(3, trim: true);
    final ul = u.toLowerCase();
    if (l.kgPerUnit != null &&
        l.kgPerUnit! > 0 &&
        (ul == 'bag' || ul == 'sack')) {
      final kg = l.qty * l.kgPerUnit!;
      return '$q $u • ${StrictDecimal.fromObject(kg).format(3, trim: true)} kg';
    }
    return '$q $u';
  }

  Future<void> _editAdvanced(int i) async {
    await widget.openAdvancedItemEditor(editIndex: i);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final lines =
        ref.watch(purchaseDraftProvider.select((d) => d.lines));
    final supplierId =
        ref.watch(purchaseDraftProvider.select((d) => d.supplierId));
    final blocked = supplierId == null || supplierId.isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (blocked)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              'Pick a supplier on the previous step to add catalog lines.',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.orange.shade900,
                fontSize: 13,
              ),
            ),
          ),
        Consumer(
          builder: (cx, rf, _) {
            final bd = rf.watch(purchaseStrictBreakdownProvider);
            final qt = rf.watch(purchaseQuantityTotalsProvider);
            final unitBits = <String>[];
            qt.qtyByUnit.forEach((k, v) {
              if (v > 1e-9) {
                unitBits.add(
                  '${StrictDecimal.fromObject(v).format(3, trim: true)} ${k.toUpperCase()}',
                );
              }
            });
            if (qt.totalKg > 1e-6) {
              unitBits.insert(0, '${qt.totalKg.toStringAsFixed(0)} KG');
            }
            final qtyLine = unitBits.isEmpty ? '—' : unitBits.join(' • ');
            return Material(
              color: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: HexaColors.brandBorder),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'TOTAL',
                      style: Theme.of(cx).textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: Colors.black54,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _inr0(bd.grand),
                      style: Theme.of(cx).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFF0F172A),
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      qtyLine,
                      style: Theme.of(cx).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFF0F172A),
                          ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Text(
              'Items (${lines.length})',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF0F172A),
                  ),
            ),
            const Spacer(),
            TextButton(
              onPressed: blocked || lines.isEmpty ? null : _confirmClearAll,
              child: const Text('Clear all'),
            ),
          ],
        ),
        const Divider(height: 16),
        if (lines.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Text(
              blocked
                  ? 'Supplier required for catalog links.'
                  : 'No items yet. Tap Add item below.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[700], fontSize: 14),
            ),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            itemCount: lines.length,
            itemBuilder: (ctx, i) {
              final ln = lines[i];
              final buy = _approxLinePurchase(ln);
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Material(
                  color: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(color: Colors.grey.shade300),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => _editAdvanced(i),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${i + 1}.',
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  ln.itemName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 16,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _qtyHuman(ln),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _inr0(buy),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 17,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Remove',
                            icon: const Icon(Icons.delete_outline_rounded),
                            onPressed: () => _removeAt(i),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        SizedBox(
          height: 52,
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: blocked
                ? null
                : () => widget.openAdvancedItemEditor(),
            icon: const Icon(Icons.add_circle_outline_rounded, size: 22),
            label: const Text(
              '+ Add Item',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
            ),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              side: const BorderSide(color: HexaColors.brandPrimary, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}
