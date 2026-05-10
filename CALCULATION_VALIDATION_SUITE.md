# Calculation validation suite — trade purchases

Authoritative money for trade purchases is computed on the **backend**. Flutter `computeTradeTotals` / `computePurchaseTotals` now mirror `compute_totals` for **line money + line item freight** and **skip header freight / header billty / header delivered** when any line has item-level charges (same rule as [`trade_purchase_service.compute_totals`](backend/app/services/trade_purchase_service.py)).

## SSOT modules (backend)

| Module | Role |
|--------|------|
| `backend/app/services/line_totals_service.py` | `line_gross_base`, `line_money`, `line_item_freight_charges`, line weight |
| `backend/app/services/aggregate_totals_service.py` | Rolled landing / selling / profit aggregates |
| `backend/app/services/trade_purchase_service.py` | `compute_totals`: header discount, header freight (skipped when any line has item-level charges), header commission modes, billty/delivered |

## Invariants

1. **Profit is not included in purchase total** — `total_amount` reflects purchase-side charges only; margin/profit is reported separately (`test_profit_not_added_into_purchase_total` in `test_trade_header_totals_parity.py`).
2. **Line total** uses line discount + tax on line gross (`line_money`).
3. **Header discount** applies to the sum of (line money + line item charges) before header freight and percent commission (percent commission basis is the post-discount subtotal, pre-freight — matches `compute_totals`).

## Automated tests (map)

| File | What it guards |
|------|----------------|
| `backend/tests/test_trade_header_totals_parity.py` | `compute_totals` vs line rollups; header freight skip; header discount + freight + commission; line tax; line delivered-only suppresses header freight; `flat_bag` / `flat_kg` commission |
| `backend/tests/test_trade_query_vs_line_totals_parity.py` | (If present) SQL vs Python line totals consistency |
| `flutter_app/test/calc_header_parity_test.dart` | One Dart fixture aligned with pytest header discount + freight + percent commission |
| `flutter_app/test/calc_line_freight_parity_test.dart` | Line delivered / line freight vs header freight and header billty-delivered skip |
| `flutter_app/test/purchase_pdf_search_parity_test.dart` | PDF/search strings vs purchase payload (run when changing PDF or totals display) |

## Manual verification checklist

1. **Wizard:** Create a 2-line bag purchase with header discount 10%, freight ₹100 separate, commission 10% — footer should match server total after save (watch for line-level delivered/freight edge case above).
2. **Reports trade:** Date range + supplier filter; spot-check line totals vs purchase detail.
3. **PDF:** Generate PDF for a purchase with tax and discount lines; compare amounts to detail screen (`purchase_pdf_search_parity_test.dart`).

## Commands

```bash
cd backend && python -m pytest tests/test_trade_header_totals_parity.py -q
cd flutter_app && flutter test test/calc_header_parity_test.dart test/calc_line_freight_parity_test.dart test/dynamic_unit_label_engine_test.dart
```
