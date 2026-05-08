# CURRENT CONTEXT

_Update this file after each meaningful agent session._

## Last updated

- Date: 2026-05-08  
- Branch: `main` (verify with `git branch`)

## Active task

- **P0 matcher safety:** shipped first backend gate (`scanner_v2/pack_gate.py`): demotes `auto` item matches when **kg pack hints** (line vs catalog `default_kg_per_bag` / name) or **unit channel** (BAG vs piece/pcs) conflict. Covers v2+v3 scans via `_match_items`. Further work: ranking, aliases, supplier history (see `TASKS.md` Critical).

## Why assistants pause between messages

- Cursor/chat turns are **bounded**; **full ERP stability** is delivered as **chained commits**, not one infinite reply. Policies still require tracing dependents — next targets: search autocomplete, report parity, delete/cache.

## Important business rules (short)

- Scan → **draft** only; final purchase after wizard confirm + backend totals.
- No guessing matches; unit mismatch → force review.
- Reports must share one backend aggregation contract.

## Current screens / flows

- **Scan:** `ScanPurchaseV2Page` → **Draft wizard:** `PurchaseScanDraftWizardPage` (`/purchase/scan-draft`) → confirm → `scanPurchaseBillV2Update` + `scanPurchaseBillV2Confirm`.

## Latest code touchpoints

- `backend/app/services/scanner_v2/pack_gate.py`, `backend/app/services/scanner_v2/pipeline.py`
- `flutter_app/lib/features/purchase/presentation/scan_purchase_v2_page.dart`
- `flutter_app/lib/features/purchase/presentation/purchase_scan_draft_wizard_page.dart`
- `flutter_app/lib/core/router/app_router.dart`

## Blockers

- None recorded.

## Pending validation

- Full `flutter test` + `pytest` on CI/local before release.
- Manual: scan → wizard → create → dashboard total matches purchase detail.
