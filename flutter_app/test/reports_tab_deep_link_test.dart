import 'package:flutter_test/flutter_test.dart';
import 'package:harisree_warehouse/features/reports/reports_bi_tab.dart';

void main() {
  test('ReportsBiTabX.fromQuery maps primary tabs', () {
    expect(ReportsBiTabX.fromQuery('items'), ReportsBiTab.items);
    expect(ReportsBiTabX.fromQuery('purchase'), ReportsBiTab.purchases);
    expect(ReportsBiTabX.fromQuery('stock'), ReportsBiTab.stock);
    expect(ReportsBiTabX.fromQuery(null), isNull);
  });

  test('legacy tab queries map to primary tabs', () {
    expect(ReportsBiTabX.resolveFromQuery('movement'), ReportsBiTab.stock);
    expect(ReportsBiTabX.resolveFromQuery('activity'), ReportsBiTab.stock);
    expect(ReportsBiTabX.resolveFromQuery('dead'), ReportsBiTab.stock);
    expect(ReportsBiTabX.resolveFromQuery('suppliers'), ReportsBiTab.purchases);
    expect(ReportsBiTabX.resolveFromQuery('categories'), ReportsBiTab.items);
  });

  test('stock section from query', () {
    expect(ReportsBiTabX.stockSectionFromQuery('dead'), 'dead');
    expect(ReportsBiTabX.stockSectionFromQuery('fast'), 'fast');
  });
}
