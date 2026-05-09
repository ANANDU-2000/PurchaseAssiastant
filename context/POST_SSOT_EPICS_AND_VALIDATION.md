# Post-SSOT epics and production validation

This file tracks follow-up work after the canonical **line money** contract (API `line_total` = tax/discount-inclusive purchase; `line_landing_gross` = pre-tax gross). It replaces scattered “next phase” notes for reporting UX, scanner AI, performance, and go-live checks.

---

## Epic: Reports and dashboard UX

**Goal:** Repro-driven fixes for layout, filters, empty states, and keyboard/safe-area behavior once report totals no longer need client-side defensive fallbacks.

**Suggested tickets (each needs: device, steps, expected vs actual):**

1. Reports period filters and chip state after navigation back from detail.
2. Dashboard summary cards: loading skeleton, error retry, empty business state.
3. Sticky CTA / bottom sheet overlap with keyboard on small phones.
4. Filter sheet: scroll vs nested scroll conflicts.
5. “View more” / expansion consistency on purchase history vs reports.

**Out of scope:** Changing purchase math (handled by backend SSOT).

---

## Epic: AI scanner stabilization (non-math)

**Goal:** Improve scan confidence, correction flows, and multi-page handling without changing authoritative totals (still `line_totals_service` / adapter after confirm).

**Milestone ideas:**

1. Confidence ranking and low-confidence surfacing in review UI.
2. Supplier/broker correction learning or shortcuts (explicit user confirm only).
3. Multi-page invoice stitching and page order.
4. OCR repair / crop UX without double-submitting purchases.

**Boundary:** Scanner preview may show draft line money; confirmed purchases remain server totals only.

**Flutter review (`scan_purchase_v2_page`):** overall confidence + `needs_review`, optional OCR read-quality chip (`scan_meta.ocr_extract_confidence`), `TOTAL_MISMATCH` callout, supplier/broker `match_state` chips + “On bill” raw text when it differs from the match, severity-sorted warnings with BLOCKER/WARN/INFO badges, item rows show bill line vs catalog when they differ + match state in trailing column, bill image preview capped (~260px) + scroll/bottom bar respect keyboard insets. **`purchase_bill_scan_panel`** (embedded wizard `/scan-purchase` legacy wire) now shows the same confidence summary card via shared `scan_review_shared.dart`, plus a structured “Scanner warnings” list from `meta.parse_warnings` (string heuristics for TOTAL_MISMATCH); server note stays separate.

---

## Epic: Performance (reports and dashboard)

**Prerequisites:** Stable aggregate definitions (post line-money contract) so cache keys and SQL rollups do not drift.

**Approach:**

1. Measure: log or APM slow endpoints (`reports_trade`, dashboard month rollup, list trade purchases with large offsets).
2. Add pagination or tighter default limits where the UI does not need full history.
3. Indexes: follow query plans on filtered date ranges + `business_id` + `status`.
4. Caching: short TTL for read-heavy aggregates **after** Phase 1 money semantics are frozen in production.

---

## Golden-path references (code)

| Step | Automated coverage |
|------|---------------------|
| Create trade purchase + tax/discount lines | `backend/tests/test_trade_purchases.py::test_get_trade_purchase_line_total_is_line_money_landing_gross_is_pre_tax` |
| Parse API line fields in Flutter | `flutter_app/test/trade_purchase_line_money_contract_test.dart` |
| Report aggregates | `flutter_app/test/trade_report_aggregate_test.dart` |
| Smart unit classifier | `flutter_app/test/smart_unit_classifier_test.dart` |
| Scanner supplier fuzzy (mixed script) | `backend/tests/scanner_v2/test_matcher_buckets.py` |

---

## CI regression gates

Workflow: [`.github/workflows/ci.yml`](.github/workflows/ci.yml).

- **backend:** `pytest` (trade purchases, scanner matcher, etc.).
- **flutter-ssot:** Runs only `trade_purchase_line_money_contract_test`, `trade_report_aggregate_test`, and `smart_unit_classifier_test` for fast SSOT signal.
- **flutter:** `flutter analyze` + full `flutter test`.

