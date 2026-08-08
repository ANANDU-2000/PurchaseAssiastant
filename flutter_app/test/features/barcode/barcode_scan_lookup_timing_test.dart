import 'package:flutter_test/flutter_test.dart';
import 'package:harisree_warehouse/features/barcode/barcode_lookup_cache.dart';
import 'package:harisree_warehouse/features/barcode/barcode_scan_controller.dart';

void main() {
  tearDown(BarcodeLookupCache.clear);

  test('cache hit lookup reports ms and fromCache=true', () async {
    const bid = 'biz-timing';
    const code = 'HIT-001';
    final row = {
      'id': 'item-1',
      'name': 'Cached Item',
      'barcode': code,
    };
    BarcodeLookupCache.put(bid, code, row);

    var networkCalls = 0;
    final ctrl = BarcodeScanController(
      lookupFn: ({required String businessId, required String code}) async {
        networkCalls++;
        // Revalidate returns same row (server still has item).
        return Map<String, dynamic>.from(row);
      },
      stockSearchFn: ({required String businessId, required String q}) async =>
          {'items': []},
    );

    final wall = Stopwatch()..start();
    await ctrl.lookup(code, businessId: bid);
    wall.stop();

    expect(ctrl.lastLookupFromCache, isTrue);
    expect(ctrl.lastLookupMs, isNotNull);
    expect(ctrl.lastLookupMs!, lessThan(200));
    expect(wall.elapsedMilliseconds, lessThan(500));
    expect(networkCalls, 1); // background revalidate
    // ignore: avoid_print
    print('CACHE_HIT scan→result: ${ctrl.lastLookupMs}ms '
        '(revalidate calls=$networkCalls)');
    ctrl.dispose();
  });

  test('cache miss lookup reports ms after mocked Dio delay', () async {
    const bid = 'biz-timing';
    const code = 'MISS-001';
    const artificialDelay = Duration(milliseconds: 80);

    final ctrl = BarcodeScanController(
      lookupFn: ({required String businessId, required String code}) async {
        await Future<void>.delayed(artificialDelay);
        return {
          'id': 'item-2',
          'name': 'Network Item',
          'barcode': code,
        };
      },
      stockSearchFn: ({required String businessId, required String q}) async =>
          {'items': []},
    );

    await ctrl.lookup(code, businessId: bid);

    expect(ctrl.lastLookupFromCache, isFalse);
    expect(ctrl.lastLookupMs, isNotNull);
    expect(ctrl.lastLookupMs!, greaterThanOrEqualTo(70));
    // ignore: avoid_print
    print('CACHE_MISS (mocked ${artificialDelay.inMilliseconds}ms API) '
        'scan→result: ${ctrl.lastLookupMs}ms');
    ctrl.dispose();
  });
}
