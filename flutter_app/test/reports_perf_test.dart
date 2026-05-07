import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:hexa_purchase_assistant/core/reporting/trade_report_aggregate.dart';

void main() {
  test('reports list ops: 5000 rows filter+sort under 300ms', () {
    final rnd = Random(1);
    final List<TradeReportItemRow> rows = List.generate(5000, (i) {
      final bags = (i % 3 == 0) ? (1 + rnd.nextInt(200)).toDouble() : 0.0;
      final boxes = (i % 5 == 0) ? (1 + rnd.nextInt(500)).toDouble() : 0.0;
      final tins = (i % 7 == 0) ? (1 + rnd.nextInt(80)).toDouble() : 0.0;
      final kg = bags > 0 ? bags * (25 + rnd.nextInt(30)) : 0.0;
      final r = TradeReportItemRow(
        key: 'k$i',
        name: i % 10 == 0 ? 'SUGAR $i' : 'ITEM $i',
      );
      r.bags = bags;
      r.boxes = boxes;
      r.tins = tins;
      r.kg = kg;
      r.amountInr = (bags + boxes + tins) * 10;
      return r;
    });

    const q = 'sugar';
    final sw = Stopwatch()..start();
    final filtered = rows
        .where((r) => r.name.toLowerCase().contains(q))
        .toList(growable: false);
    final sorted =
        sortTradeReportItemsAll(filtered.toList(growable: false), TradeReportItemSort.highQty);
    sw.stop();

    // sanity: we did real work
    expect(sorted.isNotEmpty, true);
    expect(sw.elapsedMilliseconds, lessThan(300));
  });
}

