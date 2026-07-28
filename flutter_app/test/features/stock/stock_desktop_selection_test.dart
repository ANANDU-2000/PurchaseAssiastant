import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harisree_warehouse/core/providers/stock_list_providers.dart';
import 'package:harisree_warehouse/features/stock/presentation/stock_page.dart';
import 'package:harisree_warehouse/features/stock/stock_list_row_patch.dart';

void main() {
  group('selectStockDesktopDetailItem', () {
    final items = [
      {'id': 'a', 'name': 'Item A', 'current_stock': 10},
      {'id': 'b', 'name': 'Item B', 'current_stock': 20},
      {'id': 'c', 'name': 'Item C', 'current_stock': 30},
    ];

    test('select A then B switches detail without edit', () {
      expect(selectStockDesktopDetailItem(items, 'a')?['id'], 'a');
      expect(selectStockDesktopDetailItem(items, 'b')?['id'], 'b');
    });

    test('null/empty selection falls back to first visible row', () {
      expect(selectStockDesktopDetailItem(items, null)?['id'], 'a');
      expect(selectStockDesktopDetailItem(items, '')?['id'], 'a');
    });

    test('selected id missing under active filter falls back to first visible', () {
      final filtered = items.where((e) => e['id'] != 'a').toList();
      expect(selectStockDesktopDetailItem(filtered, 'a')?['id'], 'b');
    });

    test('empty list returns null', () {
      expect(selectStockDesktopDetailItem(const [], 'a'), isNull);
    });
  });

  test('watching stockSelectedItemIdProvider rebuilds on A→B select', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final seen = <String?>[];
    container.listen<String?>(
      stockSelectedItemIdProvider,
      (prev, next) => seen.add(next),
      fireImmediately: true,
    );

    expect(seen, [null]);

    container.read(stockSelectedItemIdProvider.notifier).state = 'a';
    container.read(stockSelectedItemIdProvider.notifier).state = 'b';

    expect(seen, [null, 'a', 'b']);
    expect(container.read(stockSelectedItemIdProvider), 'b');
  });

  test('select B + row patch updates system and physical for detail row', () {
    final items = [
      {
        'id': 'a',
        'current_stock': 10,
        'physical_stock_qty': 9,
      },
      {
        'id': 'b',
        'current_stock': 20,
        'physical_stock_qty': 18,
      },
    ];
    final selected = selectStockDesktopDetailItem(items, 'b');
    expect(selected?['id'], 'b');

    final patched = mergeStockListRowMap(
      selected!,
      {
        'b': {
          'current_stock': 25,
          'physical_stock_qty': 24,
          'physical_stock_difference_qty': -1,
        },
      },
    );
    expect(patched['current_stock'], 25);
    expect(patched['physical_stock_qty'], 24);
    expect(patched['physical_stock_difference_qty'], -1);
  });
}
