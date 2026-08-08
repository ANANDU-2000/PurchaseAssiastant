import 'package:flutter_test/flutter_test.dart';
import 'package:harisree_warehouse/core/providers/stock_list_providers.dart';

void main() {
  test('mergeStockActivityRows interleaves physical floor with audit', () {
    final merged = mergeStockActivityRows(
      audit: [
        {
          'id': 'a1',
          'item_name': 'Sugar',
          'adjustment_type': 'correction',
          'old_qty': 100,
          'new_qty': 95,
          'updated_at': '2026-08-08T12:00:00Z',
        },
      ],
      physical: [
        {
          'id': 'p1',
          'item_name': 'Sugar',
          'counted_qty': 80,
          'system_qty': 100,
          'difference_qty': -20,
          'counted_at': '2026-08-08T14:00:00Z',
          'counted_by_name': 'Staff',
        },
      ],
    );
    expect(merged.length, 2);
    expect(isPhysicalFloorFeedRow(merged.first), isTrue);
    expect(merged.first['new_qty'], 80);
    expect(merged.first['updated_at'], '2026-08-08T14:00:00Z');
  });

  test('isPhysicalFloorFeedRow detects feed_kind', () {
    expect(
      isPhysicalFloorFeedRow({'feed_kind': 'physical_floor'}),
      isTrue,
    );
    expect(
      isPhysicalFloorFeedRow({'adjustment_type': 'correction'}),
      isFalse,
    );
  });
}
