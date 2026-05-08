# CURRENT CONTEXT

_Update this file after each meaningful agent session._

## Last updated

- Date: 2026-05-08  
- Branch: `main` (verify with `git branch`)

## Active task

- Restored **verbatim** `MASTER_CURSOR_RULES.md` + `AUTONOMOUS_CURSOR_EXECUTION_RULES.md` (full policy text, not summaries).
- Restructured root `TASKS.md` into **Critical / In progress / Pending / Completed / Blocked** per autonomous rules.
- **Why earlier work looked “stopped”:** a documentation-only commit intentionally summarized policies; that violated your zero-interruption / full-text expectation — corrected now.

## Important business rules (short)

- Scan → **draft** only; final purchase after wizard confirm + backend totals.
- No guessing matches; unit mismatch → force review.
- Reports must share one backend aggregation contract.

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
