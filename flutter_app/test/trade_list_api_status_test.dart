import 'package:flutter_test/flutter_test.dart';
import 'package:harisree_warehouse/core/providers/trade_purchases_provider.dart';

void main() {
  test('secondary pending maps to API pending status', () {
    expect(
      tradeListApiStatusFromFilters('all', 'pending'),
      'pending',
    );
    expect(
      tradeListApiStatusFromFilters('due', 'pending'),
      'pending',
    );
    expect(tradeListApiStatusFromFilters('paid', null), 'paid');
    expect(tradeListApiStatusFromFilters('all', 'overdue'), 'overdue');
  });
}
