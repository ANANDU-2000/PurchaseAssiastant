# CURRENT CONTEXT

_Update this file after each meaningful agent session._

## Last updated

- Date: 2026-05-08  
- Branch: verify with `git branch`

## Active task

- **Unified AI scan → manual purchase wizard:** Scan preview stays thin; **`PurchaseEntryWizardV2`** is the only heavy editor; save from AI session uses **`scan_token`** + `/scan-purchase-v2/update` + `/confirm` (not direct OCR create).
- **Next (backlog):** DB-backed aliases + pg_trgm (`TASKS.md`); ERP table / viewport polish.

## Why assistants pause between messages

- Cursor turns are **bounded**; large MASTER checklists land as **incremental commits**. Open rows in **`BUGS.md`** / **`TASKS.md`** are backlog, not ignored.

## Important business rules (short)

- Scan → **draft only**; final purchase only after user completes wizard + backend recalculation + confirm.
- No guessing matches; unit mismatch → force review (see **`MATCH_ENGINE.md`**).
- Dashboard KPIs: one backend contract; Flutter busts caches on mutation (`invalidateBusinessAggregates`).

## Current screens / flows

- **Scan:** `ScanPurchaseV2Page` → **Continue** → `/purchase/new` with `initialDraft` + `extra.aiScan` (`token`, `baseScan`).
- **Legacy:** `/purchase/scan-draft` (`PurchaseScanDraftWizardPage`) → **redirect** to `/purchase/new` with same extra (deep links / old bookmarks).
- **Manual:** `/purchase/new` without `aiScan` → POST trade purchase as before.

Wizard steps (AI bill titles in app bar): **Supplier & broker** → **Terms & charges** → **Match items** → **Review & save**. Same step order as manual entry; titles differ only when `aiScan` is present.

## Latest code touchpoints

- `flutter_app/lib/features/purchase/mapping/ai_scan_purchase_draft_map.dart` — ScanResult ↔ PurchaseDraft
- `backend/app/routers/search.py` — `/search` relevance ranking + optional `supplier_id`
- `flutter_app/lib/core/api/hexa_api.dart` — `unifiedSearch(..., supplierId:)`
- `flutter_app/lib/shared/widgets/inline_search_field.dart` — `InlineSearchItem.sortBoost`
- `flutter_app/lib/features/purchase/presentation/purchase_entry_wizard_v2.dart` — AI save branch; AI step titles; passes `preferredSupplierId` into item sheet
- `flutter_app/lib/features/purchase/presentation/scan_purchase_v2_page.dart` — `_openPurchaseEntryFromScan`; passes scan `supplier.matched_id` into preview item edit → `unifiedSearch`
- `flutter_app/lib/features/purchase/presentation/scan_draft_edit_item_sheet.dart` — AI scan line editor; debounced `/search`
- `flutter_app/lib/features/purchase/presentation/scan_purchase_draft_logic.dart` — `scanPurchaseUpdateAndConfirm`
- `flutter_app/lib/features/purchase/presentation/widgets/purchase_bill_scan_panel.dart` — embedded scan; `/search` item autocomplete parity with AI scan v2
- `flutter_app/lib/features/purchase/presentation/widgets/purchase_item_entry_sheet.dart` — catalog typeahead + supplier `sortBoost` when ranks tie
- `flutter_app/lib/core/router/app_router.dart` — parses `extra.aiScan`
- `flutter_app/test/ai_scan_purchase_draft_map_test.dart`

## Blockers

- None recorded.

## Pending validation

- Full `flutter test` / `pytest` before release.
