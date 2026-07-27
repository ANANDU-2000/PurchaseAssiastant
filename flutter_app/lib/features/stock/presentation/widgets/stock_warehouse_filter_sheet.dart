import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/stock_providers.dart';
import '../../../../core/design_system/hexa_responsive.dart';

int countWarehouseActiveFilters(StockListQuery q, StockOperationalFilters op) {
  var n = 0;
  if (q.subcategory.isNotEmpty) n++;
  if (q.status != 'all') n++;
  if (op.missingBarcodeOnly) n++;
  if (op.missingItemCodeOnly) n++;
  if (op.reorderOnly) n++;
  if (op.unit.isNotEmpty) n++;
  return n;
}

Future<void> showStockWarehouseFilterSheet({
  required BuildContext context,
  required WidgetRef ref,
  required TextEditingController subcategoryCtrl,
  VoidCallback? onApplied,
}) {
  return showHexaBottomSheet<void>(
    context: context,
    compact: true,
    child: _StockWarehouseFilterBody(
      parentRef: ref,
      subcategoryCtrl: subcategoryCtrl,
      onApplied: onApplied,
    ),
  );
}

class _StockWarehouseFilterBody extends ConsumerStatefulWidget {
  const _StockWarehouseFilterBody({
    required this.parentRef,
    required this.subcategoryCtrl,
    this.onApplied,
  });

  final WidgetRef parentRef;
  final TextEditingController subcategoryCtrl;
  final VoidCallback? onApplied;

  @override
  ConsumerState<_StockWarehouseFilterBody> createState() =>
      _StockWarehouseFilterBodyState();
}

class _StockWarehouseFilterBodyState
    extends ConsumerState<_StockWarehouseFilterBody> {
  late String _subcategory;
  late String _status;
  late bool _missingBarcode;
  late bool _missingCode;
  late bool _reorder;
  late String _unit;

  static const _units = ['bag', 'kg', 'box', 'tin', 'piece', 'sack'];

  @override
  void initState() {
    super.initState();
    final q = widget.parentRef.read(stockListQueryProvider);
    final op = widget.parentRef.read(stockOperationalFiltersProvider);
    _subcategory = q.subcategory;
    _status = q.status;
    _missingBarcode = op.missingBarcodeOnly;
    _missingCode = op.missingItemCodeOnly;
    _reorder = op.reorderOnly;
    _unit = op.unit;
    widget.subcategoryCtrl.text = _subcategory;
  }

  void _apply() {
    final sub = widget.subcategoryCtrl.text.trim();
    widget.parentRef.read(stockListQueryProvider.notifier).state =
        widget.parentRef.read(stockListQueryProvider).copyWith(
              subcategory: sub,
              category: '',
              supplier: '',
              status: _status,
              page: 1,
            );
    widget.parentRef.read(stockOperationalFiltersProvider.notifier).state =
        StockOperationalFilters(
      missingBarcodeOnly: _missingBarcode,
      missingItemCodeOnly: _missingCode,
      reorderOnly: _reorder,
      unit: _unit,
    );
    widget.onApplied?.call();
    Navigator.of(context).pop();
  }

  void _clear() {
    widget.subcategoryCtrl.clear();
    setState(() {
      _subcategory = '';
      _status = 'all';
      _missingBarcode = false;
      _missingCode = false;
      _reorder = false;
      _unit = '';
    });
    widget.parentRef.read(stockListQueryProvider.notifier).state =
        widget.parentRef.read(stockListQueryProvider).copyWith(
              subcategory: '',
              category: '',
              status: 'all',
              page: 1,
            );
    widget.parentRef.read(stockOperationalFiltersProvider.notifier).state =
        const StockOperationalFilters();
    widget.onApplied?.call();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
              children: [
                const Expanded(
                  child: Text(
                    'Filters',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Subcategory',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: widget.subcategoryCtrl,
              decoration: const InputDecoration(
                hintText: 'Search subcategory…',
                isDense: true,
                prefixIcon: Icon(Icons.search_rounded, size: 20),
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _subcategory = v),
            ),
            const SizedBox(height: 14),
            const Text(
              'Status',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _chip('Low', _status == 'low', () => setState(() {
                      _status = _status == 'low' ? 'all' : 'low';
                    })),
                _chip('Out', _status == 'out', () => setState(() {
                      _status = _status == 'out' ? 'all' : 'out';
                    })),
                _chip('Reorder', _reorder, () => setState(() {
                      _reorder = !_reorder;
                    })),
              ],
            ),
            const SizedBox(height: 14),
            const Text(
              'Codes',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _chip('Missing barcode', _missingBarcode, () {
                  setState(() => _missingBarcode = !_missingBarcode);
                }),
                _chip('Missing code', _missingCode, () {
                  setState(() => _missingCode = !_missingCode);
                }),
              ],
            ),
            const SizedBox(height: 14),
            const Text(
              'Unit',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final u in _units)
                  _chip(
                    u,
                    _unit.toLowerCase() == u,
                    () => setState(() {
                      _unit = _unit.toLowerCase() == u ? '' : u;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _clear,
                    child: const Text('Clear'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: _apply,
                    child: const Text('Apply'),
                  ),
                ),
              ],
            ),
          ],
        ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return FilterChip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      selected: selected,
      onSelected: (_) => onTap(),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}
