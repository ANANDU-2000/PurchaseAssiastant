import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harisree_warehouse/core/providers/stock_list_providers.dart';
import 'package:harisree_warehouse/features/stock/stock_list_row_patch.dart';

void main() {
  test('mergeStockListRowMap merges overlay by id', () {
    final out = mergeStockListRowMap(
      {'id': 'a', 'current_stock': 10, 'physical_stock_qty': 9},
      {
        'a': {'physical_stock_qty': 11, 'physical_stock_difference_qty': 1},
      },
    );
    expect(out['physical_stock_qty'], 11);
    expect(out['physical_stock_difference_qty'], 1);
    expect(out['current_stock'], 10);
  });

  test('stockListPatchFromStockDetail includes stock_status', () {
    final patch = stockListPatchFromStockDetail({
      'current_stock': 10,
      'reorder_level': 5,
      'stock_status': 'healthy',
    });
    expect(patch['current_stock'], 10);
    expect(patch['stock_status'], 'healthy');
  });

  test('stockListPatchFromStockDetail derives status when qty moves out of out', () {
    final patch = stockListPatchFromStockDetail({
      'current_stock': 10,
      'reorder_level': 5,
    });
    expect(patch['stock_status'], 'healthy');
  });

  test('stockListPatchFromPhysicalCount maps API fields', () {
    final patch = stockListPatchFromPhysicalCount({
      'counted_qty': 5001,
      'system_qty': 5000,
      'difference_qty': 1,
      'counted_by_name': 'Ananduk',
      'counted_at': '2026-06-04T12:00:00Z',
    });
    expect(patch['physical_stock_qty'], 5001);
    expect(patch['physical_stock_difference_qty'], 1);
    expect(patch['physical_stock_counted_by'], 'Ananduk');
  });

  test('mergeStockListRowMaps merges patches by id into items list', () {
    final data = {
      'items': [
        {'id': 'a', 'current_stock': 10},
        {'id': 'b', 'current_stock': 20},
      ],
      'total': 2,
    };
    final patches = {
      'a': {'current_stock': 15},
    };
    final out = mergeStockListRowMaps(data, patches);
    final items = out['items'] as List;
    expect((items[0] as Map)['current_stock'], 15);
    expect((items[1] as Map)['current_stock'], 20);
  });

  test('mergeStockListRowMap returns row unchanged when no patch matches', () {
    final row = {'id': 'x', 'current_stock': 10};
    final patches = <String, Map<String, dynamic>>{};
    expect(mergeStockListRowMap(row, patches), row);
  });

  test('reconcile keeps overlay when server row is stale', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    applyStockListRowPatch(
      container,
      itemId: 'a',
      patch: {
        'current_stock': 120,
        'physical_stock_qty': 115,
        'physical_stock_difference_qty': -5,
        'stock_version': 2,
      },
    );
    reconcileStockListRowPatches(container, [
      {
        'id': 'a',
        'current_stock': 110,
        'physical_stock_qty': 105,
        'physical_stock_difference_qty': -5,
        'stock_version': 1,
      },
    ]);
    final patches = container.read(stockListRowPatchProvider);
    expect(patches['a']?['current_stock'], 120);
    expect(patches['a']?['physical_stock_qty'], 115);
  });

  test('reconcile clears overlay when server matches patch', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    applyStockListRowPatch(
      container,
      itemId: 'a',
      patch: {
        'current_stock': 120,
        'physical_stock_qty': 115,
        'physical_stock_difference_qty': -5,
        'stock_version': 2,
      },
    );
    reconcileStockListRowPatches(container, [
      {
        'id': 'a',
        'current_stock': 120,
        'physical_stock_qty': 115,
        'physical_stock_difference_qty': -5,
        'stock_version': 2,
      },
    ]);
    expect(container.read(stockListRowPatchProvider).containsKey('a'), isFalse);
  });

  test('reconcile clears overlay when server stock_version is newer', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    applyStockListRowPatch(
      container,
      itemId: 'a',
      patch: {
        'current_stock': 100,
        'stock_version': 1,
      },
    );
    reconcileStockListRowPatches(container, [
      {
        'id': 'a',
        'current_stock': 130,
        'stock_version': 3,
      },
    ]);
    expect(container.read(stockListRowPatchProvider).containsKey('a'), isFalse);
  });

  test('stockListPatchFromPreSaveRow restores qty, version, status, stamps', () {
    final patch = stockListPatchFromPreSaveRow({
      'current_stock': 40,
      'physical_stock_qty': 45,
      'physical_stock_difference_qty': 5,
      'stock_version': 7,
      'stock_status': 'healthy',
      'last_stock_updated_at': '2026-08-05T10:00:00Z',
      'physical_stock_counted_by': 'Ananduk',
    });
    expect(patch['current_stock'], 40);
    expect(patch['physical_stock_qty'], 45);
    expect(patch['physical_stock_difference_qty'], 5);
    expect(patch['stock_version'], 7);
    expect(patch['stock_status'], 'healthy');
    expect(patch['last_stock_updated_at'], '2026-08-05T10:00:00Z');
    expect(patch['physical_stock_counted_by'], 'Ananduk');
  });

  test('stockListPatchFromPreSaveRow omits absent keys and computes diff', () {
    final patch = stockListPatchFromPreSaveRow({
      'current_stock': 40,
      'physical_stock_qty': 45,
    });
    expect(patch['current_stock'], 40);
    expect(patch['physical_stock_qty'], 45);
    expect(patch['physical_stock_difference_qty'], 5);
    expect(patch.containsKey('stock_version'), isFalse);
    expect(patch.containsKey('stock_status'), isFalse);
  });

  test('stockListPatchFromPreSaveRow returns empty map for blank row', () {
    expect(stockListPatchFromPreSaveRow({}), isEmpty);
    expect(stockListPatchFromPreSaveRow({'id': 'x'}), isEmpty);
  });
}
