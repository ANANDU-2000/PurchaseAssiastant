import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design_system/hexa_operational_tokens.dart';
import '../../../../core/providers/catalog_providers.dart';
import '../../../../core/providers/stock_providers.dart';
import '../../../../core/providers/suppliers_list_provider.dart';

const kOperationalDesktopBreakpoint = 1100.0;

/// Opens filter UI: bottom sheet on mobile/tablet, end-aligned panel on wide desktop.
Future<void> showOperationalStockFilter({
  required BuildContext context,
  required WidgetRef ref,
  TextEditingController? subcategoryCtrl,
  bool includeSupplier = true,
}) async {
  final width = MediaQuery.sizeOf(context).width;
  if (width >= kOperationalDesktopBreakpoint) {
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Filters',
      pageBuilder: (ctx, _, __) {
        return Align(
          alignment: Alignment.centerRight,
          child: Material(
            elevation: 12,
            child: SizedBox(
              width: 320,
              height: MediaQuery.sizeOf(ctx).height,
              child: _OperationalFilterBody(
                subcategoryCtrl: subcategoryCtrl,
                includeSupplier: includeSupplier,
              ),
            ),
          ),
        );
      },
    );
    return;
  }
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.72,
      minChildSize: 0.45,
      maxChildSize: 0.92,
      builder: (_, scrollCtrl) => _OperationalFilterBody(
        subcategoryCtrl: subcategoryCtrl,
        includeSupplier: includeSupplier,
        scrollController: scrollCtrl,
      ),
    ),
  );
}

class _OperationalFilterBody extends ConsumerStatefulWidget {
  const _OperationalFilterBody({
    this.subcategoryCtrl,
    this.includeSupplier = true,
    this.scrollController,
  });

  final TextEditingController? subcategoryCtrl;
  final bool includeSupplier;
  final ScrollController? scrollController;

  @override
  ConsumerState<_OperationalFilterBody> createState() =>
      _OperationalFilterBodyState();
}

class _OperationalFilterBodyState extends ConsumerState<_OperationalFilterBody> {
  late String _status;
  late String _sort;
  late String _category;
  late String _supplier;
  late bool _missingBarcode;
  late bool _eviction;
  late String _unit;
  late final TextEditingController _subcatField;
  final _supplierSearch = TextEditingController();

  @override
  void initState() {
    super.initState();
    final q = ref.read(stockListQueryProvider);
    final op = ref.read(stockOperationalFiltersProvider);
    _status = q.status;
    _sort = q.sort;
    _category = q.category;
    _supplier = q.supplier;
    _missingBarcode = op.missingBarcodeOnly;
    _eviction = op.evictionOnly;
    _unit = op.unit;
    _subcatField = TextEditingController(
      text: widget.subcategoryCtrl?.text ?? q.subcategory,
    );
  }

  @override
  void dispose() {
    _subcatField.dispose();
    _supplierSearch.dispose();
    super.dispose();
  }

  void _apply() {
    ref.read(stockListQueryProvider.notifier).state =
        ref.read(stockListQueryProvider).copyWith(
              status: _status,
              sort: _sort,
              category: _category,
              supplier: _supplier,
              subcategory: _subcatField.text.trim(),
              page: 1,
            );
    ref.read(stockOperationalFiltersProvider.notifier).state =
        StockOperationalFilters(
          missingBarcodeOnly: _missingBarcode,
          evictionOnly: _eviction,
          unit: _unit,
        );
    widget.subcategoryCtrl?.text = _subcatField.text.trim();
    Navigator.pop(context);
  }

