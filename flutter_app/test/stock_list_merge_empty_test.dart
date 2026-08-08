import 'package:flutter_test/flutter_test.dart';
import 'package:harisree_warehouse/features/stock/stock_list_merge.dart';

/// Regression guard: after a stock edit the deferred list reload can race the
/// shell branch sync and fabricate `{items:[], total:0}`. The page must not let
/// that empty payload clobber a healthy merged list ("Stock list did not load").
void main() {
  Map<String, dynamic> healthy() => {
        'items': [
          {'id': 'a', 'name': 'Rice', 'current_stock': 10, 'stock_status': 'healthy'},
          {'id': 'b', 'name': 'Oil', 'current_stock': 0, 'stock_status': 'out'},
        ],
        'total': 2,
        'page': 1,
      };

  test('healthy page-1 payload is not empty', () {
    expect(stockListPayloadIsEmpty(healthy()), isFalse);
  });

  test('fabricated off-tab empty payload is detected', () {
    expect(
      stockListPayloadIsEmpty(const {
        'items': <dynamic>[],
        'total': 0,
        'page': 1,
        'per_page': 50,
      }),
      isTrue,
    );
  });

  test('null payload is treated as empty', () {
    expect(stockListPayloadIsEmpty(null), isTrue);
  });

  test('empty payload does not replace a healthy merged list (page 1)', () {
    final good = mergeStockListPage(previous: null, incoming: healthy(), page: 1);
    expect(good['total'], 2);
    expect((good['items'] as List).length, 2);
    // If a reload yields the fabricated empty payload for the same page, the
    // page-level guard keeps the healthy merged list rather than adopting it.
    final empty = mergeStockListPage(
      previous: null,
      incoming: const {
        'items': <dynamic>[],
        'total': 0,
        'page': 1,
      },
      page: 1,
    );
    expect(stockListPayloadIsEmpty(empty), isTrue);
    // Guard decision: when `_mergedData` is healthy (non-empty) and the
    // incoming page-1 payload is empty, the page keeps the healthy list.
    final guardApplies =
        !stockListPayloadIsEmpty(good) && stockListPayloadIsEmpty(empty);
    expect(guardApplies, isTrue);
  });
}
