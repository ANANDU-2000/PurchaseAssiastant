# QA master checklist (Phase 8)

Run before release candidate. Mark **Pass / Fail / N/A** per build.

## Purchases

- [ ] Create draft → add bag line (kg/bag) → terms freight → save → totals match server
- [ ] Line delivered + header freight: wizard total matches `compute_totals` (Flutter `computeTradeTotals` parity)
- [ ] Edit purchase → change qty → totals refresh
- [ ] Delete (soft) purchase → disappears from history
- [ ] PDF open: line totals vs `total_amount` (mismatch note if recompute differs)

## Scan

- [ ] Scan v2 upload → review confidence card → edit line → confirm creates purchase
- [ ] Invalid scan_token → 400

## Reports / dashboard

- [ ] Reports date range + supplier filter
- [ ] Dashboard home loads with empty data (skeleton / empty state)

## Catalog / contacts

- [ ] New item → appears in search
- [ ] Supplier ledger filters

## Auth / settings

- [ ] Login / logout
- [ ] Business profile save

## Automated (CI)

- [ ] `pytest` (backend)
- [ ] `flutter analyze` + `flutter test`

## Regression highlights

- `flutter_app/test/calc_line_freight_parity_test.dart` — line charges vs header freight
- `backend/tests/test_trade_header_totals_parity.py` — server totals matrix
