# Production audit report — Sprint 1 + hardening program

**Scope:** Evidence-backed inventory for trade purchases, units/rate labels, calculation paths, scanner surfaces, and program milestone docs. **Not** a full security certification.

## Inventory generator

`python backend/scripts/sprint1_audit_collect.py > audit_signals.json`

Emits:

- `backend_routers_from_main` — from [`backend/app/main.py`](backend/app/main.py)
- `flutter_go_route_hints` — `path` / `name` from router-related Dart files
- `flutter_provider_files` — files under `lib/**/providers`
- `flutter_setstate_large_widgets` — presentation/widgets over 600 lines with `setState(` counts (rebuild-risk signal)
- `flutter_hints` — capped greps: `/kg`, `lineMoney`, `computePurchaseTotals`, Riverpod notifiers
- `backend_hints` — `line_money`, `compute_totals`, trade/report service grep buckets

## Backend routers (from `main.py`)

`admin`, `ai_chat`, `analytics`, `auth`, `billing`, `catalog`, `cloud_expense`, `contacts`, `dashboard`, `entries`, `health`, `me`, `media`, `price_intelligence`, `razorpay_webhook`, `realtime`, `reports_trade`, `search`, `trade_purchases`, `whatsapp_reports`.

## Severity table

| Severity | Area | Affected / signal | Repro / preconditions | Root cause | Recommended fix | Priority |
|----------|------|-------------------|------------------------|------------|-----------------|----------|
| **RESOLVED** | Client vs server totals when lines have charges | Wizard / PDF with line `delivered_rate` / line freight + header freight | Save vs preview | Flutter `computeTradeTotals` omitted line freight in roll-up and always added header freight | **Fixed:** `TradeCalcLine` carries line freight fields; `computeTradeTotals` mirrors `compute_totals`; PDF summary skips header freight/billty/delivered when lines have item-level charges (`flutter_app/lib/core/calc_engine.dart`, `purchase_invoice_pdf_layout.dart`). Tests: `flutter_app/test/calc_line_freight_parity_test.dart`, backend `test_trade_header_totals_parity.py`. | Done |
| **MEDIUM** | Stale `/kg` UI copy | Grep hits in comments or kg-weighted analytics | Reports metrics | Ambiguous basis vs pack rate | Explicit `wtd` labels + `dynamic_unit_label_engine` (Sprint 1) | MEDIUM |
| **MEDIUM** | Ledger rate suffix | Item history | Weight present but rate per bag | Old heuristic | `LedgerLineRow.purchaseRateDim` (Sprint 1) | MEDIUM |
| **LOW** | Large widget rebuilds | `purchase_item_entry_sheet`, `analytics_page`, `purchase_entry_wizard_v2` | Slow interactions | Many `setState` | Incremental Riverpod migration / `select` narrow watches (`PERFORMANCE_AUDIT.md`) | LOW |

## Program milestone artifacts (this delivery)

| Doc / asset | Purpose |
|-------------|---------|
| [`PERFORMANCE_AUDIT.md`](PERFORMANCE_AUDIT.md) | Phase 5 baseline template |
| [`FULL_PAGE_MATRIX.md`](FULL_PAGE_MATRIX.md) | Phase 6 route matrix |
| [`GLOBAL_SOFT_DELETE_AUDIT.md`](GLOBAL_SOFT_DELETE_AUDIT.md) | Phase 7 checklist (note: `trade_purchases` uses `status`, not `deleted_at`) |
| [`QA_MASTER_CHECKLIST.md`](QA_MASTER_CHECKLIST.md) | Phase 8 manual QA |
| [`DB_CONSISTENCY_AUDIT.md`](DB_CONSISTENCY_AUDIT.md) | Phase 9 + index SQL pointer |
| [`backend/sql/supabase_020_ocr_learning.sql`](backend/sql/supabase_020_ocr_learning.sql) | Phase 3 learning tables (apply when RLS ready) |
| [`backend/app/services/ocr_learning_service.py`](backend/app/services/ocr_learning_service.py) | Stub hooks for post-confirm learning |
| [`PRODUCTION_READINESS_SCORE.md`](PRODUCTION_READINESS_SCORE.md), [`REMAINING_RISKS.md`](REMAINING_RISKS.md), [`PERFORMANCE_BASELINE.md`](PERFORMANCE_BASELINE.md), [`ENTERPRISE_DEPLOYMENT_CHECKLIST.md`](ENTERPRISE_DEPLOYMENT_CHECKLIST.md), [`ALL_REMAINING_BLOCKERS.md`](ALL_REMAINING_BLOCKERS.md) | Phase 10 pack |

## Explicitly still open (not claimed complete)

- Full **SCAN_REVIEW_MODE** product polish and **alias consumption** in matcher + confirm wiring for `ocr_learning_service`.
- Measured performance SLIs and DB `EXPLAIN` proofs.
- Systematic soft-delete grep across every SQL path.
- Full E2E integration suite.
