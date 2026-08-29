import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/calc_engine.dart';
import '../../../../core/theme/hexa_colors.dart';
import '../../../../core/utils/unit_utils.dart';
import '../../domain/purchase_draft.dart';
import '../../state/purchase_draft_provider.dart';
import '../widgets/purchase_line_actions.dart';
import '../wizard/purchase_fast_items_step.dart' show OpenAdvancedItemSheet;

final _inrFmt = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);
String _inr2(num n) => _inrFmt.format(n);

TradeCalcLine _lineToCalc(PurchaseLineDraft l) => TradeCalcLine(
      qty: l.qty,
      landingCost: l.landingCost,
      kgPerUnit: l.kgPerUnit,
      landingCostPerKg: l.landingCostPerKg,
      taxPercent: l.taxPercent,
      discountPercent: l.lineDiscountPercent,
      freightType: l.freightType,
      freightValue: l.freightValue,
      deliveredRate: l.deliveredRate,
      billtyRate: l.billtyRate,
    );

/// Tablet (600–1023) compact transaction list — not the 9-col desktop table.
class PurchaseTabletItemList extends ConsumerStatefulWidget {
  const PurchaseTabletItemList({
    super.key,
    required this.onDraftChanged,
    required this.openAdvancedItemEditor,
    this.lineJustAdded,
    this.onDismissLineJustAdded,
  });

  final VoidCallback onDraftChanged;
  final OpenAdvancedItemSheet openAdvancedItemEditor;
  final PurchaseLineDraft? lineJustAdded;
  final VoidCallback? onDismissLineJustAdded;

  @override
  ConsumerState<PurchaseTabletItemList> createState() =>
      _PurchaseTabletItemListState();
}

class _PurchaseTabletItemListState
    extends ConsumerState<PurchaseTabletItemList> {
  Future<void> _confirmClearAll() async {
    await clearPurchaseLinesWithConfirm(
      context: context,
      ref: ref,
      onDraftChanged: widget.onDraftChanged,
    );
  }

  void _removeAt(int i) {
    final line = ref.read(purchaseDraftProvider).lines[i];
    removePurchaseLineWithUndo(
      context: context,
      ref: ref,
      index: i,
      line: line,
      onDraftChanged: widget.onDraftChanged,
    );
  }

  @override
  Widget build(BuildContext context) {
    final lines = ref.watch(purchaseDraftProvider.select((d) => d.lines));
    final supplierId =
        ref.watch(purchaseDraftProvider.select((d) => d.supplierId));
    final blocked = supplierId == null || supplierId.isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (blocked)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              'Pick a supplier above to add catalog lines.',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.orange.shade900,
                fontSize: 13,
              ),
            ),
          ),
        if (widget.lineJustAdded != null) ...[
          Material(
            color: HexaColors.skySoft,
            borderRadius: BorderRadius.circular(8),
            child: ListTile(
              dense: true,
              title: Text(
                'Added ${widget.lineJustAdded!.itemName}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              trailing: IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: widget.onDismissLineJustAdded,
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
        Row(
          children: [
            Text(
              'Items (${lines.length})',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: HexaColors.textOnLightSurface,
                  ),
            ),
            const Spacer(),
            if (lines.isNotEmpty)
              TextButton(
                onPressed: blocked ? null : _confirmClearAll,
                child: const Text('Clear all'),
              ),
          ],
        ),
        const Divider(height: 16),
        _HeaderRow(),
        const SizedBox(height: 4),
        if (lines.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              blocked
                  ? 'Pick a supplier first so catalog links and rates work.'
                  : 'No items yet — add a row below.',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: blocked
                    ? Colors.orange.shade900
                    : HexaColors.slate400,
                fontSize: 13,
              ),
            ),
          )
        else
          for (var i = 0; i < lines.length; i++) ...[
            _TabletLineRow(
              line: lines[i],
              onEdit: () => widget.openAdvancedItemEditor(editIndex: i),
              onRemove: () => _removeAt(i),
            ),
            const Divider(height: 1),
          ],
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: blocked ? null : () => widget.openAdvancedItemEditor(),
            icon: const Icon(Icons.add, size: 18),
            label: const Text(
              '+ Add row',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
            ),
          ),
        ),
      ],
    );
  }
}

class _HeaderRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: 10,
      fontWeight: FontWeight.w800,
      color: HexaColors.slate400,
      letterSpacing: 0.3,
    );
    Widget h(String t, {int flex = 1, TextAlign align = TextAlign.left}) =>
        Expanded(
          flex: flex,
          child: Text(t, style: style, textAlign: align, maxLines: 1),
        );
    return Row(
      children: [
        h('ITEM', flex: 3),
        h('QTY / UNIT', flex: 2),
        h('BUY', align: TextAlign.right),
        h('SELL', align: TextAlign.right),
        h('TAX', align: TextAlign.right),
        h('TOTAL', flex: 2, align: TextAlign.right),
        const SizedBox(width: 72),
      ],
    );
  }
}

class _TabletLineRow extends StatelessWidget {
  const _TabletLineRow({
    required this.line,
    required this.onEdit,
    required this.onRemove,
  });

  final PurchaseLineDraft line;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final li = _lineToCalc(line);
    final total = lineMoney(li) + lineItemFreightCharges(li);
    final qty = formatStockQtyForUnit(line.unit, line.qty);
    final tax = line.taxPercent ?? 0;
    final taxLabel = tax > 0 ? '${tax.toStringAsFixed(tax == tax.roundToDouble() ? 0 : 1)}%' : '—';

    TextStyle cell({bool bold = false}) => TextStyle(
          fontSize: 12,
          fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
          color: HexaColors.textOnLightSurface,
        );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  line.itemName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: cell(bold: true),
                ),
                if (line.hsnCode != null && line.hsnCode!.trim().isNotEmpty)
                  Text(
                    'HSN ${line.hsnCode}',
                    style: TextStyle(fontSize: 10, color: HexaColors.slate400),
                  ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text('$qty ${line.unit}', style: cell(), maxLines: 1),
          ),
          Expanded(
            child: Text(
              line.landingCost > 0 ? _inr2(line.landingCost) : '—',
              textAlign: TextAlign.right,
              style: cell(),
              maxLines: 1,
            ),
          ),
          Expanded(
            child: Text(
              (line.sellingPrice ?? 0) > 0 ? _inr2(line.sellingPrice!) : '—',
              textAlign: TextAlign.right,
              style: cell(),
              maxLines: 1,
            ),
          ),
          Expanded(
            child: Text(
              taxLabel,
              textAlign: TextAlign.right,
              style: cell(),
              maxLines: 1,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              _inr2(total),
              textAlign: TextAlign.right,
              style: cell(bold: true),
              maxLines: 1,
            ),
          ),
          SizedBox(
            width: 72,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Edit',
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  onPressed: onEdit,
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Remove',
                  icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade700),
                  onPressed: onRemove,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
