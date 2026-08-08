import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harisree_warehouse/core/errors/barcode_operation_errors.dart';
import 'package:harisree_warehouse/features/barcode/barcode_lookup_cache.dart';
import 'package:harisree_warehouse/features/barcode/barcode_scan_controller.dart';
import 'package:harisree_warehouse/features/barcode/barcode_scan_session.dart';

void main() {
  tearDown(BarcodeLookupCache.clear);

  test('isGarbageBarcodeDecode rejects empty and control junk', () {
    expect(isGarbageBarcodeDecode(null), isTrue);
    expect(isGarbageBarcodeDecode(''), isTrue);
    expect(isGarbageBarcodeDecode('   '), isTrue);
    expect(isGarbageBarcodeDecode('\x00\x01\x02'), isTrue);
    expect(isGarbageBarcodeDecode('ABC123'), isFalse);
  });

  test('barcodeMessageForUser maps scanner 404/409/timeout', () {
    expect(
      barcodeMessageForUser(
        DioException(
          requestOptions: RequestOptions(path: '/'),
          response: Response(
            requestOptions: RequestOptions(path: '/'),
            statusCode: 404,
          ),
          type: DioExceptionType.badResponse,
        ),
        ctx: BarcodeOperationContext.scanner,
      ),
      kBarcodeUnknownCatalogMessage,
    );
    expect(
      barcodeMessageForUser(
        DioException(
          requestOptions: RequestOptions(path: '/'),
          response: Response(
            requestOptions: RequestOptions(path: '/'),
            statusCode: 409,
            data: {'detail': 'ambiguous_barcode: multiple items'},
          ),
          type: DioExceptionType.badResponse,
        ),
        ctx: BarcodeOperationContext.scanner,
      ),
      kBarcodeAmbiguousMessage,
    );
    expect(
      barcodeMessageForUser(
        TimeoutException('x'),
        ctx: BarcodeOperationContext.scanner,
      ),
      kBarcodeNetworkMessage,
    );
    expect(
      barcodeMessageForUser(
        DioException(
          requestOptions: RequestOptions(path: '/'),
          response: Response(
            requestOptions: RequestOptions(path: '/'),
            statusCode: 403,
          ),
          type: DioExceptionType.badResponse,
        ),
        ctx: BarcodeOperationContext.scanner,
      ),
      kBarcodePermissionDeniedMessage,
    );
  });

  test('acceptDecode rejects garbage and sets lastRejectMessage', () {
    final ctrl = BarcodeScanController(
      lookupFn: ({required String businessId, required String code}) async =>
          fail('should not lookup'),
      stockSearchFn: ({required String businessId, required String q}) async =>
          {'items': []},
    );
    expect(ctrl.acceptDecode(''), isFalse);
    expect(ctrl.lastRejectMessage, isNotNull);
    expect(ctrl.acceptDecode('GOOD-CODE'), isTrue);
    ctrl.dispose();
  });

  test('stale older lookup cannot overwrite newer result', () async {
    final ctrl = BarcodeScanController(
      lookupFn: ({required String businessId, required String code}) async {
        if (code == 'SLOW') {
          await Future<void>.delayed(const Duration(milliseconds: 80));
          return {'id': 'slow', 'name': 'Slow', 'barcode': code};
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return {'id': 'fast', 'name': 'Fast', 'barcode': code};
      },
      stockSearchFn: ({required String businessId, required String q}) async =>
          {'items': []},
    );

    // Simulate overlapping by starting slow then completing fast via session.
    final slowId = ctrl.session.beginLookup('SLOW');
    final fastId = ctrl.session.beginLookup('FAST');
    expect(ctrl.session.isStale(slowId), isTrue);
    expect(ctrl.session.isStale(fastId), isFalse);
    ctrl.session.completeFound(
      fastId,
      item: {'id': 'fast', 'name': 'Fast'},
    );
    expect(ctrl.session.completeFound(slowId, item: {'id': 'slow'}), isFalse);
    expect(ctrl.session.current?.itemId, 'fast');
    ctrl.dispose();
  });

  test('cache revalidate 404 flips to notFound and invalidates', () async {
    const bid = 'biz';
    const code = 'GONE';
    BarcodeLookupCache.put(bid, code, {
      'id': 'old',
      'name': 'Gone Item',
      'barcode': code,
    });

    final ctrl = BarcodeScanController(
      lookupFn: ({required String businessId, required String code}) async {
        throw DioException(
          requestOptions: RequestOptions(path: '/'),
          response: Response(
            requestOptions: RequestOptions(path: '/'),
            statusCode: 404,
          ),
          type: DioExceptionType.badResponse,
        );
      },
      stockSearchFn: ({required String businessId, required String q}) async =>
          {'items': []},
    );

    await ctrl.lookup(code, businessId: bid);
    expect(ctrl.session.current?.outcome, BarcodeScanOutcome.notFound);
    expect(BarcodeLookupCache.get(bid, code), isNull);
    ctrl.dispose();
  });

  test('second lookup while lookingUp is dropped', () async {
    var calls = 0;
    final ctrl = BarcodeScanController(
      lookupFn: ({required String businessId, required String code}) async {
        calls++;
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return {'id': '1', 'name': 'A', 'barcode': code};
      },
      stockSearchFn: ({required String businessId, required String q}) async =>
          {'items': []},
    );

    final a = ctrl.lookup('AAA', businessId: 'b');
    final b = ctrl.lookup('BBB', businessId: 'b');
    await Future.wait([a, b]);
    expect(calls, 1);
    ctrl.dispose();
  });
}
