# Final production entry flow — checklist

## Preconditions

- Supplier chosen on Party step (wizard still enforces).
- Catalog list warm (compact or full per deployment).

## Happy path

1. Open **Add item**
2. Search item → pick row
3. Enter qty (bags)
4. Enter purchase rate + selling rate (same row)
5. Leave **Tax ON** (default) or **Tax OFF** for exempt
6. Read 4-line preview
7. Tap **Save**

## Regression matrix

| Case | Expect |
|------|--------|
| Tax OFF | `tax_percent` saved `0`; GST ₹0 in preview |
| Tax ON, catalog 5% | Tax matches 5% of taxable base |
| Bag + kg/bag | Qty mode toggle fits one line |
| Full-page + IME | Save buttons visible above keyboard |
| Edit old inclusive line | Advanced shows legacy controls; saving still valid |

## Automated

- `flutter analyze`
- `flutter test test/trade_purchase_line_money_contract_test.dart test/purchase_draft_calc_test.dart`
