import 'package:flutter_test/flutter_test.dart';
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
}
