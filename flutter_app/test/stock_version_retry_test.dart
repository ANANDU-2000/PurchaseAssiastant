import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harisree_warehouse/core/stock/stock_version_retry.dart';

DioException _stale409({required int version}) {
  return DioException(
    requestOptions: RequestOptions(path: '/stock'),
    response: Response(
      requestOptions: RequestOptions(path: '/stock'),
      statusCode: 409,
      data: {
        'detail': {
          'code': 'STALE_STOCK_VERSION',
          'stock_version': version,
          'current_stock': '42',
        },
      },
    ),
  );
}

void main() {
  test('parseStaleStockConflict reads version from 409 body', () {
    final stale = parseStaleStockConflict(_stale409(version: 7));
    expect(stale, isNotNull);
    expect(stale!.currentVersion, 7);
    expect(stale.currentStock, '42');
  });

  test('runWithStockVersionRetry retries once with new version', () async {
    var calls = 0;
    final result = await runWithStockVersionRetry<int>(
      initialVersion: 1,
      operation: (version, {force = false}) async {
        calls++;
        if (calls == 1) {
          expect(version, 1);
          expect(force, isFalse);
          throw _stale409(version: 2);
        }
        expect(version, 2);
        expect(force, isFalse);
        return 99;
      },
    );
    expect(result, 99);
    expect(calls, 2);
  });

  test('runWithStockVersionRetry never forces final stale attempt', () async {
    var calls = 0;
    await expectLater(
      runWithStockVersionRetry<int>(
        initialVersion: 0,
        maxAttempts: 3,
        operation: (version, {force = false}) async {
          calls++;
          expect(force, isFalse);
          throw _stale409(version: calls);
        },
      ),
      throwsA(isA<StaleStockConflict>()),
    );
    expect(calls, 3);
  });

  test('runWithStockVersionRetry throws StaleStockConflict when all attempts stale', () {
    expect(
      () => runWithStockVersionRetry<void>(
        initialVersion: 0,
        maxAttempts: 2,
        operation: (_, {force = false}) async {
          throw _stale409(version: 1);
        },
      ),
      throwsA(isA<StaleStockConflict>()),
    );
  });

  test('stockVersionFromItem parses int and num', () {
    expect(stockVersionFromItem({'stock_version': 3}), 3);
    expect(stockVersionFromItem({'stock_version': 4.0}), 4);
  });
}
