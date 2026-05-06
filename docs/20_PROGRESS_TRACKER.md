# 20 — Progress Tracker (Master Rebuild)

## Current Goal

Rebuild purchase workflow (logic + UI + reports + validations + scanner) into a stable wholesale trading app with correct units and zero calculation errors.

## Current Task

Dynamic form engine + unit-system lockdown: enforce `KG|BAG|BOX|TIN|PCS`, remove user-facing `sack`, and make BOX/TIN count-only (no kg tracking) in default wholesale mode.

## Completed

- Created master rebuild docs `docs/00_...md` through `docs/22_...md`.
- Scanner v2 backend foundations created (`backend/app/services/scanner_v2/*`) with tests.
- Unit system updates:
  - Backend: normalize `sack`→`bag` in scan parsers; standardize `pc/pcs`→`piece`; BOX/TIN kg totals disabled in `_line_total_weight()`
  - Flutter: removed `sack` from unit dropdown; legacy `sack` treated as `bag` for totals; BOX/TIN kg totals disabled in `linePhysicalWeightKg()`
  - Dynamic form engine (default wholesale mode): BOX/TIN advanced weight/item fields hidden + cleared on unit change; BOX/TIN treated count-only
  - Validation: `pytest` green; `flutter analyze` + `flutter test` green
- Reports aggregation aligned:
  - Backend report kg totals now count only BAG + KG (BOX/TIN weights ignored even for old rows)
  - Flutter reports aggregation now treats BOX/TIN as count-only (no kg totals), with updated tests
- PDF layout aligned:
  - Items table is now `Item | Qty | Unit | P Rate | S Rate | Total`
  - Removed KG/Tax columns from table (compact wholesale-friendly layout)
- Scanner v2 backend flow wired:
  - `/v1/me/scan-purchase-v2` returns `ScanResult` + `scan_token` (preview only, never saves)
  - `/v1/me/scan-purchase-v2/correct` upserts `catalog_aliases` (learning)
  - `/v1/me/scan-purchase-v2/confirm` converts preview → validated `TradePurchaseCreateRequest` → saves
  - Backend tests green
- Offline + refresh wired:
  - Offline queue for new purchase saves on network failure (wizard)
  - Background sync periodically retries queued saves and auto-refreshes caches on success
  - Rapid double-tap queue dedupe via fingerprint

## Pending

- Deterministic calculation engine pass (single SSOT everywhere; eliminate duplicate math)
- Offline queue + auto refresh engine + duplicate prevention v2

## Bugs

None logged.

## Blockers

None.

## Next Action

Backend field normalization/strip-by-unit for create/update (BOX/TIN count-only hardening).

## Validation Status

- Docs: in progress
- Backend: partial (scanner_v2 foundations exist)
- Flutter: pending

