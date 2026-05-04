import 'package:hexa_purchase_assistant/core/models/trade_purchase_models.dart';
import 'package:hexa_purchase_assistant/core/reporting/trade_report_aggregate.dart';
import 'package:flutter_test/flutter_test.dart';

TradePurchase _purchase({
  required String id,
  required List<TradePurchaseLine> lines,
  DateTime? purchaseDate,
}) {
  return TradePurchase(
    id: id,
    humanId: id,
    purchaseDate: purchaseDate ?? DateTime(2026, 1, 15),
    paidAmount: 0,
    totalAmount: 0,
    storedStatus: 'paid',
    derivedStatus: 'paid',
    remaining: 0,
    lines: lines,
  );
}

void main() {
  test('bag: kg from qty × kg_per_unit', () {
    final p = _purchase(
      id: 'a',
      lines: [
        TradePurchaseLine(
          id: 'l1',
          itemName: 'Rice',
          qty: 4,
          unit: 'bag',
          landingCost: 100,
          lineTotal: 400,
          kgPerUnit: 50,
        ),
      ],
    );
    final agg = buildTradeReportAgg([p]);
    expect(agg.totals.bags, 4);
    expect(agg.totals.kg, 200);
    expect(agg.totals.inr, 400);
    expect(buildTradeStatementLines([p]).length, 1);
  });

  test('box: kg from qty × items_per_box × weight_per_item', () {
    final p = _purchase(
      id: 'b',
      lines: [
        TradePurchaseLine(
          id: 'l1',
          itemName: 'Oil',
          qty: 3,
          unit: 'BOX',
          landingCost: 10,
          lineTotal: 300,
          itemsPerBox: 12,
          weightPerItem: 0.5,
        ),
      ],
    );
    final kg = reportLineKg(p.lines.first);
    expect(kg, 3 * 12 * 0.5);

    final aggAll = buildTradeReportAgg([p]);
    expect(aggAll.totals.boxes, 3);
    expect(aggAll.itemsBox.length, 1);

    final bagsOnly = buildTradeReportAgg([p], onlyKind: ReportPackKind.bag);
    expect(bagsOnly.totals.bags, 0);
    expect(bagsOnly.totals.kg, 0);
    expect(buildTradeStatementLines([p]).length, 1);
  });

  test('tin: kg from qty × weight_per_tin', () {
    final p = _purchase(
      id: 'c',
      lines: [
        TradePurchaseLine(
          id: 'l1',
          itemName: 'Ghee',
          qty: 5,
          unit: 'tin',
          landingCost: 20,
          lineTotal: 500,
          weightPerTin: 15,
        ),
      ],
    );
    final agg = buildTradeReportAgg([p]);
    expect(agg.totals.tins, 5);
    expect(agg.totals.kg, 75);
  });

  test('classified lines counted once: multi-line purchase', () {
    final p = _purchase(
      id: 'd',
      lines: [
        TradePurchaseLine(
          id: 'l1',
          itemName: 'A',
          qty: 2,
          unit: 'bag',
          landingCost: 1,
          lineTotal: 2,
          kgPerUnit: 10,
        ),
        TradePurchaseLine(
          id: 'l2',
          itemName: 'B',
          qty: 1,
          unit: 'box',
          landingCost: 1,
          lineTotal: 1,
          kgPerBox: 24,
        ),
      ],
    );
    final stm = buildTradeStatementLines([p]);
    expect(stm.length, 2);
    final agg = buildTradeReportAgg([p]);
    expect(agg.totals.deals, 1);
    expect(agg.totals.inr, closeTo(3, 1e-6));
    expect(
      agg.itemsBag.fold<double>(0, (s, r) => s + r.bags),
      2,
    );
    expect(
      agg.itemsBox.fold<double>(0, (s, r) => s + r.boxes),
      1,
    );
  });

  test('unclassified unit is skipped', () {
    final p = _purchase(
      id: 'e',
      lines: [
        TradePurchaseLine(
          id: 'l1',
          itemName: 'X',
          qty: 99,
          unit: 'unknown',
          landingCost: 1,
          lineTotal: 99,
        ),
      ],
    );
    final agg = buildTradeReportAgg([p]);
    expect(agg.totals.deals, 0);
    expect(agg.itemsBag, isEmpty);
    expect(buildTradeStatementLines([p]), isEmpty);
  });

  test('itemsAll merges packs per item; latest sort uses lastPurchaseDate', () {
    final pOld = _purchase(
      id: 'old',
      purchaseDate: DateTime(2026, 1, 1),
      lines: [
        TradePurchaseLine(
          id: 'l1',
          itemName: 'Wheat',
          qty: 2,
          unit: 'bag',
          landingCost: 10,
          lineTotal: 20,
          kgPerUnit: 50,
        ),
      ],
    );
    final pNew = _purchase(
      id: 'new',
      purchaseDate: DateTime(2026, 3, 1),
      lines: [
        TradePurchaseLine(
          id: 'l2',
          itemName: 'Wheat',
          qty: 1,
          unit: 'bag',
          landingCost: 10,
          lineTotal: 10,
          kgPerUnit: 50,
        ),
      ],
    );
    final agg = buildTradeReportAgg([pOld, pNew]);
    expect(agg.itemsAll.length, 1);
    final row = agg.itemsAll.first;
    expect(row.bags, 3);
    expect(row.lastPurchaseDate, DateTime(2026, 3, 1));

    final riceOld = _purchase(
      id: 'a',
      purchaseDate: DateTime(2026, 1, 10),
      lines: [
        TradePurchaseLine(
          id: 'la',
          itemName: 'Rice',
          qty: 1,
          unit: 'bag',
          landingCost: 1,
          lineTotal: 1,
          kgPerUnit: 1,
        ),
      ],
    );
    final riceNew = _purchase(
      id: 'b',
      purchaseDate: DateTime(2026, 6, 1),
      lines: [
        TradePurchaseLine(
          id: 'lb',
          itemName: 'Rice',
          qty: 1,
          unit: 'bag',
          landingCost: 1,
          lineTotal: 1,
          kgPerUnit: 1,
        ),
      ],
    );
    final agg2 = buildTradeReportAgg([riceOld, pOld, riceNew]);
    final latest = sortTradeReportItemsAll(
      List.of(agg2.itemsAll),
      TradeReportItemSort.latest,
    );
    expect(latest.first.name, 'Rice');
  });
}
