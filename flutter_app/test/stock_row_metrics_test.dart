import 'package:flutter_test/flutter_test.dart';
import 'package:harisree_warehouse/features/stock/presentation/widgets/stock_row_metrics.dart';

void main() {
  group('StockRowMetrics.diffQty', () {
    test('uses physical minus system when both present', () {
      final item = {
        'current_stock': 100,
        'physical_stock_qty': 80,
      };
      expect(StockRowMetrics.diffQty(item), -20);
    });

    test('prefers warehouse_diff_qty when set', () {
      final item = {
        'current_stock': 100,
        'physical_stock_qty': 80,
        'warehouse_diff_qty': 5,
      };
      expect(StockRowMetrics.diffQty(item), 5);
    });

    test('does not subtract purchased qty', () {
      final item = {
        'current_stock': 101,
        'period_purchased_qty': 711,
        'physical_stock_qty': null,
      };
      final diff = StockRowMetrics.diffQty(item);
      expect(diff.isNaN, isTrue);
    });
  });

  group('StockRowMetrics.deliveryMetaLine', () {
    test('pending truck with qty and days', () {
      final line = StockRowMetrics.deliveryMetaLine({
        'has_pending_order': true,
        'pending_delivery_qty': 12,
        'pending_order_days': 3,
        'last_purchase_human_id': 'PO-1',
      });
      expect(line, contains('Pending truck'));
      expect(line, contains('3d'));
    });
  });
}
