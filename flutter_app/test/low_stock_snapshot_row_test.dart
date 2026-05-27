import 'package:flutter_test/flutter_test.dart';
import 'package:harisree_warehouse/features/catalog/domain/item_stock_snapshot.dart';

void main() {
  test('ItemStockSnapshot.fromStockListRow maps operational fields', () {
    final snap = ItemStockSnapshot.fromStockListRow({
      'name': 'Rice',
      'stock_unit': 'bag',
      'current_stock': 10,
      'physical_stock_qty': 8,
      'physical_stock_difference_qty': -2,
      'reorder_level': 15,
      'has_pending_order': true,
      'pending_order_days': 5,
      'needs_verification': false,
      'lifecycle_stage': 'ordered',
    });

    expect(snap.systemQty, 10);
    expect(snap.physicalQty, 8);
    expect(snap.diffQty, -2);
    expect(snap.hasPendingIncoming, isTrue);
    expect(snap.pendingIncomingDays, 5);
    expect(snap.statusChipLabel().isNotEmpty, isTrue);
  });
}
