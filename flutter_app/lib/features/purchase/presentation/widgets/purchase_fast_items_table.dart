import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/calc_engine.dart';
import '../../../../core/design_system/hexa_ds_tokens.dart';
import '../../../../core/theme/hexa_colors.dart';
import '../../../../core/utils/unit_utils.dart';
import '../../domain/purchase_draft.dart';
import '../../state/purchase_draft_provider.dart';
import '../wizard/purchase_fast_items_step.dart' show OpenAdvancedItemSheet;
import 'item_entry/purchase_inline_line_builder.dart';
import 'purchase_inline_entry_row.dart';
import 'purchase_line_actions.dart';

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

/// Desktop items table — inline spreadsheet entry + display rows.
///
/// Columns: ITEM | QTY | UNIT | BUY | SELL | TAX | TOTAL | ACTIONS.
/// Common lines commit in-place; Advanced opens the full item sheet.
/// When [fillHeight] is true (voucher chrome), the body scrolls inside
/// [Expanded] so the table owns most of the viewport.
class PurchaseFastItemsTable extends ConsumerStatefulWidget {
  const PurchaseFastItemsTable({
    super.key,
    required this.onDraftChanged,
    required this.openAdvancedItemEditor,
    required this.catalog,
    this.preferredSupplierId,
    this.priorityCatalogItemIds = const [],
    this.lineJustAdded,
    this.onDismissLineJustAdded,
    this.fillHeight = false,
  });

  final VoidCallback onDraftChanged;
  final OpenAdvancedItemSheet openAdvancedItemEditor;
  final List<Map<String, dynamic>> catalog;
  final String? preferredSupplierId;
  final List<String> priorityCatalogItemIds;
  final PurchaseLineDraft? lineJustAdded;
  final VoidCallback? onDismissLineJustAdded;

  /// Parent provides bounded height (e.g. [Expanded]); rows scroll inside.
  final bool fillHeight;

  @override
  ConsumerState<PurchaseFastItemsTable> createState() =>
      _PurchaseFastItemsTableState();
}

