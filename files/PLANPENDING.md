# HARISREE Purchase Assistant — Cursor Pro Prompt Pack
## Complete Bug Fix + Feature Sprint | 2026-05-28

---

## How to Use This Pack

1. Open Cursor Pro in the `PurchaseAssiastant-main` repo root.
2. Run prompts **in order** — each file is one focused Cursor session.
3. Each file is self-contained: paste the full content into Cursor chat.
4. After each session, run `flutter analyze` and fix any new errors before proceeding.

---

## Prompt Files (Run in This Order)

| # | File | Area | Priority |
|---|------|------|----------|
| 01 | `01_STOCK_PAGE_TIME_FILTER.md` | Stock page period filter + icons | P0 |
| 02 | `02_STOCK_FILTER_SUBCATEGORY_SEARCH.md` | Subcategory suggestions fix | P0 |
| 03 | `03_SYSTEM_STOCK_CALCULATION.md` | System stock not updating | P0 |
| 04 | `04_ITEM_DETAIL_EDIT.md` | Item detail edit mode broken | P0 |
| 05 | `05_ITEM_DETAIL_OPENING_REORDER.md` | Opening stock + reorder level from detail | P0 |
| 06 | `06_PURCHASE_FORM_KEYBOARD_SUGGESTIONS.md` | Add purchase keyboard/suggestion overlap | P0 |
| 07 | `07_NOTIFICATIONS_ALERTS_FIX.md` | Notification cards not showing | P0 |
| 08 | `08_LOW_STOCK_PAGE_FIX.md` | Low stock page completely broken | P0 |
| 09 | `09_PO_PAGE_WHITESPACE.md` | Purchase orders page whitespace + time filter | P1 |
| 10 | `10_STAFF_VERIFICATION_WORKFLOW.md` | Staff verify purchase at warehouse | P1 |
| 11 | `11_EXPORT_BACKUP.md` | PDF + Excel export, auto-backup | P1 |
| 12 | `12_OWNER_TASKS_CHECKLIST.md` | Owner task/checklist management | P2 |
| 13 | `13_ML_SUGGESTIONS.md` | ML model for better suggestions | P2 |
| 14 | `14_PERFORMANCE_SYNC.md` | Performance, prompt sync, realtime | P2 |

---

## Root Cause Summary (Code-Verified)

| Bug | Root Cause |
|-----|-----------|
| System stock wrong | `patch_trade_purchase_delivery` may not be calling `apply_confirmed_purchase_stock` on all delivery paths |
| Item edit broken | `context.push('/catalog/item/$itemId?edit=1')` — router shows same `ItemDetailPage`, no edit query param handler exists |
| Subcategory suggestions broken | `_OperationalFilterBody` subcategory field uses plain `TextField` not `InlineSearchField` with suggestion overlay |
| Keyboard covers form | `showModalBottomSheet` with `isScrollControlled: true` but form fields inside are not wrapped in `KeyboardSafeFormViewport` |
| Notifications empty | `warehouseAlertNotificationItemsProvider` items exist but `NotificationAlertCard` ListView has zero `itemCount` when filter mismatch |
| Low stock all zeros | `stockStatusCountsProvider` → backend `stock_alerts_summary` counting wrong — `total_items` uses `current_stock > 0` filter not full catalog |
| No time filter on stock | `StockOperationalTopBar` has no period picker; `HomePeriod` enum exists but UI chip never shown |
