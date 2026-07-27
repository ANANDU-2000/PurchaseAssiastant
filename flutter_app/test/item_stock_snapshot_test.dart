import 'package:flutter_test/flutter_test.dart';
import 'package:harisree_warehouse/features/catalog/domain/item_stock_snapshot.dart';

void main() {
  group('ItemStockSnapshot', () {
    test('mismatch when diff non-zero', () {
      final s = ItemStockSnapshot(
        unitLabel: 'BAG',
        openingQty: 0,
        purchasedQty: 0,
        physicalQty: 50,
        systemQty: 100,
        diffQty: -50,
        reorderLevel: 0,
        hasPendingIncoming: false,
        pendingIncomingDays: null,
        lastUpdatedAt: null,
        lastUpdatedBy: null,
        needsVerification: false,
      );
      expect(s.status, ItemStockStatus.mismatch);
      expect(s.diffLabel().toLowerCase(), contains('missing'));
    });

    test('low stock when below reorder and no mismatch', () {
      final s = ItemStockSnapshot(
        unitLabel: 'KG',
        openingQty: 0,
        purchasedQty: 0,
        physicalQty: 10,
        systemQty: 10,
        diffQty: 0,
        reorderLevel: 20,
        hasPendingIncoming: false,
        pendingIncomingDays: null,
        lastUpdatedAt: null,
        lastUpdatedBy: null,
        needsVerification: false,
      );
      expect(s.status, ItemStockStatus.lowStock);
    });

    test('negative overrides other states', () {
      final s = ItemStockSnapshot(
        unitLabel: 'BAG',
        openingQty: 0,
        purchasedQty: 0,
        physicalQty: 0,
        systemQty: -1,
        diffQty: 0,
        reorderLevel: 0,
        hasPendingIncoming: false,
        pendingIncomingDays: null,
        lastUpdatedAt: null,
        lastUpdatedBy: null,
        needsVerification: true,
      );
      expect(s.status, ItemStockStatus.negative);
    });
  });
}

