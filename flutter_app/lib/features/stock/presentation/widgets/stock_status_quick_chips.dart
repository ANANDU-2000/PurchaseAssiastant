import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/stock_providers.dart';
import '../../../../core/theme/hexa_colors.dart';
import 'stock_warehouse_filter_sheet.dart';

/// All / Low / Out quick filters above the stock search bar.
class StockStatusQuickChips extends ConsumerWidget {
  const StockStatusQuickChips({
    super.key,
    required this.selectedStatus,
    required this.onSelected,
  });

  final String selectedStatus;
  final ValueChanged<String> onSelected;

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
        int? lowCount() => (counts['low'] ?? 0) + (counts['critical'] ?? 0);

        int? countFor(String key, bool selected) {
          if (filtersActive && !selected) return null;
          return switch (key) {
            'all' => counts['all'],
            'low' => lowCount(),
            'out' => counts['out'],
            _ => counts[key],
          };
        }

        final lowSelected =
            selectedStatus == 'low' || selectedStatus == 'shortage';

        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 2),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _chip(
                label: 'All',
                count: countFor('all', selectedStatus == 'all'),
                icon: Icons.layers_outlined,
                color: HexaColors.brandPrimary,
                selected: selectedStatus == 'all',
                onTap: () => onSelected('all'),
              ),
              _chip(
                label: 'Low',
                count: countFor('low', lowSelected),
                icon: Icons.warning_amber_rounded,
                color: const Color(0xFFE65100),
                selected: lowSelected,
                onTap: () => onSelected('shortage'),
              ),
              _chip(
                label: 'Out',
                count: countFor('out', selectedStatus == 'out'),
                icon: Icons.remove_shopping_cart_outlined,
                color: const Color(0xFFDC2626),
                selected: selectedStatus == 'out',
                onTap: () => onSelected('out'),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _chip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    required Color color,
    required IconData icon,
    int? count,
  }) {
    return FilterChip(
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      selected: selected,
      showCheckmark: false,
      avatar: Icon(
        icon,
        size: 14,
        color: selected ? Colors.white : color,
      ),
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: selected ? Colors.white : color,
            ),
          ),
          if (count != null) ...[
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: selected ? Colors.white.withValues(alpha: 0.25) : color,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                count > 999 ? '999+' : '$count',
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
            ),
          ] else if (!selected) ...[
            const SizedBox(width: 4),
            Text(
              '—',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: color.withValues(alpha: 0.6),
              ),
            ),
          ],
        ],
      ),
      selectedColor: color,
      backgroundColor: color.withValues(alpha: 0.08),
      side: BorderSide(color: selected ? color : color.withValues(alpha: 0.35)),
      onSelected: (_) => onTap(),
    );
  }
}