  void _clear() {
    ref.read(stockListQueryProvider.notifier).state = const StockListQuery();
    ref.read(stockOperationalFiltersProvider.notifier).state =
        const StockOperationalFilters();
    widget.subcategoryCtrl?.clear();
    _subcatField.clear();
    setState(() {
      _status = 'all';
      _sort = 'name';
      _category = '';
      _supplier = '';
      _missingBarcode = false;
      _eviction = false;
      _unit = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final catsAsync = ref.watch(itemCategoriesListProvider);
    final suppliersAsync = ref.watch(suppliersListProvider);

    return ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(
        HexaOp.pageGutter,
        12,
        HexaOp.pageGutter,
        24,
      ),
      children: [
        Text(
          'Filters',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                fontSize: 20,
              ),
        ),
        const SizedBox(height: 16),
        Text('Stock status', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: _status,
          decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
          items: const [
            DropdownMenuItem(value: 'all', child: Text('All')),
            DropdownMenuItem(value: 'low', child: Text('Low stock')),
            DropdownMenuItem(value: 'critical', child: Text('Critical')),
            DropdownMenuItem(value: 'out', child: Text('Out of stock')),
          ],
          onChanged: (v) => setState(() => _status = v ?? 'all'),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Missing barcode only'),
          value: _missingBarcode,
          onChanged: (v) => setState(() => _missingBarcode = v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Needs eviction only'),
          value: _eviction,
          onChanged: (v) => setState(() => _eviction = v),
        ),
        const SizedBox(height: 12),
        Text('Unit type', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: _unit.isEmpty ? '' : _unit,
          decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
          items: const [
            DropdownMenuItem(value: '', child: Text('All units')),
            DropdownMenuItem(value: 'bag', child: Text('Bag')),
            DropdownMenuItem(value: 'box', child: Text('Box')),
            DropdownMenuItem(value: 'tin', child: Text('Tin')),
            DropdownMenuItem(value: 'kg', child: Text('Kg')),
            DropdownMenuItem(value: 'piece', child: Text('Piece')),
          ],
          onChanged: (v) => setState(() => _unit = v ?? ''),
        ),
        const SizedBox(height: 12),
        catsAsync.when(
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
          data: (cats) {
            final names = [
              for (final c in cats)
                if ((c['name'] ?? '').toString().trim().isNotEmpty)
                  c['name'].toString().trim(),
            ];
            if (names.isEmpty) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Category', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _category.isEmpty ? '' : _category,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem(value: '', child: Text('All categories')),
                    for (final n in names)
                      DropdownMenuItem(value: n, child: Text(n)),
                  ],
                  onChanged: (v) => setState(() => _category = v ?? ''),
                ),
                const SizedBox(height: 12),
              ],
            );
          },
        ),
        TextField(
          controller: _subcatField,
          decoration: const InputDecoration(
            labelText: 'Subcategory',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        if (widget.includeSupplier) ...[
          const SizedBox(height: 16),
          Text('Supplier', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          suppliersAsync.when(
            loading: () => const LinearProgressIndicator(),
            error: (_, __) => const SizedBox.shrink(),
            data: (rows) {
              final names = [
                for (final s in rows)
                  if ((s['name'] ?? '').toString().trim().isNotEmpty)
                    s['name'].toString().trim(),
              ]..sort();
              return DropdownButtonFormField<String>(
                value: _supplier.isEmpty ? '' : _supplier,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  const DropdownMenuItem(value: '', child: Text('All suppliers')),
                  for (final n in names.take(120))
                    DropdownMenuItem(value: n, child: Text(n)),
                ],
                onChanged: (v) => setState(() => _supplier = v ?? ''),
              );
            },
          ),
        ],
        const SizedBox(height: 12),
        Text('Sort', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: _sort,
          decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
          items: const [
            DropdownMenuItem(value: 'name', child: Text('Name A–Z')),
            DropdownMenuItem(value: 'stock_asc', child: Text('Stock ↑')),
            DropdownMenuItem(value: 'stock_desc', child: Text('Stock ↓')),
            DropdownMenuItem(value: 'recent', child: Text('Recent')),
          ],
          onChanged: (v) => setState(() => _sort = v ?? 'name'),
        ),
        const SizedBox(height: 20),
        FilledButton(onPressed: _apply, child: const Text('Apply filters')),
        TextButton(onPressed: _clear, child: const Text('Clear all')),
      ],
    );
  }
}

String stockActiveFilterSummary(StockListQuery q, StockOperationalFilters op) {
  final parts = <String>[];
  if (q.category.isNotEmpty) parts.add(q.category);
  if (q.subcategory.isNotEmpty) parts.add(q.subcategory);
  if (q.supplier.isNotEmpty) parts.add(q.supplier);
  if (q.status == 'low') parts.add('Low stock');
  if (q.status == 'critical') parts.add('Critical');
  if (q.status == 'out') parts.add('Out of stock');
  if (op.missingBarcodeOnly) parts.add('Missing barcode');
  if (op.evictionOnly) parts.add('Eviction');
  if (op.unit.isNotEmpty) parts.add(op.unit.toUpperCase());
  if (q.sort == 'recent') parts.add('Recent');
  return parts.join(' · ');
}
