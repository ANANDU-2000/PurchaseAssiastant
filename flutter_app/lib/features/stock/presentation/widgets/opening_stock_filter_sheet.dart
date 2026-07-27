import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design_system/hexa_ds_tokens.dart';
import '../../../../core/design_system/hexa_responsive.dart';
import '../../../../core/providers/stock_providers.dart';
import '../../../../core/providers/suppliers_list_provider.dart';
import '../../../../shared/widgets/inline_search_field.dart';

/// Opens advanced opening-stock filters modal.
Future<void> showOpeningStockFilters({
  required BuildContext context,
  required WidgetRef ref,
}) async {
  await showHexaBottomSheet<void>(
    context: context,
    compact: true,
    child: const _OpeningStockFilterBody(),
  );
}

class _OpeningStockFilterBody extends ConsumerStatefulWidget {
  const _OpeningStockFilterBody();

  @override
  ConsumerState<_OpeningStockFilterBody> createState() =>
      _OpeningStockFilterBodyState();
}

class _OpeningStockFilterBodyState
    extends ConsumerState<_OpeningStockFilterBody> {
  final _categoryCtrl = TextEditingController();
  final _subcategoryCtrl = TextEditingController();
  final _updatedByCtrl = TextEditingController();

  InlineSearchItem? _supplier;
  String _stockStatus = 'all';
  String _unit = '';
  bool _updatedToday = false;
  bool _pendingOnly = false;

  @override
  void initState() {
    super.initState();
    final q = ref.read(openingStockSetupQueryProvider);
    _categoryCtrl.text = q.category;
    _subcategoryCtrl.text = q.subcategory;
    _unit = q.unit;
    _updatedByCtrl.text = q.updatedBy;
    _stockStatus = q.stockStatus;
    _updatedToday = q.updatedToday;
    _pendingOnly = q.status == 'pending';
  }

  @override
  void dispose() {
    _categoryCtrl.dispose();
    _subcategoryCtrl.dispose();
    _updatedByCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = ref.watch(openingStockSetupQueryProvider);
    final suppliers = ref.watch(suppliersListProvider);
    final supplierItems = suppliers.valueOrNull?.map((s) {
      final id = s['id']?.toString() ?? '';
      final name = s['name']?.toString() ?? 'Supplier';
      return InlineSearchItem(
        id: id,
        label: name,
        searchText: '$name ${s['phone'] ?? ''}',
      );
    }).toList() ?? const <InlineSearchItem>[];

    final units = const ['bag', 'kg', 'piece', 'box', 'tin'];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
            children: [
              Expanded(
                child: Text(
                  'Advanced filters',
                  style: HexaDsType.label(13).copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _categoryCtrl,
            decoration: const InputDecoration(
              labelText: 'Category (exact match)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _subcategoryCtrl,
            decoration: const InputDecoration(
              labelText: 'Subcategory (exact match)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          InlineSearchField(
            items: supplierItems,
            onSelected: (it) {
              setState(() => _supplier = it);
            },
            controller: TextEditingController(
              text: _supplier?.label ?? '',
            ),
            placeholder: 'Supplier (autocomplete)',
            minQueryLength: 1,
          ),
          const SizedBox(height: 10),
          InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Unit type',
              border: OutlineInputBorder(),
            ),
            child: DropdownButton<String>(
              isExpanded: true,
              value: _unit,
              items: [
                const DropdownMenuItem(value: '', child: Text('All units')),
                for (final u in units)
                  DropdownMenuItem(value: u, child: Text(u.toUpperCase())),
              ],
              onChanged: (v) => setState(() => _unit = v ?? ''),
            ),
          ),
          const SizedBox(height: 10),
          InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Stock status',
              border: OutlineInputBorder(),
            ),
            child: DropdownButton<String>(
              isExpanded: true,
              value: _stockStatus,
              items: const [
                DropdownMenuItem(value: 'all', child: Text('All stock status')),
                DropdownMenuItem(value: 'low', child: Text('Low')),
                DropdownMenuItem(value: 'out', child: Text('Out')),
              ],
              onChanged: (v) => setState(() => _stockStatus = v ?? 'all'),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Checkbox(
                value: _pendingOnly,
                onChanged: (_) => setState(() => _pendingOnly = !_pendingOnly),
              ),
              const Text('Pending opening stock only'),
            ],
          ),
          Row(
            children: [
              Checkbox(
                value: _updatedToday,
                onChanged: (_) => setState(() => _updatedToday = !_updatedToday),
              ),
              const Text('Updated today'),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _updatedByCtrl,
            decoration: const InputDecoration(
              labelText: 'Updated by (substring)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 48,
            child: FilledButton(
              onPressed: () {
                      final nextStatus = _pendingOnly ? 'pending' : 'all';
                      ref.read(openingStockSetupQueryProvider.notifier).state =
                            q.copyWith(
                              page: 1,
                              status: nextStatus,
                              stockStatus: _stockStatus,
                              category: _categoryCtrl.text.trim(),
                              subcategory: _subcategoryCtrl.text.trim(),
                              supplierId: _supplier?.id,
                              unit: _unit.trim(),
                              updatedToday: _updatedToday,
                              updatedBy: _updatedByCtrl.text.trim(),
                            );
                      Navigator.of(context).pop();
                    },
              child: const Text('Apply filters'),
            ),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () {
              ref.read(openingStockSetupQueryProvider.notifier).state =
                  const OpeningStockSetupQuery();
              Navigator.of(context).pop();
            },
            child: const Text('Clear all'),
        )
      ],
    );
  }
}

