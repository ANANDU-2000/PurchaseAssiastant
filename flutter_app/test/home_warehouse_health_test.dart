import 'package:flutter_test/flutter_test.dart';
import 'package:harisree_warehouse/features/home/domain/warehouse_health.dart';

void main() {
  group('computeWarehouseHealth', () {
    test('GOOD when no issues', () {
      expect(
        computeWarehouseHealth(const WarehouseHealthInput()),
        WarehouseHealthLevel.good,
      );
    });

    test('WARNING for low stock or pending delivery', () {
      expect(
        computeWarehouseHealth(
          const WarehouseHealthInput(lowStock: 2),
        ),
        WarehouseHealthLevel.warning,
      );
      expect(
        computeWarehouseHealth(
          const WarehouseHealthInput(pendingDeliveries: 1),
        ),
        WarehouseHealthLevel.warning,
      );
      expect(
        computeWarehouseHealth(
          const WarehouseHealthInput(pendingApprovals: 3),
        ),
        WarehouseHealthLevel.warning,
      );
    });

    test('CRITICAL overrides warning', () {
      expect(
        computeWarehouseHealth(
          const WarehouseHealthInput(
            lowStock: 5,
            criticalStock: 1,
          ),
        ),
        WarehouseHealthLevel.critical,
      );
      expect(
        computeWarehouseHealth(
          const WarehouseHealthInput(mismatchCount: 1),
        ),
        WarehouseHealthLevel.critical,
      );
      expect(
        computeWarehouseHealth(
          const WarehouseHealthInput(negativeStock: 2),
        ),
        WarehouseHealthLevel.critical,
      );
    });
  });
}
