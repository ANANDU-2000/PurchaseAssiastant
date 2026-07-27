import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:harisree_warehouse/core/providers/business_aggregates_invalidation.dart';
import 'package:harisree_warehouse/core/providers/home_owner_dashboard_providers.dart';
import 'package:harisree_warehouse/core/providers/low_stock_providers.dart';
import 'package:harisree_warehouse/core/providers/stock_providers.dart';

void main() {
  test('invalidateAfterDeliveryCommit refreshes stock and low-stock providers',
      () async {
    var stockReads = 0;
    var lowStockReads = 0;

    final container = ProviderContainer(
      overrides: [
        stockListProvider.overrideWith((ref) async {
          stockReads++;
          return <String, dynamic>{'items': <Map<String, dynamic>>[], 'total': 0};
        }),
        lowStockOperationsSummaryProvider.overrideWith((ref) async {
          lowStockReads++;
          return <String, dynamic>{};
        }),
      ],
    );
    addTearDown(container.dispose);

    await container.read(stockListProvider.future);
    await container.read(lowStockOperationsSummaryProvider.future);
    expect(stockReads, 1);
    expect(lowStockReads, 1);

    invalidateAfterDeliveryCommit(
      container,
      purchaseId: 'purchase-1',
      affectedItemIds: {'item-1'},
    );
    await Future<void>.delayed(const Duration(milliseconds: 200));

    await container.read(stockListProvider.future);
    await container.read(lowStockOperationsSummaryProvider.future);
    expect(stockReads, 2);
    expect(lowStockReads, 2);
  });

  test('invalidateAfterDeliveryCommit busts homeStockAttentionCountProvider',
      () async {
    var attentionReads = 0;

    final container = ProviderContainer(
      overrides: [
        homeStockAttentionCountProvider.overrideWith((ref) async {
          attentionReads++;
          return 3;
        }),
      ],
    );
    addTearDown(container.dispose);

    await container.read(homeStockAttentionCountProvider.future);
    expect(attentionReads, 1);

    invalidateAfterDeliveryCommit(
      container,
      purchaseId: 'purchase-1',
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));

    await container.read(homeStockAttentionCountProvider.future);
    expect(attentionReads, 2);
  });

  test('syncPurchaseStockAfterVerify commits bust stock when stock_committed',
      () async {
    var stockReads = 0;

    final container = ProviderContainer(
      overrides: [
        stockListProvider.overrideWith((ref) async {
          stockReads++;
          return <String, dynamic>{'items': <Map<String, dynamic>>[], 'total': 0};
        }),
      ],
    );
    addTearDown(container.dispose);

    await container.read(stockListProvider.future);
    syncPurchaseStockAfterVerify(
      container,
      purchaseId: 'p1',
      verifyResponse: {
        'delivery_status': 'stock_committed',
        'lines': [
          {'catalog_item_id': 'item-a'},
        ],
      },
    );
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await container.read(stockListProvider.future);
    expect(stockReads, 2);
  });

  test('invalidateAfterPurchaseDelete refreshes stockListProvider', () async {
    var stockReads = 0;

    final container = ProviderContainer(
      overrides: [
        stockListProvider.overrideWith((ref) async {
          stockReads++;
          return <String, dynamic>{'items': <Map<String, dynamic>>[], 'total': 0};
        }),
      ],
    );
    addTearDown(container.dispose);

    await container.read(stockListProvider.future);
    invalidateAfterPurchaseDelete(
      container,
      purchaseId: 'deleted-po',
      extraItemIds: {'item-x'},
    );
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await container.read(stockListProvider.future);
    expect(stockReads, 2);
  });
}
