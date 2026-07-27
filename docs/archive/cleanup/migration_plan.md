# Flutter Cleanup Migration Plan

**Date:** 2026-06-03

## Step 0 — Baseline scan

```bash
cd flutter_app
dart run tool/find_dart_orphans.dart > ../docs/cleanup/orphan_scan_output.txt
flutter analyze
flutter test
```

Record baseline in `docs/TEST_RESULTS.md`.

---

## Step 1 — Documentation (complete)

- [x] `docs/cleanup/cleanup_report.md`
- [x] `docs/cleanup/migration_plan.md`
- [x] `docs/cleanup/verification_checklist.md`
- [x] `docs/cleanup/DEPRECATED_FILES.md`
- [x] `flutter_app/tool/find_dart_orphans.dart`

---

## Step 2 — Import normalization (low risk)

1. **Router** (`app_router.dart`):
   - `full_reports_page.dart` → `reports_shell_page.dart`, widget `ReportsShellPage`
   - `scan_purchase_page.dart` → `scan_purchase_v2_page.dart`, widget `ScanPurchaseV2Page`

2. **Optional follow-up** (no urgency): replace any `stock/.../barcode_scan_page.dart` imports with `barcode/...` (currently only export file references stock path).

3. Run `flutter analyze lib` after each file.

---

## Step 3 — Deprecation markers (no behavior change)

Add file-level DEPRECATED comments to:

- `item_wizard_page.dart`
- `catalog_item_purchase_history_page.dart`
- `home_insights_provider.dart`
- `page_transitions_v2.dart`
- `add_item_entry_page.dart`

Index in `DEPRECATED_FILES.md`.

---

## Step 4 — Shim retention (do not remove yet)

Keep until deep-link audit + one release cycle:

- `scan_purchase_page.dart` (wrapper)
- `catalog_add_item_page.dart`
- `update_stock_sheet.dart`
- `stock/presentation/barcode_scan_page.dart` (export)
- `dashboard/presentation/home_page.dart` (export)

---

## Step 5 — Optional delete PR (future, user approval)

Delete only when all gates in `verification_checklist.md` pass:

1. `page_transitions_v2.dart`
2. `home_insights_provider.dart`
3. `add_item_entry_page.dart`

**Defer:** `item_wizard_page.dart` (product sign-off).

---

## Step 6 — Provider consolidation (out of scope)

Do not merge `home_dashboard_provider` and `home_owner_dashboard_providers` in this pass.

---

## Rollback

All changes are import/router/doc only. Revert `app_router.dart` imports if analyze or tests fail.
