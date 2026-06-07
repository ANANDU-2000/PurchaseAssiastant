import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design_system/hexa_operational_tokens.dart';
import '../../../../core/design_system/hexa_responsive.dart';
import '../../../../core/providers/stock_providers.dart';
import 'stock_warehouse_filter_sheet.dart';

/// Compact horizontal status filters: All, Low, Out, Missing Code, Missing Barcode.
class StockStatusChipRow extends ConsumerWidget {
  const StockStatusChipRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final countsAsync = ref.watch(stockFilteredStatusCountsProvider);
    final q = ref.watch(stockListQueryProvider);
    final op = ref.watch(stockOperationalFiltersProvider);
    final filterCount = countWarehouseActiveFilters(q, op);
    final filtersActive = filterCount > 0 || stockListHasScopedFilters(q, op);

    return countsAsync.when(
      loading: () => const SizedBox(height: 36),
      error: (_, __) => const SizedBox.shrink(),
      data: (counts) {
        void applyStatus(String status) {
          ref.read(stockListQueryProvider.notifier).state = q.copyWith(
            status: status,
            page: 1,
          );
          ref.invalidate(stockListProvider);
        }

        void applyMissingCode() {
          ref.read(stockListQueryProvider.notifier).state =
              q.copyWith(status: 'all', page: 1);
          ref.read(stockOperationalFiltersProvider.notifier).state = op
              .copyWith(missingItemCodeOnly: true, clearMissingItemCode: false);
          ref.invalidate(stockListProvider);
        }

        void applyMissingBarcode() {
          ref.read(stockListQueryProvider.notifier).state =
              q.copyWith(status: 'all', page: 1);
          ref.read(stockOperationalFiltersProvider.notifier).state =
              op.copyWith(missingBarcodeOnly: true);
          ref.invalidate(stockListProvider);
        }

        final lowSelected = q.status == 'low' || q.status == 'shortage';

        int? countForChip(String key, bool selected) {
          if (filtersActive && !selected) return null;
          return switch (key) {
            'all' => counts['all'],
            'low' => (counts['low'] ?? 0) + (counts['critical'] ?? 0),
            'out' => counts['out'],
            'missing_code' => counts['missing_code'],
            'missing_barcode' => counts['missing_barcode'],
            _ => counts[key],
          };
        }

        final chips = <({String label, bool selected, VoidCallback onTap, String countKey})>[
          (
            label: 'All',
            selected: q.status == 'all' &&
                !op.missingBarcodeOnly &&
                !op.missingItemCodeOnly,
            onTap: () => applyStatus('all'),
            countKey: 'all',
          ),
          (
            label: 'Low',
            selected: lowSelected,
            onTap: () => applyStatus('shortage'),
            countKey: 'low',
          ),
          (
            label: 'Out',
            selected: q.status == 'out',
            onTap: () => applyStatus('out'),
            countKey: 'out',
          ),
          (
            label: 'Missing Code',
            selected: op.missingItemCodeOnly,
            onTap: applyMissingCode,
            countKey: 'missing_code',
          ),
          (
            label: 'Missing Barcode',
            selected: op.missingBarcodeOnly,
            onTap: applyMissingBarcode,
            countKey: 'missing_barcode',
          ),
        ];

        return SizedBox(
          height: 36,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(
              horizontal: HexaResponsive.pageGutter(context, operational: true),
            ),
            itemCount: chips.length,
            separatorBuilder: (_, __) => const SizedBox(width: 6),
            itemBuilder: (ctx, i) {
              final c = chips[i];
              final n = countForChip(c.countKey, c.selected);
              final countLabel = n != null ? ' ($n)' : (filtersActive && !c.selected ? ' (—)' : '');
              return ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: HexaOp.touchTargetMin,
                ),
                child: FilterChip(
                  label: Text('${c.label}$countLabel'),
                  selected: c.selected,
                  onSelected: (_) => c.onTap(),
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  labelStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  showCheckmark: false,
                ),
              );
            },
          ),
        );
      },
    );
  }
}
