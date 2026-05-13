# Report PDF — summary system (trade statement)

## Problem

Trade purchases **statement PDF** listed line rows but the footer only showed **kg + Rs**, missing **bags / boxes / tins** and weak **period / generated** metadata.

## Solution (SSOT)

Footer totals now come from **`buildTradeReportAgg(purchases)`** — the same aggregate engine as in-app **Reports** and dashboard pack summaries (`TradeReportTotals`).

### Implemented fields

- **Bags / Boxes / Tins · KG** — single summary line (omits zero components).
- **Total amount** — `totals.inr` (sum of `reportLineAmountInr` on classified pack lines).
- **Purchases with pack lines** — `totals.deals`.
- **Period** — explicit `from → to` (local statement window).
- **Generated** — `DateTime.now()` formatted (`dd MMM yyyy, h:mm a`).

### Code

- `flutter_app/lib/core/services/reports_pdf.dart` → `buildTradeStatementSsotPdfBytes`
- Engine: `flutter_app/lib/core/reporting/trade_report_aggregate.dart` → `buildTradeReportAgg`

## Consistency note

Detail **table rows** still come from `buildTradeStatementLines` (classifies with `reportClassifyPackKind`). Aggregate footer uses `reportEffectivePack` paths inside `buildTradeReportAgg`. If a line appears in the table, it is included in totals; edge mismatches should be investigated against `reportEffectivePack` vs `reportClassifyPackKind` (document any future alignment work here).

## Cross-links

- `EXPORT_AND_PRINT_LAYOUT_GUIDE.md`
- `FINAL_TRADER_UX_PRODUCTION_READINESS.md`
