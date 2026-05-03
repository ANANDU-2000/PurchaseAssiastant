import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/strict_decimal.dart';
import '../../../../core/theme/hexa_colors.dart';
import '../../domain/purchase_draft.dart';
import '../../state/purchase_draft_provider.dart';

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

  double? _approxLineSell(PurchaseLineDraft l) {
    final sp = l.sellingPrice;
    if (sp == null || sp <= 0) return null;
    return sp * l.qty;
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
        Row(
          children: [
            Text(
              'Items (${lines.length})',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const Spacer(),
            TextButton(
              onPressed: blocked || lines.isEmpty ? null : _confirmClearAll,
              child: const Text('Reset row'),
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
              final sellTot = _approxLineSell(ln);
              final subtitle = sellTot != null
                  ? '${StrictDecimal.fromObject(ln.qty).format(3, trim: true)} ${ln.unit} · est. buy ₹${buy.toStringAsFixed(2)} · est. sell ₹${sellTot.toStringAsFixed(2)}'
                  : '${StrictDecimal.fromObject(ln.qty).format(3, trim: true)} ${ln.unit} · est. buy ₹${buy.toStringAsFixed(2)}';
              return Card(
                margin: const EdgeInsets.only(bottom: 6),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(color: Colors.grey.shade300),
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor:
                        HexaColors.brandPrimary.withValues(alpha: 0.1),
                    foregroundColor: HexaColors.brandPrimary,
                    child: Text(
                      '${i + 1}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  title: Text(
                    ln.itemName,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(subtitle),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Edit',
                        icon: const Icon(Icons.tune_rounded),
                        onPressed: () => _editAdvanced(i),
                      ),
                      IconButton(
                        tooltip: 'Remove',
                        icon: const Icon(Icons.delete_outline_rounded),
                        onPressed: () => _removeAt(i),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        if (lines.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 16),
            child: Consumer(
              builder: (cx, rf, _) {
                final bd = rf.watch(purchaseStrictBreakdownProvider);
                final qt = rf.watch(purchaseQuantityTotalsProvider);
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFECFEFF),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: HexaColors.brandPrimary.withValues(alpha: 0.22),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Total qty',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            qt.totalKg > 1e-6
                                ? '${qt.totalKg.toStringAsFixed(2)} kg'
                                : '${lines.fold<double>(0, (a, l) => a + l.qty).toStringAsFixed(0)} units',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'P: est. payable',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            '₹${bd.grand.toStringAsFixed(2)}',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 15,
                              color: HexaColors.brandPrimary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        SizedBox(
          height: 52,
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: blocked
                ? null
                : () => widget.openAdvancedItemEditor(),
            icon: const Icon(Icons.add_circle_outline_rounded),
            label: const Text(
              'Add item',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              side: BorderSide(color: HexaColors.brandPrimary),
            ),
          ),
        ),
      ],
    );
  }
}
