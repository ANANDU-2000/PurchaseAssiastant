import 'package:flutter_test/flutter_test.dart';
import 'package:hexa_purchase_assistant/core/decision/trade_buy_verdict.dart';

void main() {
  test('no data when last or avg missing', () {
    expect(
      tradeBuyVerdict(lastLanded: null, tradeAvg: 10).label,
      'NO DATA',
    );
    expect(
      tradeBuyVerdict(lastLanded: 5, tradeAvg: null).label,
      'NO DATA',
    );
  });

  test('GOOD at or below average', () {
    final a = tradeBuyVerdict(lastLanded: 100, tradeAvg: 100);
    expect(a.label, 'GOOD');
    final b = tradeBuyVerdict(lastLanded: 99, tradeAvg: 100);
    expect(b.label, 'GOOD');
  });

  test('OK within 5% band', () {
    final v = tradeBuyVerdict(lastLanded: 104, tradeAvg: 100);
    expect(v.label, 'OK');
  });

  test('BAD above 5% band', () {
    final v = tradeBuyVerdict(lastLanded: 106, tradeAvg: 100);
    expect(v.label, 'BAD');
  });

  test('OK includes bestLatest in detail when set', () {
    final v = tradeBuyVerdict(
      lastLanded: 104,
      tradeAvg: 100,
      bestLatest: 95,
    );
    expect(v.label, 'OK');
    expect(v.detail, contains('Best latest supplier quote'));
  });
}
