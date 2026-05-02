import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/calc_engine.dart';
import '../../../../core/strict_decimal.dart';
import '../../../../core/theme/hexa_colors.dart';
import '../../domain/purchase_draft.dart';
import '../../state/purchase_draft_provider.dart';
import 'purchase_wizard_shared.dart' show kPurchaseFieldHeight;

typedef OpenItemEditor = Future<void> Function({
  int? editIndex,
  Map<String, dynamic>? initialOverride,
});

class PurchaseItemsStep extends ConsumerStatefulWidget {
  const PurchaseItemsStep({
    super.key,
    required this.onOpenItem,
    required this.fetchSupplierHistoryHints,
    required this.hexaBusinessIdOrNull,
  });

  final OpenItemEditor onOpenItem;
  final Future<List<String>> Function(String businessId, Set<String> cids)?
      fetchSupplierHistoryHints;
  final String? hexaBusinessIdOrNull;

  @override
  ConsumerState<PurchaseItemsStep> createState() => _PurchaseItemsStepState();
}

class _PurchaseItemsStepState extends ConsumerState<PurchaseItemsStep> {
  String? _histKey;
  Future<List<String>>? _histFut;

  @override
  Widget build(BuildContext context) {
    final supplierId =
        ref.watch(purchaseDraftProvider.select((d) => d.supplierId));
    final lines = ref.watch(purchaseDraftProvider.select((d) => d.lines));
    final draft = ref.watch(purchaseDraftProvider);
    final cids = draft.lines
        .map((l) => l.catalogItemId)
        .whereType<String>()
        .where((s) => s.isNotEmpty)
        .toList()
      ..sort();
    final histKey = cids.join('|');
    final bid = widget.hexaBusinessIdOrNull;
    if (histKey != _histKey) {
      _histKey = histKey;
      if (bid != null &&
          histKey.isNotEmpty &&
          widget.fetchSupplierHistoryHints != null) {
        _histFut = widget.fetchSupplierHistoryHints!(bid, cids.toSet());
      } else {
        _histFut = null;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 0, 0, 6),
          child: Row(
            children: [
              Text(
                'Items',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: supplierId == null || supplierId.isEmpty
                    ? null
                    : () => widget.onOpenItem(),
                style: TextButton.styleFrom(
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                ),
                icon: const Icon(Icons.add, size: 20),
                label: const Text('Add'),
              ),
            ],
          ),
        ),
        if (bid != null && histKey.isNotEmpty && _histFut != null)
          FutureBuilder<List<String>>(
            future: _histFut,
            builder: (context, snap) {
              if (snap.hasData && (snap.data?.isNotEmpty ?? false)) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    'From history: ${snap.data!.join(" · ")}',
                    style: TextStyle(color: Colors.grey[700], fontSize: 12),
                  ),
                );
              }
              return const SizedBox.shrink();
            },
          ),
        Expanded(
          child: lines.isEmpty
              ? Center(
                  child: Text(
                    supplierId == null || supplierId.isEmpty
                        ? 'Select supplier on the previous step.'
                        : 'No items yet. Tap Add item below.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey[700], fontSize: 14),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 12),
                  itemCount: lines.length,
                  itemBuilder: (ctx, i) =>
                      _lineTile(ref, lines[i], i, widget.onOpenItem),
                ),
        ),
      ],
    );
  }

  static Widget _lineTile(
    WidgetRef ref,
    PurchaseLineDraft it,
    int i,
    OpenItemEditor onOpenItem,
  ) {
    final line = TradeCalcLine(
      qty: it.qty,
      landingCost: it.landingCost,
      kgPerUnit: it.kgPerUnit,
      landingCostPerKg: it.landingCostPerKg,
      taxPercent: it.taxPercent,
      discountPercent: it.lineDiscountPercent,
    );
    final total = lineMoney(line);
    final kpu = it.kgPerUnit;
    final lck = it.landingCostPerKg;
    final rateUnit = (kpu != null && lck != null && kpu > 0 && lck > 0)
        ? (kpu * lck)
        : it.landingCost;
    final qtyStr = StrictDecimal.fromObject(it.qty).format(3, trim: true);
    final lineText =
        '$qtyStr × ₹${rateUnit.toStringAsFixed(2)} = ₹${total.toStringAsFixed(2)} · ${it.unit.trim()}';
    const h = kPurchaseFieldHeight;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => onOpenItem(editIndex: i),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        it.itemName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        lineText,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[800],
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Edit',
                  iconSize: 22,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minHeight: h, minWidth: h),
                  icon: const Icon(Icons.edit_outlined, color: HexaColors.brandPrimary),
                  onPressed: () => onOpenItem(editIndex: i),
                ),
                IconButton(
                  tooltip: 'Remove',
                  iconSize: 22,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minHeight: h, minWidth: h),
                  icon: Icon(Icons.delete_outline_rounded, color: Colors.red[700]),
                  onPressed: () {
                    ref.read(purchaseDraftProvider.notifier).removeLineAt(i);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
