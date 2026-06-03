# Deprecated Flutter Files

Do not use in new code. Removal scheduled only after zero-reference verification (see `verification_checklist.md`).

| File | Since | Replacement | Delete priority |
|------|-------|-------------|-----------------|
| `lib/features/contacts/presentation/item_wizard_page.dart` | 2026-06-03 | `CatalogItemCreatePage` (`/catalog/item/create`) | Deferred (large; product review) |
| `lib/features/catalog/presentation/catalog_item_purchase_history_page.dart` | 2026-06-03 | `ItemHistoryPage`, item detail trade section | Low |
| `lib/core/providers/home_insights_provider.dart` | 2026-06-03 | None (unused) | High (after verify) |
| `lib/core/router/page_transitions_v2.dart` | 2026-06-03 | `page_transitions.dart` | High (after verify) |
| `lib/features/purchase/presentation/widgets/add_item_entry_page.dart` | 2026-06-03 | `PurchaseItemEntrySheet` | High (after verify) |

## Shims (keep; not deprecated)

| File | Purpose |
|------|---------|
| `lib/features/stock/presentation/barcode_scan_page.dart` | Re-export canonical barcode scan |
| `lib/features/purchase/presentation/scan_purchase_page.dart` | Route wrapper → v2 |
| `lib/features/dashboard/presentation/home_page.dart` | Re-export owner home |
| `lib/features/catalog/presentation/catalog_add_item_page.dart` | Preset taxonomy route wrapper |
| `lib/features/stock/presentation/update_stock_sheet.dart` | Public API → quick stock sheet |
