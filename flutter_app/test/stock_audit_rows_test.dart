import 'package:flutter_test/flutter_test.dart';
import 'package:harisree_warehouse/core/providers/home_dashboard_provider.dart';
import 'package:harisree_warehouse/core/utils/stock_audit_rows.dart';

void main() {
  test('parseStockAuditTimestamp prefers updated_at', () {
    final at = parseStockAuditTimestamp({
      'updated_at': '2026-06-01T10:30:00Z',
      'created_at': '2020-01-01T00:00:00Z',
    });
    expect(at, isNotNull);
    expect(at!.year, 2026);
  });

  test('stockAuditQtyDelta from old and new qty', () {
    expect(
      stockAuditQtyDelta({'old_qty': 10, 'new_qty': 15}),
      5,
    );
    expect(
      stockAuditQtyDelta({'old_qty': 20, 'new_qty': 12}),
      -8,
    );
  });

  test('filterStockAuditRowsByHomePeriod keeps rows in window', () {
    final rows = [
      {
        'updated_at': '2026-06-01T12:00:00Z',
        'item_name': 'Sugar',
      },
      {
        'updated_at': '2020-01-01T12:00:00Z',
        'item_name': 'Old',
      },
    ];
    final filtered = filterStockAuditRowsByHomePeriod(
      rows,
      HomePeriod.month,
      now: DateTime(2026, 6, 1),
    );
    expect(filtered.length, 1);
    expect(filtered.first['item_name'], 'Sugar');
  });

  test('filterStockAuditRowsOnLocalDay matches calendar day', () {
    final rows = [
      {'updated_at': '2026-06-01T18:00:00Z', 'item_name': 'A'},
      {'updated_at': '2026-05-31T18:00:00Z', 'item_name': 'B'},
    ];
    final day = DateTime(2026, 6, 1);
    final filtered = filterStockAuditRowsOnLocalDay(rows, day);
    expect(filtered.length, 1);
    expect(filtered.first['item_name'], 'A');
  });
}
