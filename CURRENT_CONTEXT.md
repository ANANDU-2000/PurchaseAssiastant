# CURRENT CONTEXT

_Update this file after each meaningful agent session._

## Last updated

- Date: 2026-05-08  
- Branch: `main` (verify with `git branch`)

## Active task

- Policies on disk: **verbatim** `context/rules/MASTER_CURSOR_RULES.md` + `AUTONOMOUS_CURSOR_EXECUTION_RULES.md` (confirmed ends `UI demo builder.` / `FULL SYSTEM STABLE.` — no merged files).
- `TASKS.md` section order matches autonomous spec: **Pending → In Progress → Completed → Blocked → Critical**.

## Why an assistant “stops” (platform limits, not ERP preference)

- Chat turns end after a **bounded amount of work** (commits, files, tests).
- **“Full system stable”** for every bullet in your rules is **multi-sprint** engineering; it is executed as **chained tasks** from `TASKS.md` / `Critical`, not one infinite reply.
- Next coding slice should start from **P0 Critical** (item match + unit safety) **after** tracing matcher + catalog schema in repo (no guessing).

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
