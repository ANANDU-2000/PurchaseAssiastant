import 'package:flutter_test/flutter_test.dart';
import 'package:harisree_warehouse/features/reports/stock/reports_stock_models.dart';
import 'package:harisree_warehouse/features/reports/stock/reports_stock_status.dart';

void main() {
  group('ReportsStockMovementStatus', () {
    test('fromApi maps backend keys', () {
      expect(
        ReportsStockMovementStatusX.fromApi('fast'),
        ReportsStockMovementStatus.fast,
      );
      expect(
        ReportsStockMovementStatusX.fromApi('very_slow'),
        ReportsStockMovementStatus.verySlow,
      );
      expect(
        ReportsStockMovementStatusX.fromApi('dead'),
        ReportsStockMovementStatus.dead,
      );
    });

    test('labels match ERP spec', () {
      expect(ReportsStockMovementStatus.dead.label, 'Dead Stock');
      expect(ReportsStockMovementStatus.fast.label, 'Fast Moving');
    });
  });

  group('ReportsStockIntelItem', () {
    test('parses movement fields and matches chip filters', () {
      final item = ReportsStockIntelItem.fromMap({
        'id': '1',
        'name': 'Sugar 50 KG',
        'category': 'Grocery',
        'unit': 'bag',
        'current_stock': 2500,
        'used_7d': 0,
        'used_30d': 20,
        'idle_days': 3,
        'movement_status': 'slow',
      });

      expect(item.currentStock, 2500);
      expect(item.used30d, 20);
      expect(item.movementCompact, '3d ago');
      expect(item.matchesChip(ReportsStockChipFilter.slow), isTrue);
      expect(item.matchesChip(ReportsStockChipFilter.fast), isFalse);
    });

    test('summary counts from map', () {
      final s = ReportsStockSummary.fromMap({
        'all': 120,
        'active': 80,
        'slow': 30,
        'dead': 2,
        'fast': 45,
      });
      expect(s.countFor(ReportsStockChipFilter.dead), 2);
    });
  });
}
