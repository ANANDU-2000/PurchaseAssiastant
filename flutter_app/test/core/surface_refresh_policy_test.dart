import 'package:flutter_test/flutter_test.dart';

import 'package:harisree_warehouse/core/navigation/surface_refresh_policy.dart';

void main() {
  test('shouldRefreshOnShellTabReturn respects 45s min interval', () {
    expect(shouldRefreshOnShellTabReturn(null), isTrue);
    expect(
      shouldRefreshOnShellTabReturn(
        DateTime.now().subtract(const Duration(seconds: 10)),
      ),
      isFalse,
    );
    expect(
      shouldRefreshOnShellTabReturn(
        DateTime.now().subtract(const Duration(seconds: 50)),
      ),
      isTrue,
    );
  });

  test('shouldSoftRefreshHomeSurfaces respects 30s min interval', () {
    expect(shouldSoftRefreshHomeSurfaces(null), isTrue);
    expect(
      shouldSoftRefreshHomeSurfaces(
        DateTime.now().subtract(const Duration(seconds: 10)),
      ),
      isFalse,
    );
    expect(
      shouldSoftRefreshHomeSurfaces(
        DateTime.now().subtract(const Duration(seconds: 35)),
      ),
      isTrue,
    );
  });

  test('kStockListCacheTtl is three minutes', () {
    expect(kStockListCacheTtl, const Duration(minutes: 3));
  });
}
