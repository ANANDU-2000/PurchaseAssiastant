import 'package:flutter_test/flutter_test.dart';
import 'package:harisree_warehouse/features/stock/presentation/widgets/stock_status_badge.dart';

void main() {
  group('StockStatusBadge.resolve', () {
    test('priority: out beats low', () {
      expect(
        StockStatusBadge.resolve(
          stockStatus: 'out',
          missingBarcode: true,
        ),
        StockRowStatusKind.out,
      );
    });

    test('low when critical', () {
      expect(
        StockStatusBadge.resolve(stockStatus: 'critical', missingBarcode: false),
        StockRowStatusKind.low,
      );
    });

    test('missing barcode when healthy', () {
      expect(
        StockStatusBadge.resolve(stockStatus: 'healthy', missingBarcode: true),
        StockRowStatusKind.missingBarcode,
      );
    });

    test('ok when healthy with code', () {
      expect(
        StockStatusBadge.resolve(stockStatus: 'healthy', missingBarcode: false),
        StockRowStatusKind.ok,
      );
    });
  });

  group('formatStockRelativeTime', () {
    test('returns empty for null', () {
      expect(formatStockRelativeTime(null), '');
    });

    test('returns minutes ago for recent', () {
      final iso = DateTime.now()
          .subtract(const Duration(minutes: 2))
          .toUtc()
          .toIso8601String();
      expect(formatStockRelativeTime(iso), '2m ago');
    });
  });
}
