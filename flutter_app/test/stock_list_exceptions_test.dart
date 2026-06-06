import 'package:flutter_test/flutter_test.dart';
import 'package:harisree_warehouse/core/providers/stock_list_exceptions.dart';

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
}