---

## Operator runbook — bill scan

- Scan routes return **preview only** (`ScanResult` + `scan_token`); they never persist a finalized purchase.
- **Confirm** paths apply server validation and SSOT line money; clients must not override authoritative totals.
- Use `confidence_score`, row-level `confidence`, `scan_meta.ocr_extract_confidence` (when OCR fallback ran), and `warnings[]` to drive review—not silent amount fixes.

---

## Epic: Mobile UX (detailed repro tickets)

Use per-ticket: **Device / OS / build** · **Screen** · **Steps** · **Expected** · **Actual** · **Evidence**.

| ID | Area | Capture |
|----|------|--------|
| M-1 | Purchase wizard / item sheet | Keyboard vs sticky CTA overlap |
| M-2 | Purchase review / tally | `viewInsets` padding vs double `SafeArea` |
| M-3 | Reports | Horizontal overflow; clipped charts/tables |
| M-4 | Reports filters | Bottom sheet + nested scroll conflict |
| M-5 | Global search | List jank when query changes |
| M-6 | Scan review | Scroll jumps on edit; animation on each keystroke |

**Patterns:** one primary scroll; bottom pad for insets where fixed CTA exists; narrow Riverpod rebuilds (`select`).

---

## Performance inventory (measure first)

| Area | Entry | Note |
|------|--------|------|
| Trade list | `GET …/trade-purchases` | Server clamps `limit` to 50; paginate in Flutter. |
| Reports | `reports_trade` router | TTL caches; validate key includes date range + `business_id`. |
| Dashboard | `dashboard` router | Bounded reads where `run_read_budget_bounded` applies. |
| Scanner | `scanner_v2` preprocess + Vision | Cap variant count if latency spikes. |
| Flutter lists | History / reports / ledger | `ListView.builder`, stable keys, avoid wide rebuilds. |

---

## Validation / repair (design-first)

**Read-only spike (no auto money fixes):** (1) compare scan trace preview totals to post-confirm purchase; (2) compare report rollups to `trade_line_amount_expr` sums for same window; (3) document cache invalidation expectations after writes.

**Future repair:** non-financial fields only, explicit user confirm; financial fixes = manual or audited batch.

**Historical rows:** older purchases may have legacy unit snapshots or null `line_total` in DB (SQL `coalesce` uses computed gross). Prefer controlled backfill scripts (separate change list) over silent client-side “fixes”.

---

## Production validation checklist

Run before a major release or after backend/Flutter contract changes.

### API (manual or scripted)

- [ ] Register / login; create business if needed.
- [ ] Create catalog item + trade purchase with **discount + tax** on a line.
- [ ] `GET …/trade-purchases/{id}`: `line_landing_gross` equals pre-tax gross; `line_total` equals tax/discount-inclusive amount (`test_get_trade_purchase_line_total_is_line_money_landing_gross_is_pre_tax`).
- [ ] Reports trade endpoint for the same period: totals align with expectation for stored `line_total` (see `trade_line_amount_expr` docstring for NULL legacy behavior).
- [ ] Partial payment / mark paid still derives status correctly.

### Flutter

- [ ] `flutter test test/trade_purchase_line_money_contract_test.dart`
- [ ] `flutter test test/trade_report_aggregate_test.dart`
- [ ] `flutter test test/smart_unit_classifier_test.dart`
- [ ] Open supplier ledger: line intel amount matches `reportLineAmountInr` (uses `line_total` when present).

### PDF / statements

- [ ] Generate supplier or item statement for a purchase with tax/discount; spot-check line amounts against API `line_total`.

### Scanner

- [ ] Scan → preview line amounts → save draft → open wizard: preview money matches post-save line totals within rounding.
- [ ] Mixed Malayalam + English supplier header still surfaces correct supplier (`test_mixed_script_supplier_header_prefers_latin_traders_name`).

### Automated regression (CI)

- [ ] `pytest` (backend job)
- [ ] `flutter-ssot` job
- [ ] `flutter analyze` + full `flutter test` (flutter job)
