import 'package:flutter_test/flutter_test.dart';
import 'package:harisree_warehouse/core/providers/stock_providers.dart';

void main() {
  test('StockListQuery equality enables cache family dedupe', () {
    const a = StockListQuery(status: 'out', perPage: 8);
    const b = StockListQuery(status: 'out', perPage: 8);
    const c = StockListQuery(status: 'low', perPage: 8);
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a, isNot(c));
  });

  test('kHomeOutOfStockListQuery is scoped for home strip', () {
    expect(kHomeOutOfStockListQuery.status, 'out');
    expect(kHomeOutOfStockListQuery.perPage, lessThanOrEqualTo(10));
  });
}
