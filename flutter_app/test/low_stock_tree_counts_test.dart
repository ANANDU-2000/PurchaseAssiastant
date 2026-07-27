import 'package:flutter_test/flutter_test.dart';
import 'package:harisree_warehouse/features/stock/presentation/widgets/low_stock_category_tree.dart';
import 'package:harisree_warehouse/features/stock/presentation/widgets/low_stock_tree_counts.dart';

void main() {
  Map<String, dynamic> row({
    String status = 'low',
    double stock = 5,
    bool pending = false,
    bool delivered = true,
    double pendingDel = 0,
    double purchased = 0,
  }) {
    return {
      'stock_status': status,
      'current_stock': stock,
      'reorder_level': 10,
      'has_pending_order': pending,
      'last_purchase_delivered': delivered,
      'pending_delivery_qty': pendingDel,
      'period_purchased_qty': purchased,
    };
  }

  group('lowStockMatchesTab', () {
    test('out tab matches zero stock', () {
      expect(
        lowStockMatchesTab(row(status: 'out', stock: 0), LowStockTreeTab.outOfStock),
        isTrue,
      );
      expect(
        lowStockMatchesTab(row(status: 'low', stock: 5), LowStockTreeTab.outOfStock),
        isFalse,
      );
    });

    test('pending delivery tab', () {
      expect(
        lowStockMatchesTab(
          row(pending: true, delivered: false),
          LowStockTreeTab.pendingDelivery,
        ),
        isTrue,
      );
      expect(
        lowStockMatchesTab(
          row(pendingDel: 2),
          LowStockTreeTab.pendingDelivery,
        ),
        isTrue,
      );
    });
  });

  group('dual counts', () {
    test('category low and out badges', () {
      final grouped = {
        'Spices': {
          'Whole': [
            row(status: 'low', stock: 2),
            row(status: 'out', stock: 0),
          ],
        },
      };
      final c = countLowOutForGrouped(grouped, 'Spices', LowStockTreeTab.allLow);
      expect(c.low, 1);
      expect(c.out, 1);
    });
  });

  group('sortedLowStockItemsByName', () {
    test('sorts by name then id', () {
      final sorted = sortedLowStockItemsByName([
        {'id': '2', 'name': 'Zebra'},
        {'id': '1', 'name': 'Apple'},
        {'id': '3', 'name': 'apple'},
      ]);
      expect(sorted.map((e) => e['name']).toList(), ['Apple', 'apple', 'Zebra']);
    });
  });

  group('filterLowStockGrouped search scope', () {
    test('category scope filters by category name', () {
      final grouped = {
        'Rice': {'A': [row()]},
        'Spices': {'B': [row()]},
      };
      final filtered = filterLowStockGrouped(
        grouped: grouped,
        tab: LowStockTreeTab.allLow,
        searchQuery: 'rice',
        searchScope: LowStockSearchScope.category,
      );
      expect(filtered.keys, ['Rice']);
    });

    test('item scope filters by name', () {
      final grouped = {
        'Rice': {
          'A': [
            {...row(), 'name': 'Basmati'},
            {...row(), 'name': 'Sona'},
          ],
        },
      };
      final filtered = filterLowStockGrouped(
        grouped: grouped,
        tab: LowStockTreeTab.allLow,
        searchQuery: 'bas',
        searchScope: LowStockSearchScope.item,
      );
      expect(filtered['Rice']!['A']!.length, 1);
      expect(filtered['Rice']!['A']!.first['name'], 'Basmati');
    });
  });
}
