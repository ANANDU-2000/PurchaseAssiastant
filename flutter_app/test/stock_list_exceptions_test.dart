import 'package:flutter_test/flutter_test.dart';
import 'package:harisree_warehouse/core/auth/provider_api_guard.dart';
import 'package:harisree_warehouse/core/providers/stock_list_exceptions.dart';
import 'package:harisree_warehouse/core/providers/stock_providers.dart'
    show stockListCacheBodyIsUsable;

void main() {
  test('tab_not_visible is not treated as auth failure', () {
    expect(
      isStockListAuthFailure(
        const StockListFetchBlockedException('tab_not_visible'),
      ),
      isFalse,
    );
  });

  test('no_session is auth failure', () {
    expect(
      isStockListAuthFailure(
        const StockListFetchBlockedException('no_session'),
      ),
      isTrue,
    );
  });

  test('api_gate is transient not auth failure', () {
    expect(
      isStockListAuthFailure(
        const StockListFetchBlockedException('api_gate'),
      ),
      isFalse,
    );
    expect(
      isStockListTransientBlock(
        const StockListFetchBlockedException('api_gate'),
      ),
      isTrue,
    );
  });

  test('ProviderFetchAborted is transient stock fetch error', () {
    expect(isTransientStockFetchError(const ProviderFetchAborted()), isTrue);
    expect(
      isTransientStockFetchError(
        const StockListFetchBlockedException('api_gate'),
      ),
      isTrue,
    );
    expect(
      isTransientStockFetchError(
        const StockListFetchBlockedException('no_session'),
      ),
      isFalse,
    );
  });

  test('stockListCacheBodyIsUsable rejects empty page-1 cache', () {
    expect(stockListCacheBodyIsUsable(null), isFalse);
    expect(stockListCacheBodyIsUsable(const {}), isFalse);
    expect(
      stockListCacheBodyIsUsable(const {'items': [], 'total': 0}),
      isFalse,
    );
    expect(
      stockListCacheBodyIsUsable(const {
        'items': [{'id': 'a'}],
        'total': 1,
      }),
      isTrue,
    );
    expect(
      stockListCacheBodyIsUsable(const {'items': [], 'total': 536}),
      isTrue,
    );
  });
}
