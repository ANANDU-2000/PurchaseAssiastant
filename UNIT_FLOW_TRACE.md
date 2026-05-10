# Unit Flow Trace

## Purpose
Production unit synchronization now has one target truth: persisted catalog unit metadata resolved through backend `unit_resolution_service`, then consumed in Flutter through `ResolvedItemUnitContext`.

## Flow Map

### New Purchase / Wizard Item Entry
- Route: `flutter_app/lib/core/router/app_router.dart` -> `/purchase/new`.
- Main page: `flutter_app/lib/features/purchase/presentation/purchase_entry_wizard_v2.dart`.
- Item sheet: `flutter_app/lib/features/purchase/presentation/widgets/purchase_item_entry_sheet.dart`.
- Catalog metadata enters through `catalogItemsListProvider` and optional `resolveCatalogItem` fresh fetch.
- Local draft conversion happens through `PurchaseLineDraft.fromLineMap` in `flutter_app/lib/features/purchase/domain/purchase_draft.dart`.
- Repair: item-sheet labels/dropdown now resolve through `ResolvedItemUnitContext`, which consumes `unit_resolution` before local classifier fallback.

### Scanner Purchase
- Scan pages: `scan_purchase_v2_page.dart`, `purchase_scan_draft_wizard_page.dart`, `scan_draft_edit_item_sheet.dart`.
- Backend scanner: `backend/app/services/scanner_v2/pipeline.py`, `purchase_scan_ai.py`, `scanner_trade_line_adapter.py`.
- Scanner sends/derives `rate_context`; preview validates via `trade_preview_service.py`.
- Risk remaining: scanner preview widgets still display `unit_type` directly in some places; they must consume persisted preview `rate_context` or `ResolvedItemUnitContext` when mapped to catalog.

### Edit Purchase / History Edit
- History opens `/purchase/edit/:id` from `purchase_detail_page.dart`, `item_history_page.dart`, ledger cards, and catalog item history.
- Existing persisted lines hydrate through `trade_purchase_detail_provider` then `purchaseDraftProvider` using `PurchaseLineDraft.fromLineMap`.
- Risk: historical rows may carry legacy `piece`/`kg`; backend output now supplies `rate_context`, and Flutter display helpers should prefer it.

### Quick Add Item
- Quick add UI: `catalog_add_item_page.dart`.
- Backend create/update: `backend/app/routers/catalog.py`.
- Backend create already calls `resolve_for_catalog_item` and `merge_unit_resolution_into_catalog_row`.
- Risk: UI still allows `piece` as catalog unit for creation. Production metadata repair maps known retail packs to BOX/TIN/BAG through canonical profiles.

### Report / Dashboard Item Edit
- Item rows open through `core/navigation/open_trade_item_from_report.dart` from Home, Contacts, Analytics, and Reports.
- Report data is trade-backed through `hexa_api.dart` endpoints `/reports/trade-items`, `/trade-suppliers`, `/trade-types`, `/home-overview`.
- Home non-category tabs use `homeShellReportsProvider`; fixed connectivity hard-timeouts prevent infinite loading.

## Stale State Sources Found
- `_unitCtrl` in `PurchaseItemEntrySheet` was a local truth and could retain `piece`/`kg` after catalog selection.
- `DropdownButtonFormField.initialValue` could be rebuilt with stale local value; now menu is bounded and value is normalized through context.
- `homeShellReportsProvider` could hang before API calls if `Connectivity().checkConnectivity()` never returned; now capped.
- Backend `resolve_for_catalog_item` previously trusted persisted `PCS` rows before strong text rules; now unverified legacy PCS can be overridden by strong package rules.
