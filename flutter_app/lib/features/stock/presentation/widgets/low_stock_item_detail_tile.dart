import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/json_coerce.dart';
import '../../../../core/utils/unit_utils.dart';

/// BAG / TIN / BOX / KG display columns for a stock row.
class LowStockUnitGrid extends StatelessWidget {
  const LowStockUnitGrid({super.key, required this.item});

  final Map<String, dynamic> item;

  static String? _qtyForColumn(Map<String, dynamic> item, String column) {
    final unit =
        (item['stock_unit'] ?? item['unit'] ?? '').toString().trim().toLowerCase();
    final stock = coerceToDouble(item['current_stock']);
    final kg = coerceToDoubleNullable(item['current_stock_kg']);

    switch (column) {
      case 'kg':
        if (kg != null && kg > 0) return formatStockQtyNumber(kg);
        return null;
      case 'bag':
        if (unit.contains('bag') || unit == 'sack') {
          return formatStockQtyNumber(stock);
        }
        return null;
      case 'tin':
        if (unit.contains('tin')) return formatStockQtyNumber(stock);
        return null;
      case 'box':
        if (unit.contains('box')) return formatStockQtyNumber(stock);
        return null;
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    const cols = ['BAG', 'TIN', 'BOX', 'KG'];
    final keys = ['bag', 'tin', 'box', 'kg'];
    return Row(
      children: [
        for (var i = 0; i < cols.length; i++)
          Expanded(
            child: _UnitCell(
              label: cols[i],
              value: _qtyForColumn(item, keys[i]) ?? '—',
            ),
          ),
      ],
    );
  }
}

class _UnitCell extends StatelessWidget {
  const _UnitCell({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              color: Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: value == '—'
                    ? const Color(0xFF94A3B8)
                    : const Color(0xFFDC2626),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Expandable item tile with unit grid, stock progress, and role actions.
class LowStockItemDetailTile extends StatefulWidget {
  const LowStockItemDetailTile({
    super.key,
    required this.item,
    required this.staffMode,
    this.onOrderNow,
    this.onNotifyOwner,
    this.onEditReorder,
    this.onStockUpdate,
    this.onReceive,
  });

  final Map<String, dynamic> item;
  final bool staffMode;
  final void Function(Map<String, dynamic> item)? onOrderNow;
  final void Function(Map<String, dynamic> item)? onNotifyOwner;
  final void Function(Map<String, dynamic> item)? onEditReorder;
  final void Function(Map<String, dynamic> item)? onStockUpdate;
  final void Function(Map<String, dynamic> item)? onReceive;

  @override
  State<LowStockItemDetailTile> createState() => _LowStockItemDetailTileState();
}

class _LowStockItemDetailTileState extends State<LowStockItemDetailTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final name = item['name']?.toString() ?? '—';
    final system = coerceToDouble(item['current_stock']);
    final purchased = coerceToDouble(item['period_purchased_qty']);
    final physicalRaw = item['physical_stock_qty'];
    final physical = physicalRaw == null
        ? system
        : coerceToDouble(physicalRaw);
    final pendingDel = coerceToDoubleNullable(item['pending_delivery_qty']) ?? 0;
    final pending = item['has_pending_order'] == true;
    final pendingDays = (item['pending_order_days'] as num?)?.toInt();
    final unit =
        item['stock_unit']?.toString() ?? item['unit']?.toString() ?? '';
    final unitUp = unit.trim().isEmpty ? '' : unit.toUpperCase();
    final id = item['id']?.toString() ?? '';
    final showReceive = pending &&
        (item['last_purchase_delivered'] == false ||
            pendingDel > 0.001);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: const Border(
            left: BorderSide(color: Color(0xFFDC2626), width: 3),
          ),
          color: const Color(0xFFFFF5F5),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      Icon(
                        _expanded
                            ? Icons.expand_less_rounded
                            : Icons.expand_more_rounded,
                        size: 20,
                      ),
                    ],
                  ),
                  if (_expanded) ...[
                    const SizedBox(height: 8),
                    LowStockUnitGrid(item: item),
                    const SizedBox(height: 8),
                    Text(
                      'Stock progress · Sys ${formatStockQtyNumber(system)}'
                      '${unitUp.isNotEmpty ? ' $unitUp' : ''}'
                      ' · Bought ${formatStockQtyNumber(purchased)}'
                      ' · Phys ${formatStockQtyNumber(physical)}'
                      '${pendingDel > 0.001 ? ' · Pend del ${formatStockQtyNumber(pendingDel)}' : ''}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF64748B),
                      ),
                    ),
                    if (pending)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Chip(
                          visualDensity: VisualDensity.compact,
                          avatar: const Icon(
                            Icons.local_shipping_rounded,
                            size: 16,
                          ),
                          label: Text(
                            pendingDays != null
                                ? 'Ordered · $pendingDays d ago'
                                : 'Ordered · pending',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        if (!widget.staffMode && widget.onOrderNow != null)
                          FilledButton.tonalIcon(
                            style: FilledButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                            ),
                            onPressed: () => widget.onOrderNow!(item),
                            icon: const Icon(Icons.shopping_cart_outlined, size: 18),
                            label: const Text('Order now'),
                          ),
                        if (widget.onEditReorder != null)
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                            ),
                            onPressed: () => widget.onEditReorder!(item),
                            icon: const Icon(Icons.tune_rounded, size: 18),
                            label: const Text('Reorder level'),
                          ),
                        if (widget.onStockUpdate != null)
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                            ),
                            onPressed: () => widget.onStockUpdate!(item),
                            icon: const Icon(Icons.inventory_2_outlined, size: 18),
                            label: const Text('Stock update'),
                          ),
                        if (widget.staffMode && widget.onNotifyOwner != null)
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                            ),
                            onPressed: () => widget.onNotifyOwner!(item),
                            icon: const Icon(
                              Icons.notifications_active_outlined,
                              size: 18,
                            ),
                            label: const Text('Inform owner'),
                          ),
                        if (showReceive && widget.onReceive != null)
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                            ),
                            onPressed: () => widget.onReceive!(item),
                            icon: const Icon(Icons.local_shipping_outlined, size: 18),
                            label: const Text('Receive'),
                          ),
                        if (id.isNotEmpty)
                          TextButton(
                            onPressed: () => context.push('/catalog/items/$id'),
                            child: const Text('Open item'),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