class _PurchaseFastItemsTableState
    extends ConsumerState<PurchaseFastItemsTable> {
  /// `null` = new-row editor at bottom; otherwise editing that committed index.
  int? _editIndex;
  int _rowSession = 0;
  bool _showNewRow = true;

  Future<void> _confirmClearAll() async {
    await clearPurchaseLinesWithConfirm(
      context: context,
      ref: ref,
      onDraftChanged: widget.onDraftChanged,
    );
    if (mounted) {
      setState(() {
        _editIndex = null;
        _showNewRow = true;
        _rowSession++;
      });
    }
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
    if (_editIndex == i) {
      setState(() {
        _editIndex = null;
        _showNewRow = true;
        _rowSession++;
      });
    } else if (_editIndex != null && _editIndex! > i) {
      setState(() => _editIndex = _editIndex! - 1);
    }
  }

  void _startEdit(int i) {
    setState(() {
      _editIndex = i;
      _showNewRow = false;
      _rowSession++;
    });
  }

  void _startNewRow() {
    setState(() {
      _editIndex = null;
      _showNewRow = true;
      _rowSession++;
    });
  }

  void _cancelInline() {
    setState(() {
      _editIndex = null;
      _showNewRow = true;
      _rowSession++;
    });
  }

  void _commitInline(Map<String, dynamic> lineMap) {
    final draft = PurchaseLineDraft.fromLineMap(lineMap);
    final editAt = _editIndex;
    ref.read(purchaseDraftProvider.notifier).addOrReplaceLine(
          draft,
          editIndex: editAt,
        );
    widget.onDraftChanged();
    if (!mounted) return;
    setState(() {
      _editIndex = null;
      _showNewRow = true;
      _rowSession++;
    });
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          editAt != null ? 'Item updated' : 'Added ${draft.itemName}',
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lines = ref.watch(purchaseDraftProvider.select((d) => d.lines));
    final supplierId =
        ref.watch(purchaseDraftProvider.select((d) => d.supplierId));
    final blocked = supplierId == null || supplierId.isEmpty;
    final searchItems = buildPurchaseCatalogSearchItems(
      widget.catalog,
      preferredSupplierId: widget.preferredSupplierId ?? supplierId,
      priorityCatalogItemIds: widget.priorityCatalogItemIds,
    );

    final titleRow = Row(
      children: [
        Text(
          'Items (${lines.length})',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w900,
                color: HexaColors.textOnLightSurface,
                fontSize: widget.fillHeight ? 13 : null,
              ),
        ),
        const Spacer(),
        if (lines.isNotEmpty)
          TextButton(
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: blocked ? null : _confirmClearAll,
            child: const Text('Clear all'),
          ),
      ],
    );

    final rows = <Widget>[
      if (lines.isEmpty && (blocked || !_showNewRow))
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            blocked
                ? 'Pick a supplier first so catalog links and rates work.'
                : 'No items yet — add a row below.',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: blocked ? Colors.orange.shade900 : HexaColors.slate400,
              fontSize: 13,
            ),
          ),
        ),
      for (var i = 0; i < lines.length; i++) ...[
        if (_editIndex == i)
          KeyedSubtree(
            key: ValueKey('edit-$_rowSession-$i'),
            child: PurchaseInlineEntryRow(
              catalog: widget.catalog,
              searchItems: searchItems,
              initial: lines[i],
              preferredSupplierId: widget.preferredSupplierId ?? supplierId,
              onCommit: _commitInline,
              onCancel: _cancelInline,
              onOpenAdvanced: () async {
                final idx = i;
                _cancelInline();
                await widget.openAdvancedItemEditor(editIndex: idx);
              },
            ),
          )
        else
          _DesktopDisplayRow(
            key: ValueKey('${lines[i].catalogItemId ?? ''}#$i'),
            line: lines[i],
            onEdit: blocked ? null : () => _startEdit(i),
            onRemove: () => _removeAt(i),
            onAdvanced: () => widget.openAdvancedItemEditor(editIndex: i),
          ),
        const Divider(height: 1),
      ],
      if (!blocked && _showNewRow && _editIndex == null) ...[
        KeyedSubtree(
          key: ValueKey('new-$_rowSession'),
          child: PurchaseInlineEntryRow(
            catalog: widget.catalog,
            searchItems: searchItems,
            preferredSupplierId: widget.preferredSupplierId ?? supplierId,
            autofocusItem: lines.isNotEmpty || _rowSession > 0,
            onCommit: _commitInline,
            onCancel: () {
              setState(() => _rowSession++);
            },
            onOpenAdvanced: () async {
              await widget.openAdvancedItemEditor();
              if (mounted) _startNewRow();
            },
          ),
        ),
        const Divider(height: 1),
      ],
      const SizedBox(height: 4),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          style: TextButton.styleFrom(
            visualDensity: VisualDensity.compact,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onPressed: blocked
              ? null
              : () {
                  if (_editIndex != null) {
                    _cancelInline();
                  } else {
                    _startNewRow();
                  }
                },
          icon: const Icon(Icons.add, size: 18),
          label: const Text(
            '+ Add row',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
          ),
        ),
      ),
    ];

    final chrome = <Widget>[
      if (blocked)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            'Pick a supplier above to add catalog lines.',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: Colors.orange.shade900,
              fontSize: 12,
            ),
          ),
        ),
      if (widget.lineJustAdded != null) ...[
        _LineAddedBanner(
          line: widget.lineJustAdded!,
          onDismiss: widget.onDismissLineJustAdded,
        ),
        const SizedBox(height: 6),
      ],
      titleRow,
      const Divider(height: 10),
      _ColumnHeaderRow(),
      const SizedBox(height: 2),
    ];

    if (widget.fillHeight) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ...chrome,
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              keyboardDismissBehavior:
                  ScrollViewKeyboardDismissBehavior.manual,
              children: rows,
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...chrome,
        ...rows,
      ],
    );
  }
}

