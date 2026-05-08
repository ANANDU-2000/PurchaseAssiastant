# CURRENT CONTEXT

_Update this file after each meaningful agent session._

## Last updated

- Date: 2026-05-08  
- Branch: `main` (verify with `git branch`)

## Active task

- Enterprise purchase draft flow & Cursor policy alignment (`MASTER_CURSOR_RULES`, autonomous execution rules).

## Current screens / flows

- **Scan:** `ScanPurchaseV2Page` → **Draft wizard:** `PurchaseScanDraftWizardPage` (`/purchase/scan-draft`) → confirm → `scanPurchaseBillV2Update` + `scanPurchaseBillV2Confirm`.

## Latest code touchpoints

- `flutter_app/lib/features/purchase/presentation/scan_purchase_v2_page.dart`
- `flutter_app/lib/features/purchase/presentation/purchase_scan_draft_wizard_page.dart`
- `flutter_app/lib/features/purchase/presentation/scan_purchase_draft_logic.dart`
- `flutter_app/lib/core/router/app_router.dart`

## Blockers

- None recorded.

## Pending validation

- Full `flutter test` + `pytest` on CI/local before release.
- Manual: scan → wizard → create → dashboard total matches purchase detail.
