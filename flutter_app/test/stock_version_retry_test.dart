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
      operation: (version) async {
        calls++;
        if (calls == 1) {
          expect(version, 1);
          throw _stale409(version: 2);
        }
        expect(version, 2);
        return 99;
      },
    );
    expect(result, 99);
    expect(calls, 2);
  });

  test('runWithStockVersionRetry throws StaleStockConflict on second 409', () {
    expect(
      () => runWithStockVersionRetry<void>(
        initialVersion: 0,
        operation: (_) async {
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