class _ColumnHeaderRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w800,
      color: HexaColors.slate400,
      letterSpacing: 0.2,
    );
    Widget h(String t, {int flex = 1, TextAlign align = TextAlign.left}) =>
        Expanded(
          flex: flex,
          child: Text(t, style: style, textAlign: align, maxLines: 1),
        );
    return Row(
      children: [
        h('ITEM', flex: 4),
        h('QTY', flex: 2, align: TextAlign.right),
        h('UNIT', flex: 2, align: TextAlign.right),
        h('BUY ₹', flex: 2, align: TextAlign.right),
        h('SELL ₹', flex: 2, align: TextAlign.right),
        h('GST', flex: 2, align: TextAlign.right),
        h('TOTAL', flex: 2, align: TextAlign.right),
        const SizedBox(width: 72, child: Text('')),
      ],
    );
  }
}

class _DesktopDisplayRow extends StatelessWidget {
  const _DesktopDisplayRow({
    super.key,
    required this.line,
    required this.onRemove,
    this.onEdit,
    this.onAdvanced,
  });

  final PurchaseLineDraft line;
  final VoidCallback? onEdit;
  final VoidCallback onRemove;
  final VoidCallback? onAdvanced;

  @override
  Widget build(BuildContext context) {
    final li = _lineToCalc(line);
    final total = lineMoney(li) + lineItemFreightCharges(li);
    final qty = formatStockQtyForUnit(line.unit, line.qty);
    final tax = line.taxPercent ?? 0;
    final taxLabel = tax <= 0
        ? 'Nil'
        : '${tax.toStringAsFixed(tax == tax.roundToDouble() ? 0 : 1)}%';

    TextStyle cell({bool bold = false, double size = 13}) => TextStyle(
          fontSize: size,
          fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
          color: HexaColors.textOnLightSurface,
        );

    return InkWell(
      onTap: onEdit,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                flex: 4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      line.itemName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: cell(bold: true),
                    ),
                    if (line.hsnCode != null &&
                        line.hsnCode!.trim().isNotEmpty)
                      Text(
                        'HSN ${line.hsnCode}',
                        style: TextStyle(
                          fontSize: 10,
                          color: HexaColors.slate400,
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  qty,
                  textAlign: TextAlign.right,
                  style: cell(),
                  maxLines: 1,
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  line.unit.toUpperCase(),
                  textAlign: TextAlign.right,
                  style: cell(size: 12),
                  maxLines: 1,
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  line.landingCost > 0 ? _inr2(line.landingCost) : '—',
                  textAlign: TextAlign.right,
                  style: cell(),
                  maxLines: 1,
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  (line.sellingPrice ?? 0) > 0
                      ? _inr2(line.sellingPrice!)
                      : '—',
                  textAlign: TextAlign.right,
                  style: cell(),
                  maxLines: 1,
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  taxLabel,
                  textAlign: TextAlign.right,
                  style: cell(size: 12),
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
                      tooltip: 'Remove',
                      icon: const Icon(Icons.close_rounded, size: 18),
                      visualDensity: VisualDensity.compact,
                      onPressed: onRemove,
                    ),
                    if (onAdvanced != null)
                      PopupMenuButton<String>(
                        tooltip: 'More',
                        padding: EdgeInsets.zero,
                        onSelected: (v) {
                          if (v == 'advanced') onAdvanced?.call();
                          if (v == 'edit') onEdit?.call();
                          if (v == 'remove') onRemove();
                        },
                        itemBuilder: (ctx) => const [
                          PopupMenuItem(
                            value: 'edit',
                            child: Text('Edit inline'),
                          ),
                          PopupMenuItem(
                            value: 'advanced',
                            child: Text('Advanced…'),
                          ),
                          PopupMenuItem(
                            value: 'remove',
                            child: Text('Remove'),
                          ),
                        ],
                        child: const Icon(Icons.more_vert, size: 18),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LineAddedBanner extends StatelessWidget {
  const _LineAddedBanner({required this.line, this.onDismiss});

  final PurchaseLineDraft line;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: HexaDsColors.successSurface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Row(
          children: [
            const Icon(Icons.check_circle_rounded,
                color: HexaDsColors.successForeground, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Added ${line.itemName}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: HexaDsColors.successForeground,
                ),
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close_rounded, size: 18),
              onPressed: onDismiss,
            ),
          ],
        ),
      ),
    );
  }
}
