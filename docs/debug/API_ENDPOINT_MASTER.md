# PROJECT API AUDIT — Master Tracker

**Generated:** 2026-07-28
**Discovered HTTP routes (excl. HEAD/OPTIONS):** 216
**Note:** ~380 was an estimate; FastAPI currently exposes **216** method+path pairs. Tracker uses discovered count as 100%.
**Hosts:** API https://my-purchases-api.onrender.com · Web https://purchase-assiastant.vercel.app
**Detail audit (Auth):** `docs/debug/API_AUDIT_AUTH.md` · Ops: `docs/debug/API_AUDIT_OPS.md`

## Progress

| Metric | Value |
|--------|-------|
| Total endpoints | 216 |
| Completed | 17 / 216 |
| Current focus | Medium backlog (AUTH-H2/H3 still blocked) |

## Status legend

`NOT_STARTED` · `DISCOVERED` · `AUDITING` · `TESTING` · `FIXING` · `VERIFYING` · `DEPLOYED` · `COMPLETED` · `BLOCKED`

## Issue log

| ID | Severity | Status | Summary | Commit |
|----|----------|--------|---------|--------|
| AUTH-C1 | Critical | COMPLETED | Refresh gates blocked/inactive | 9d50148 |
| AUTH-H1 | High | COMPLETED | Login missing db.commit | (see latest) |
| AUTH-H4 | High | COMPLETED | Google bypasses ALLOW_PUBLIC_REGISTRATION | 8187417 |
| AUTH-H2 | High | BLOCKED | Forgot-password email | needs approval |
| AUTH-H3 | High | BLOCKED | Logo object storage | needs approval |
| AUTH-M2 | Medium | COMPLETED | Login / forgot-password rate limits | (this pass) |
| UTIL-M1 | Medium | COMPLETED | Health db-check no exception leak | (this pass) |
| UTIL-M2 | Medium | COMPLETED | Search staff redact supplier/broker phones | (this pass) |
| OPS-M2 | Medium | COMPLETED | Checklist complete validates task_key | (this pass) |
| STOCK/HOME isce | Critical | COMPLETED | Shared-session gather sequentialized | a52dd46, 772bdc0 |
| HOME-C1 | Critical | COMPLETED | home-overview isce (same as above) | 772bdc0 |
| SUPPLIER-C1 | Critical | COMPLETED | Delete supplier/broker clears M2M (+ defaults) | (this pass) |
| SUPPLIER-H1 | High | COMPLETED | Supplier metrics avg_landing = money÷qty | (this pass) |
| SUPPLIER-H2 | High | COMPLETED | contacts/search brokers use `_broker_out` | (this pass) |
| REPORTS-C1 | Critical | COMPLETED | Item report StockPhysicalCount.counted_qty | (this pass) |
| REPORTS-H1 | High | COMPLETED | trade-suppliers avg_landing money÷qty | (this pass) |
| REPORTS-H2 | High | COMPLETED | trade-items category/supplier SQL filters | (this pass) |
| REPORTS-H3 | High | COMPLETED | Item bundle rate_avg money÷qty | (this pass) |
| NOTIF-H1 | High | COMPLETED | Role filter before LIMIT (stable pages) | (this pass) |
| NOTIF-H2 | High | COMPLETED | Unread/summary honor target_roles | (this pass) |
| NOTIF-H3 | High | COMPLETED | Idle delivery skips cancelled/deleted | (this pass) |
| USERS-C1 | Critical | COMPLETED | Reset password + refresh JWT tv revoke | (this pass) |
| USERS-H1 | High | COMPLETED | Deactivate revokes tokens | (this pass) |
| USERS-H2 | High | COMPLETED | Permissions patch actor guard | (this pass) |
| USERS-H3 | High | COMPLETED | Activity log IDOR for staff | (this pass) |
| OPS-H1 | High | COMPLETED | Checklist distinct slot+task_key | (this pass) |
| OPS-H2 | High | COMPLETED | usage_submit source_id on new log | (this pass) |
| OPS-H3 | High | COMPLETED | materialize requires stock_edit | (this pass) |
| OPS-C1 | Critical | COMPLETED | verify-count stores idempotency_key | (this pass) |
| OPS-C2 | Critical | COMPLETED | PUT audit blocks applied line replace | (this pass) |
| OPS-H4 | High | COMPLETED | inventory-summary redact value for staff | (this pass) |
| OPS-H5 | High | COMPLETED | warehouse checklist template denom | (this pass) |
| OPS-H6 | High | COMPLETED | reorder last_purchase_rate redact | (this pass) |
| EXP-H1 | High | COMPLETED | Backup ZIP purchase PDF cap (400) | (this pass) |
| PUB-C1 | Critical | COMPLETED | Public item JSON strips rates/supplier | (this pass) |
| EXP-M1 | Medium | COMPLETED | Cap catalog/supplier rows in exports | (this pass) |
| OPS-M1 | Medium | COMPLETED | Persist checklist default template seed | (this pass) |
| REPORTS-M2 | Medium | COMPLETED | Tests use trade-summary not dead /dashboard | (this pass) |
| USERS-M1 | Medium | COMPLETED | list_users / active-sessions batched stats | (this pass) |
| NOTIF-L1 | Low | COMPLETED | due_soon scheduler emits payment notifications | (this pass) |

## Ordered work queue (one-by-one)

1. ~~AUTH-C1~~ · ~~AUTH-H1~~ · ~~AUTH-H4~~ · ~~HOME-C1 isce~~
2. **AUTH-H2 / AUTH-H3** — wait for your approval (email / object storage)
3. ~~Stock~~ · ~~Purchase~~ · ~~Supplier~~ · ~~Reports~~ · ~~Notifications~~ · ~~Users~~ · ~~Warehouse/Ops~~ · ~~Exports~~ · ~~Utilities/Public~~
4. **AUTH-H2 / AUTH-H3** — wait for approval · optional Medium backlog


## Work rules

- One issue at a time; no unrelated file churn.
- AUTH-H2 / AUTH-H3 require user approval (email provider / object storage).
- Stock bundle + home-overview isce already fixed; mark those Stock/Reports rows when audited.

## Authentication

| Method | Endpoint | Controller | Frontend | Status | Priority | Notes | Done |
|--------|----------|------------|----------|--------|----------|-------|------|
| POST | `/v1/auth/forgot-password` | `auth.forgot_password` | forgot/reset pages | BLOCKED | High | AUTH-H2 needs email product decision | ⛔ |
| POST | `/v1/auth/google` | `auth.auth_google` | — | COMPLETED | High | AUTH-H4 registration gate | ☑ |
| POST | `/v1/auth/login` | `auth.login` | login_page | COMPLETED | High | AUTH-H1 commit | ☑ |
| POST | `/v1/auth/refresh` | `auth.refresh_token` | session_notifier | COMPLETED | Critical | AUTH-C1 fixed 9d50148 | ☑ |
| POST | `/v1/auth/register` | `auth.register` | — | COMPLETED | Low | Prod 403 by design | ☑ |
| POST | `/v1/auth/reset-password` | `auth.reset_password_with_token` | forgot/reset pages | DISCOVERED | Medium | Depends AUTH-H2 | ☐ |
| POST | `/v1/me/bootstrap-workspace` | `me.post_bootstrap_workspace` | session bootstrap | COMPLETED | Medium | Working; slow | ☑ |
| GET | `/v1/me/businesses` | `me.my_businesses` | session bootstrap | COMPLETED | Low | Working prod | ☑ |
| PATCH | `/v1/me/businesses/{business_id}/branding` | `me.patch_my_business_branding` | — | DISCOVERED | Medium | — | ☐ |
| POST | `/v1/me/businesses/{business_id}/branding/logo` | `me.upload_business_logo` | — | BLOCKED | High | AUTH-H3 ephemeral disk | ⛔ |
| GET | `/v1/me/profile` | `me.get_my_profile` | session bootstrap | COMPLETED | Low | Working prod | ☑ |
| PATCH | `/v1/me/profile` | `me.patch_my_profile` | — | DISCOVERED | Low | Unused by Flutter | ☐ |

## Dashboard

_No routes discovered in this category (N/A for this codebase)._

## Home

_No routes discovered in this category (N/A for this codebase)._

## Stock

| Method | Endpoint | Controller | Frontend | Status | Priority | Notes | Done |
|--------|----------|------------|----------|--------|----------|-------|------|
| GET | `/v1/businesses/{business_id}/exports/stock-inventory.xlsx` | `exports.get_stock_inventory_xlsx` | — | DISCOVERED | Medium | — | ☐ |
| GET | `/v1/businesses/{business_id}/stock-audits` | `stock_audits.list_stock_audits` | — | DISCOVERED | Medium | — | ☐ |
| POST | `/v1/businesses/{business_id}/stock-audits` | `stock_audits.create_stock_audit` | — | DISCOVERED | Medium | — | ☐ |
| GET | `/v1/businesses/{business_id}/stock-audits/active` | `stock_audits.get_active_stock_audit` | — | DISCOVERED | Medium | — | ☐ |
| GET | `/v1/businesses/{business_id}/stock-audits/kpis` | `stock_audits.stock_audit_kpis` | — | DISCOVERED | Medium | — | ☐ |
| GET | `/v1/businesses/{business_id}/stock-audits/pending-lines` | `stock_audits.list_pending_audit_lines_for_item` | — | DISCOVERED | Medium | — | ☐ |
| DELETE | `/v1/businesses/{business_id}/stock-audits/{audit_id}` | `stock_audits.delete_stock_audit` | — | DISCOVERED | Medium | — | ☐ |
| GET | `/v1/businesses/{business_id}/stock-audits/{audit_id}` | `stock_audits.get_stock_audit` | — | DISCOVERED | Medium | — | ☐ |
| PUT | `/v1/businesses/{business_id}/stock-audits/{audit_id}` | `stock_audits.update_stock_audit` | — | DISCOVERED | Medium | — | ☐ |
| POST | `/v1/businesses/{business_id}/stock-audits/{audit_id}/complete` | `stock_audits.complete_stock_audit_endpoint` | — | DISCOVERED | Medium | — | ☐ |
| POST | `/v1/businesses/{business_id}/stock-audits/{audit_id}/lines` | `stock_audits.upsert_stock_audit_line` | — | DISCOVERED | Medium | — | ☐ |
| POST | `/v1/businesses/{business_id}/stock-audits/{audit_id}/lines/{line_id}/approve` | `stock_audits.approve_stock_audit_line` | — | DISCOVERED | Medium | — | ☐ |
| GET | `/v1/businesses/{business_id}/stock/alerts/summary` | `stock_list.stock_alerts_summary` | stock_page / item detail | DISCOVERED | Medium | — | ☐ |
| GET | `/v1/businesses/{business_id}/stock/audit/feed` | `stock_audit.audit_feed` | stock_page / item detail | DISCOVERED | Medium | — | ☐ |
| GET | `/v1/businesses/{business_id}/stock/audit/recent` | `stock_audit.recent_adjustments_all` | stock_page / item detail | DISCOVERED | Medium | — | ☐ |
| GET | `/v1/businesses/{business_id}/stock/audit/{item_id}` | `stock_audit.audit_for_item` | stock_page / item detail | DISCOVERED | Medium | — | ☐ |
| POST | `/v1/businesses/{business_id}/stock/barcode/batch` | `stock_barcode.barcode_batch` | stock_page / item detail | DISCOVERED | Medium | — | ☐ |
| GET | `/v1/businesses/{business_id}/stock/barcode/lookup` | `stock_barcode.barcode_lookup` | stock_page / item detail | COMPLETED | High | isce sequential a52dd46 | ☑ |
| GET | `/v1/businesses/{business_id}/stock/barcode/{item_id}` | `stock_barcode.barcode_label` | stock_page / item detail | DISCOVERED | Medium | — | ☐ |
| GET | `/v1/businesses/{business_id}/stock/critical` | `stock_list.critical_stock` | stock_page / item detail | DISCOVERED | Medium | — | ☐ |
| GET | `/v1/businesses/{business_id}/stock/delivery-indicator-counts` | `stock_list.delivery_indicator_counts` | stock_page / item detail | DISCOVERED | Medium | — | ☐ |
| GET | `/v1/businesses/{business_id}/stock/inventory-summary` | `stock_ops.stock_inventory_summary` | stock_page / item detail | DISCOVERED | Medium | — | ☐ |
| GET | `/v1/businesses/{business_id}/stock/item/{item_id}/summary` | `stock_detail.get_stock_item_summary` | stock_page / item detail | DISCOVERED | Medium | — | ☐ |
| GET | `/v1/businesses/{business_id}/stock/items/{item_id}/purchase-intelligence` | `stock_detail.get_item_purchase_intelligence` | stock_page / item detail | DISCOVERED | Medium | — | ☐ |
| GET | `/v1/businesses/{business_id}/stock/list` | `stock_list.list_stock` | stock_page / item detail | DISCOVERED | Medium | — | ☐ |
| GET | `/v1/businesses/{business_id}/stock/list/compact` | `stock_list.list_stock_compact` | stock_page / item detail | DISCOVERED | Medium | — | ☐ |
| GET | `/v1/businesses/{business_id}/stock/low` | `stock_list.low_stock` | stock_page / item detail | DISCOVERED | Medium | — | ☐ |
| GET | `/v1/businesses/{business_id}/stock/low-stock/operations` | `stock_list.low_stock_operations` | stock_page / item detail | DISCOVERED | Medium | — | ☐ |
| GET | `/v1/businesses/{business_id}/stock/low-stock/summary` | `stock_list.low_stock_operations_summary` | stock_page / item detail | DISCOVERED | Medium | — | ☐ |
| GET | `/v1/businesses/{business_id}/stock/opening/missing` | `stock_ops.missing_opening_stock` | stock_page / item detail | DISCOVERED | Medium | — | ☐ |
| GET | `/v1/businesses/{business_id}/stock/opening/setup` | `stock_ops.list_opening_stock_setup` | stock_page / item detail | DISCOVERED | Medium | — | ☐ |
| GET | `/v1/businesses/{business_id}/stock/reorder` | `stock_ops.list_reorder_entries` | stock_page / item detail | DISCOVERED | Medium | — | ☐ |
| DELETE | `/v1/businesses/{business_id}/stock/reorder/{entry_id}` | `stock_ops.delete_reorder_entry` | stock_page / item detail | DISCOVERED | Medium | — | ☐ |
| PATCH | `/v1/businesses/{business_id}/stock/reorder/{entry_id}` | `stock_ops.patch_reorder_entry` | stock_page / item detail | DISCOVERED | Medium | — | ☐ |
| GET | `/v1/businesses/{business_id}/stock/search` | `stock_list.search_stock` | stock_page / item detail | DISCOVERED | Medium | — | ☐ |
| GET | `/v1/businesses/{business_id}/stock/shell-bundle` | `stock_list.stock_shell_bundle` | stock_page / item detail | COMPLETED | Critical | isce sequential a52dd46 | ☑ |
| GET | `/v1/businesses/{business_id}/stock/staff-purchases` | `stock_audit.list_staff_purchase_logs` | stock_page / item detail | DISCOVERED | Medium | — | ☐ |
| POST | `/v1/businesses/{business_id}/stock/staff-purchases` | `stock_audit.create_staff_purchase_log` | stock_page / item detail | DISCOVERED | Medium | — | ☐ |
| GET | `/v1/businesses/{business_id}/stock/totals` | `stock_ops.stock_totals` | stock_page / item detail | DISCOVERED | Medium | — | ☐ |
| GET | `/v1/businesses/{business_id}/stock/variances/today` | `stock_audit.variances_today` | stock_page / item detail | DISCOVERED | Medium | — | ☐ |
| GET | `/v1/businesses/{business_id}/stock/warehouse/alerts-summary` | `stock_list.warehouse_alerts_summary` | stock_page / item detail | DISCOVERED | Medium | — | ☐ |
| GET | `/v1/businesses/{business_id}/stock/{item_id}` | `stock_detail.get_stock_item` | stock_page / item detail | DISCOVERED | Medium | — | ☐ |
| PATCH | `/v1/businesses/{business_id}/stock/{item_id}` | `stock_detail.patch_stock_item` | stock_page / item detail | DISCOVERED | Medium | — | ☐ |
| GET | `/v1/businesses/{business_id}/stock/{item_id}/activity` | `stock_detail.stock_item_activity` | stock_page / item detail | DISCOVERED | Medium | — | ☐ |
| GET | `/v1/businesses/{business_id}/stock/{item_id}/bundle` | `stock_detail.stock_item_bundle` | stock_page / item detail | COMPLETED | Critical | isce sequential a52dd46 | ☑ |
| GET | `/v1/businesses/{business_id}/stock/{item_id}/intelligence` | `stock_detail.get_stock_intelligence` | stock_page / item detail | DISCOVERED | Medium | — | ☐ |
| POST | `/v1/businesses/{business_id}/stock/{item_id}/notify-owner` | `stock_detail.notify_owner_about_item` | stock_page / item detail | DISCOVERED | Medium | — | ☐ |
| POST | `/v1/businesses/{business_id}/stock/{item_id}/opening-stock` | `stock_detail.set_opening_stock` | stock_page / item detail | DISCOVERED | Medium | — | ☐ |
| POST | `/v1/businesses/{business_id}/stock/{item_id}/physical-count` | `stock_detail.record_physical_stock_count` | stock_page / item detail | DISCOVERED | Medium | — | ☐ |
| POST | `/v1/businesses/{business_id}/stock/{item_id}/physical-update` | `stock_detail.update_physical_stock` | stock_page / item detail | DISCOVERED | Medium | — | ☐ |
| POST | `/v1/businesses/{business_id}/stock/{item_id}/quick-purchase` | `stock_ops.create_item_quick_purchase` | stock_page / item detail | DISCOVERED | Medium | — | ☐ |
| POST | `/v1/businesses/{business_id}/stock/{item_id}/reorder` | `stock_ops.add_item_to_reorder_list` | stock_page / item detail | DISCOVERED | Medium | — | ☐ |
| POST | `/v1/businesses/{business_id}/stock/{item_id}/undo-last` | `stock_detail.undo_last_stock_change` | stock_page / item detail | DISCOVERED | Medium | — | ☐ |
| POST | `/v1/businesses/{business_id}/stock/{item_id}/verify-count` | `stock_detail.verify_stock_count` | stock_page / item detail | DISCOVERED | Medium | — | ☐ |
| GET | `/v1/businesses/{business_id}/users/{user_id}/stock-adjustments` | `users.user_stock_adjustments` | — | DISCOVERED | Medium | — | ☐ |

## Purchase

| Method | Endpoint | Controller | Frontend | Status | Priority | Notes | Done |
|--------|----------|------------|----------|--------|----------|-------|------|
| GET | `/v1/businesses/{business_id}/damage-reports/pending-count` | `damage_reports.pending_damage_reports_count` | — | DISCOVERED | Medium | — | ☐ |
| PATCH | `/v1/businesses/{business_id}/damage-reports/{report_id}` | `damage_reports.patch_damage_report_status` | — | DISCOVERED | Medium | — | ☐ |
| GET | `/v1/businesses/{business_id}/trade-purchases` | `trade_purchases.list_trade_purchases` | — | DISCOVERED | Medium | — | ☐ |
| POST | `/v1/businesses/{business_id}/trade-purchases` | `trade_purchases.create_trade_purchase` | — | DISCOVERED | Medium | — | ☐ |
| POST | `/v1/businesses/{business_id}/trade-purchases/check-duplicate` | `trade_purchases.check_trade_duplicate` | — | DISCOVERED | Medium | — | ☐ |
| GET | `/v1/businesses/{business_id}/trade-purchases/delivery-pipeline` | `trade_purchases.get_trade_purchase_delivery_pipeline` | — | DISCOVERED | Medium | — | ☐ |
| DELETE | `/v1/businesses/{business_id}/trade-purchases/draft` | `trade_purchases.delete_trade_draft` | — | DISCOVERED | Medium | — | ☐ |
| GET | `/v1/businesses/{business_id}/trade-purchases/draft` | `trade_purchases.read_trade_draft` | — | DISCOVERED | Medium | — | ☐ |
| PUT | `/v1/businesses/{business_id}/trade-purchases/draft` | `trade_purchases.upsert_trade_draft` | — | DISCOVERED | Medium | — | ☐ |
| GET | `/v1/businesses/{business_id}/trade-purchases/last-defaults` | `trade_purchases.last_trade_purchase_defaults` | — | DISCOVERED | Medium | — | ☐ |
| GET | `/v1/businesses/{business_id}/trade-purchases/next-human-id` | `trade_purchases.next_trade_human_id` | — | DISCOVERED | Medium | — | ☐ |
| POST | `/v1/businesses/{business_id}/trade-purchases/preview-lines` | `trade_purchases.preview_trade_purchase_lines` | — | DISCOVERED | Medium | — | ☐ |
| POST | `/v1/businesses/{business_id}/trade-purchases/validate` | `trade_purchases.validate_trade_purchase` | — | DISCOVERED | Medium | — | ☐ |
| DELETE | `/v1/businesses/{business_id}/trade-purchases/{purchase_id}` | `trade_purchases.delete_trade_purchase` | — | DISCOVERED | Medium | — | ☐ |
| GET | `/v1/businesses/{business_id}/trade-purchases/{purchase_id}` | `trade_purchases.get_trade_purchase` | — | DISCOVERED | Medium | — | ☐ |
| PUT | `/v1/businesses/{business_id}/trade-purchases/{purchase_id}` | `trade_purchases.update_trade_purchase` | — | DISCOVERED | Medium | — | ☐ |
| POST | `/v1/businesses/{business_id}/trade-purchases/{purchase_id}/arrive` | `trade_purchases.arrive_trade_purchase` | — | DISCOVERED | Medium | — | ☐ |
| POST | `/v1/businesses/{business_id}/trade-purchases/{purchase_id}/auto-commit` | `trade_purchases.auto_commit_trade_purchase_delivery` | — | DISCOVERED | Medium | — | ☐ |
| POST | `/v1/businesses/{business_id}/trade-purchases/{purchase_id}/cancel` | `trade_purchases.cancel_trade_purchase` | — | DISCOVERED | Medium | — | ☐ |
| POST | `/v1/businesses/{business_id}/trade-purchases/{purchase_id}/commit-stock` | `trade_purchases.commit_trade_purchase_delivery` | — | DISCOVERED | Medium | — | ☐ |
| GET | `/v1/businesses/{business_id}/trade-purchases/{purchase_id}/damage-reports` | `trade_purchases.list_purchase_damage_reports` | — | DISCOVERED | Medium | — | ☐ |
| POST | `/v1/businesses/{business_id}/trade-purchases/{purchase_id}/damage-reports` | `trade_purchases.create_purchase_damage_report` | — | DISCOVERED | Medium | — | ☐ |
| PATCH | `/v1/businesses/{business_id}/trade-purchases/{purchase_id}/delivery` | `trade_purchases.patch_trade_purchase_delivery` | — | DISCOVERED | Medium | — | ☐ |
| POST | `/v1/businesses/{business_id}/trade-purchases/{purchase_id}/dispatch` | `trade_purchases.dispatch_trade_purchase` | — | DISCOVERED | Medium | — | ☐ |
| POST | `/v1/businesses/{business_id}/trade-purchases/{purchase_id}/lifecycle` | `trade_purchases.transition_purchase_lifecycle` | — | DISCOVERED | Medium | — | ☐ |
| GET | `/v1/businesses/{business_id}/trade-purchases/{purchase_id}/lifecycle-events` | `trade_purchases.list_purchase_lifecycle_events` | — | DISCOVERED | Medium | — | ☐ |
| POST | `/v1/businesses/{business_id}/trade-purchases/{purchase_id}/mark-paid` | `trade_purchases.mark_trade_purchase_paid` | — | DISCOVERED | Medium | — | ☐ |
| PATCH | `/v1/businesses/{business_id}/trade-purchases/{purchase_id}/payment` | `trade_purchases.patch_trade_purchase_payment` | — | DISCOVERED | Medium | — | ☐ |
| POST | `/v1/businesses/{business_id}/trade-purchases/{purchase_id}/verify` | `trade_purchases.verify_trade_purchase_delivery` | — | DISCOVERED | Medium | — | ☐ |

## Purchase Orders

_No routes discovered in this category (N/A for this codebase)._

## Sales

_No routes discovered in this category (N/A for this codebase)._

## Inventory

| Method | Endpoint | Controller | Frontend | Status | Priority | Notes | Done |
|--------|----------|------------|----------|--------|----------|-------|------|
| GET | `/v1/businesses/{business_id}/catalog-items` | `catalog.list_catalog_items` | — | DISCOVERED | Medium | — | ☐ |
| POST | `/v1/businesses/{business_id}/catalog-items` | `catalog.create_catalog_item` | — | DISCOVERED | Medium | — | ☐ |
| POST | `/v1/businesses/{business_id}/catalog-items/batch` | `catalog.batch_create_catalog_items` | — | DISCOVERED | Medium | — | ☐ |
| POST | `/v1/businesses/{business_id}/catalog-items/from-scan` | `catalog.create_catalog_item_from_scan` | — | DISCOVERED | Medium | — | ☐ |
| DELETE | `/v1/businesses/{business_id}/catalog-items/{item_id}` | `catalog.delete_catalog_item` | — | DISCOVERED | Medium | — | ☐ |
| GET | `/v1/businesses/{business_id}/catalog-items/{item_id}` | `catalog.get_catalog_item` | — | DISCOVERED | Medium | — | ☐ |
| PATCH | `/v1/businesses/{business_id}/catalog-items/{item_id}` | `catalog.update_catalog_item` | — | DISCOVERED | Medium | — | ☐ |
| PATCH | `/v1/businesses/{business_id}/catalog-items/{item_id}/barcode` | `catalog.patch_catalog_item_barcode` | — | DISCOVERED | Medium | — | ☐ |
| POST | `/v1/businesses/{business_id}/catalog-items/{item_id}/generate-code` | `catalog.generate_catalog_item_code` | — | DISCOVERED | Medium | — | ☐ |
| GET | `/v1/businesses/{business_id}/catalog-items/{item_id}/insights` | `catalog.catalog_item_insights` | — | DISCOVERED | Medium | — | ☐ |
| PATCH | `/v1/businesses/{business_id}/catalog-items/{item_id}/item-code` | `catalog.patch_catalog_item_code` | — | DISCOVERED | Medium | — | ☐ |
| GET | `/v1/businesses/{business_id}/catalog-items/{item_id}/lines` | `catalog.catalog_item_lines` | — | DISCOVERED | Medium | — | ☐ |
| GET | `/v1/businesses/{business_id}/catalog-items/{item_id}/supplier-purchase-defaults` | `catalog.supplier_purchase_defaults` | — | DISCOVERED | Medium | — | ☐ |
| GET | `/v1/businesses/{business_id}/catalog-items/{item_id}/trade-supplier-prices` | `catalog.catalog_item_trade_supplier_prices` | — | DISCOVERED | Medium | — | ☐ |
| GET | `/v1/businesses/{business_id}/catalog-items/{item_id}/variants` | `catalog.list_catalog_variants` | — | DISCOVERED | Medium | — | ☐ |
| POST | `/v1/businesses/{business_id}/catalog-items/{item_id}/variants` | `catalog.create_catalog_variant` | — | DISCOVERED | Medium | — | ☐ |
| DELETE | `/v1/businesses/{business_id}/catalog-variants/{variant_id}` | `catalog.delete_catalog_variant` | — | DISCOVERED | Medium | — | ☐ |
| PATCH | `/v1/businesses/{business_id}/catalog-variants/{variant_id}` | `catalog.update_catalog_variant` | — | DISCOVERED | Medium | — | ☐ |
| GET | `/v1/businesses/{business_id}/catalog/duplicate-clusters` | `catalog.catalog_duplicate_clusters` | — | DISCOVERED | Medium | — | ☐ |
| GET | `/v1/businesses/{business_id}/catalog/fuzzy-check` | `catalog.catalog_fuzzy_check` | — | DISCOVERED | Medium | — | ☐ |
| POST | `/v1/businesses/{business_id}/catalog/items/bulk-archive` | `catalog.bulk_archive_catalog_items` | — | DISCOVERED | Medium | — | ☐ |
| PATCH | `/v1/businesses/{business_id}/catalog/items/bulk-reorder` | `catalog.bulk_reorder_catalog_items` | — | DISCOVERED | Medium | — | ☐ |
| GET | `/v1/businesses/{business_id}/category-types-index` | `catalog.list_category_types_index` | — | DISCOVERED | Medium | — | ☐ |
| GET | `/v1/businesses/{business_id}/item-categories` | `catalog.list_item_categories` | — | DISCOVERED | Medium | — | ☐ |
| POST | `/v1/businesses/{business_id}/item-categories` | `catalog.create_item_category` | — | DISCOVERED | Medium | — | ☐ |
| DELETE | `/v1/businesses/{business_id}/item-categories/{category_id}` | `catalog.delete_item_category` | — | DISCOVERED | Medium | — | ☐ |
| GET | `/v1/businesses/{business_id}/item-categories/{category_id}` | `catalog.get_item_category` | — | DISCOVERED | Medium | — | ☐ |
| PATCH | `/v1/businesses/{business_id}/item-categories/{category_id}` | `catalog.update_item_category` | — | DISCOVERED | Medium | — | ☐ |
| GET | `/v1/businesses/{business_id}/item-categories/{category_id}/category-types` | `catalog.list_category_types` | — | DISCOVERED | Medium | — | ☐ |
| POST | `/v1/businesses/{business_id}/item-categories/{category_id}/category-types` | `catalog.create_category_type` | — | DISCOVERED | Medium | — | ☐ |
| DELETE | `/v1/businesses/{business_id}/item-categories/{category_id}/category-types/{type_id}` | `catalog.delete_category_type` | — | DISCOVERED | Medium | — | ☐ |
| PATCH | `/v1/businesses/{business_id}/item-categories/{category_id}/category-types/{type_id}` | `catalog.update_category_type` | — | DISCOVERED | Medium | — | ☐ |
| GET | `/v1/businesses/{business_id}/item-categories/{category_id}/insights` | `catalog.category_insights` | — | DISCOVERED | Medium | — | ☐ |
| GET | `/v1/businesses/{business_id}/item-categories/{category_id}/trade-summary` | `catalog.category_trade_summary` | — | DISCOVERED | Medium | — | ☐ |

## Warehouse

| Method | Endpoint | Controller | Frontend | Status | Priority | Notes | Done |
|--------|----------|------------|----------|--------|----------|-------|------|
| GET | `/v1/businesses/{business_id}/operations/checklist/summary` | `operations.checklist_summary` | — | DISCOVERED | Medium | — | ☐ |
| GET | `/v1/businesses/{business_id}/operations/checklist/templates` | `operations.list_checklist_templates` | — | DISCOVERED | Medium | — | ☐ |
| PUT | `/v1/businesses/{business_id}/operations/checklist/templates` | `operations.replace_checklist_templates` | — | DISCOVERED | Medium | — | ☐ |
| GET | `/v1/businesses/{business_id}/operations/checklist/today` | `operations.checklist_today` | — | DISCOVERED | Medium | — | ☐ |
| POST | `/v1/businesses/{business_id}/operations/checklist/{slot}/complete` | `operations.checklist_complete` | — | DISCOVERED | Medium | — | ☐ |
| GET | `/v1/businesses/{business_id}/operations/snapshots` | `operations.list_daily_snapshots` | — | DISCOVERED | Medium | — | ☐ |
| POST | `/v1/businesses/{business_id}/operations/snapshots/materialize` | `operations.materialize_daily_snapshots` | — | DISCOVERED | Medium | — | ☐ |
| GET | `/v1/businesses/{business_id}/operations/usage/summary` | `operations.usage_summary` | — | DISCOVERED | Medium | — | ☐ |
| GET | `/v1/businesses/{business_id}/operations/usage/today` | `operations.usage_today` | — | DISCOVERED | Medium | — | ☐ |
| POST | `/v1/businesses/{business_id}/operations/usage/today` | `operations.usage_submit` | — | DISCOVERED | Medium | — | ☐ |

## Supplier

| Method | Endpoint | Controller | Frontend | Status | Priority | Notes | Done |
|--------|----------|------------|----------|--------|----------|-------|------|
| GET | `/v1/businesses/{business_id}/brokers` | `contacts.list_brokers` | — | DISCOVERED | Medium | — | ☐ |
| POST | `/v1/businesses/{business_id}/brokers` | `contacts.create_broker` | — | DISCOVERED | Medium | — | ☐ |
| DELETE | `/v1/businesses/{business_id}/brokers/{broker_id}` | `contacts.delete_broker` | — | DISCOVERED | Medium | — | ☐ |
| GET | `/v1/businesses/{business_id}/brokers/{broker_id}` | `contacts.get_broker` | — | DISCOVERED | Medium | — | ☐ |
| PATCH | `/v1/businesses/{business_id}/brokers/{broker_id}` | `contacts.update_broker` | — | DISCOVERED | Medium | — | ☐ |
| GET | `/v1/businesses/{business_id}/brokers/{broker_id}/linked-suppliers` | `contacts.broker_linked_suppliers` | — | DISCOVERED | Medium | — | ☐ |
| GET | `/v1/businesses/{business_id}/brokers/{broker_id}/metrics` | `contacts.broker_metrics` | — | DISCOVERED | Medium | — | ☐ |
| GET | `/v1/businesses/{business_id}/contacts/category-items` | `contacts.category_items` | — | DISCOVERED | Medium | — | ☐ |
| GET | `/v1/businesses/{business_id}/contacts/search` | `contacts.contacts_search` | — | DISCOVERED | Medium | — | ☐ |
| GET | `/v1/businesses/{business_id}/suppliers` | `contacts.list_suppliers` | — | DISCOVERED | Medium | — | ☐ |
| POST | `/v1/businesses/{business_id}/suppliers` | `contacts.create_supplier` | — | DISCOVERED | Medium | — | ☐ |
| DELETE | `/v1/businesses/{business_id}/suppliers/{supplier_id}` | `contacts.delete_supplier` | — | DISCOVERED | Medium | — | ☐ |
| GET | `/v1/businesses/{business_id}/suppliers/{supplier_id}` | `contacts.get_supplier` | — | DISCOVERED | Medium | — | ☐ |
| PATCH | `/v1/businesses/{business_id}/suppliers/{supplier_id}` | `contacts.update_supplier` | — | DISCOVERED | Medium | — | ☐ |
| GET | `/v1/businesses/{business_id}/suppliers/{supplier_id}/metrics` | `contacts.supplier_metrics` | — | DISCOVERED | Medium | — | ☐ |

## Customer

_No routes discovered in this category (N/A for this codebase)._

## Reports

| Method | Endpoint | Controller | Frontend | Status | Priority | Notes | Done |
|--------|----------|------------|----------|--------|----------|-------|------|
| GET | `/v1/businesses/{business_id}/operations/reports/summary` | `operations.operational_reports_summary` | — | DISCOVERED | Medium | — | ☐ |
| GET | `/v1/businesses/{business_id}/report-views` | `report_views.list_report_views` | — | DISCOVERED | Medium | — | ☐ |
| POST | `/v1/businesses/{business_id}/report-views` | `report_views.create_report_view` | — | DISCOVERED | Medium | — | ☐ |
| DELETE | `/v1/businesses/{business_id}/report-views/{view_id}` | `report_views.delete_report_view` | — | DISCOVERED | Medium | — | ☐ |
| PATCH | `/v1/businesses/{business_id}/report-views/{view_id}` | `report_views.patch_report_view` | — | DISCOVERED | Medium | — | ☐ |
| GET | `/v1/businesses/{business_id}/reports/activity-feed` | `reports_trade.reports_activity_feed` | — | DISCOVERED | Medium | — | ☐ |
| GET | `/v1/businesses/{business_id}/reports/home-overview` | `reports_trade.trade_home_overview` | home_dashboard | COMPLETED | Critical | isce sequential 772bdc0 | ☑ |
| GET | `/v1/businesses/{business_id}/reports/item/{catalog_item_id}` | `reports_trade.reports_item_bundle` | — | DISCOVERED | Medium | — | ☐ |
| GET | `/v1/businesses/{business_id}/reports/movement-summary` | `reports_trade.reports_movement_summary` | — | DISCOVERED | Medium | — | ☐ |
| GET | `/v1/businesses/{business_id}/reports/period-comparison` | `reports_trade.reports_period_comparison` | — | DISCOVERED | Medium | — | ☐ |
| POST | `/v1/businesses/{business_id}/reports/sales-comparison` | `reports_trade.compare_sales_lines` | — | DISCOVERED | Medium | — | ☐ |
| GET | `/v1/businesses/{business_id}/reports/trade-categories` | `reports_trade.trade_categories_breakdown` | — | DISCOVERED | Medium | — | ☐ |
| GET | `/v1/businesses/{business_id}/reports/trade-daily-profit` | `reports_trade.trade_daily_profit_series` | — | DISCOVERED | Medium | — | ☐ |
| GET | `/v1/businesses/{business_id}/reports/trade-dashboard-snapshot` | `reports_trade.trade_dashboard_snapshot` | — | COMPLETED | Critical | isce sequential 772bdc0 | ☑ |
| GET | `/v1/businesses/{business_id}/reports/trade-items` | `reports_trade.trade_items_breakdown` | — | DISCOVERED | Medium | — | ☐ |
| GET | `/v1/businesses/{business_id}/reports/trade-last-supplier-autofill` | `reports_trade.trade_last_supplier_autofill` | — | DISCOVERED | Medium | — | ☐ |
| GET | `/v1/businesses/{business_id}/reports/trade-summary` | `reports_trade.trade_purchase_summary` | — | DISCOVERED | Medium | — | ☐ |
| GET | `/v1/businesses/{business_id}/reports/trade-supplier-broker-map` | `reports_trade.trade_supplier_broker_map` | — | DISCOVERED | Medium | — | ☐ |
| GET | `/v1/businesses/{business_id}/reports/trade-suppliers` | `reports_trade.trade_suppliers_breakdown` | — | DISCOVERED | Medium | — | ☐ |
| GET | `/v1/businesses/{business_id}/reports/trade-types` | `reports_trade.trade_types_breakdown` | — | DISCOVERED | Medium | — | ☐ |

## Notifications

| Method | Endpoint | Controller | Frontend | Status | Priority | Notes | Done |
|--------|----------|------------|----------|--------|----------|-------|------|
| GET | `/v1/businesses/{business_id}/notifications` | `notifications.list_notifications` | — | DISCOVERED | Medium | — | ☐ |
| DELETE | `/v1/businesses/{business_id}/notifications/clear-all` | `notifications.clear_all` | — | DISCOVERED | Medium | — | ☐ |
| POST | `/v1/businesses/{business_id}/notifications/client-event` | `notifications.client_notification_event` | — | DISCOVERED | Medium | — | ☐ |
| POST | `/v1/businesses/{business_id}/notifications/mark-all-read` | `notifications.mark_all_read` | — | DISCOVERED | Medium | — | ☐ |
| GET | `/v1/businesses/{business_id}/notifications/summary` | `notifications.notifications_summary` | — | DISCOVERED | Medium | — | ☐ |
| GET | `/v1/businesses/{business_id}/notifications/unread-count` | `notifications.unread_count` | — | DISCOVERED | Medium | — | ☐ |
| PATCH | `/v1/businesses/{business_id}/notifications/{notification_id}` | `notifications.patch_notification` | — | DISCOVERED | Medium | — | ☐ |

## Settings

_No routes discovered in this category (N/A for this codebase)._

## Users

| Method | Endpoint | Controller | Frontend | Status | Priority | Notes | Done |
|--------|----------|------------|----------|--------|----------|-------|------|
| GET | `/v1/businesses/{business_id}/activity-log` | `users.list_activity` | — | DISCOVERED | Medium | — | ☐ |
| POST | `/v1/businesses/{business_id}/activity-log` | `users.post_activity` | — | DISCOVERED | Medium | — | ☐ |
| GET | `/v1/businesses/{business_id}/users` | `users.list_users` | — | DISCOVERED | Medium | — | ☐ |
| POST | `/v1/businesses/{business_id}/users` | `users.create_user` | — | DISCOVERED | Medium | — | ☐ |
| GET | `/v1/businesses/{business_id}/users/active-sessions` | `users.active_sessions` | — | DISCOVERED | Medium | — | ☐ |
| POST | `/v1/businesses/{business_id}/users/bulk` | `users.bulk_users` | — | DISCOVERED | Medium | — | ☐ |
| DELETE | `/v1/businesses/{business_id}/users/{user_id}` | `users.delete_user` | — | DISCOVERED | Medium | — | ☐ |
| GET | `/v1/businesses/{business_id}/users/{user_id}` | `users.get_user` | — | DISCOVERED | Medium | — | ☐ |
| PATCH | `/v1/businesses/{business_id}/users/{user_id}` | `users.patch_user` | — | DISCOVERED | Medium | — | ☐ |
| GET | `/v1/businesses/{business_id}/users/{user_id}/created-items` | `users.user_created_items` | — | DISCOVERED | Medium | — | ☐ |
| GET | `/v1/businesses/{business_id}/users/{user_id}/credentials` | `users.user_credentials` | — | DISCOVERED | Medium | — | ☐ |
| GET | `/v1/businesses/{business_id}/users/{user_id}/ledger` | `users.user_ledger` | — | DISCOVERED | Medium | — | ☐ |
| GET | `/v1/businesses/{business_id}/users/{user_id}/permissions` | `users.get_permissions` | — | DISCOVERED | Medium | — | ☐ |
| PATCH | `/v1/businesses/{business_id}/users/{user_id}/permissions` | `users.patch_permissions` | — | DISCOVERED | Medium | — | ☐ |
| GET | `/v1/businesses/{business_id}/users/{user_id}/purchases` | `users.user_purchases` | — | DISCOVERED | Medium | — | ☐ |
| POST | `/v1/businesses/{business_id}/users/{user_id}/reset-password` | `users.reset_password` | forgot/reset pages | DISCOVERED | Medium | — | ☐ |

## Admin

_No routes discovered in this category (N/A for this codebase)._

## Uploads

_No routes discovered in this category (N/A for this codebase)._

## Images

_No routes discovered in this category (N/A for this codebase)._

## Exports

| Method | Endpoint | Controller | Frontend | Status | Priority | Notes | Done |
|--------|----------|------------|----------|--------|----------|-------|------|
| POST | `/v1/businesses/{business_id}/exports/backup` | `exports.post_backup_zip` | — | DISCOVERED | Medium | — | ☐ |
| GET | `/v1/businesses/{business_id}/exports/backup/export` | `exports.get_backup_export_json` | — | DISCOVERED | Medium | — | ☐ |
| GET | `/v1/businesses/{business_id}/exports/purchases-month.pdf` | `exports.get_purchases_month_pdf` | — | DISCOVERED | Medium | — | ☐ |

## Imports

_No routes discovered in this category (N/A for this codebase)._

## Webhooks

_No routes discovered in this category (N/A for this codebase)._

## Background Jobs

_No routes discovered in this category (N/A for this codebase)._

## Cron Jobs

_No routes discovered in this category (N/A for this codebase)._

## Utilities

| Method | Endpoint | Controller | Frontend | Status | Priority | Notes | Done |
|--------|----------|------------|----------|--------|----------|-------|------|
| GET | `/v1/businesses/{business_id}/search` | `search.unified_search` | — | DISCOVERED | Medium | — | ☐ |

## Internal APIs

| Method | Endpoint | Controller | Frontend | Status | Priority | Notes | Done |
|--------|----------|------------|----------|--------|----------|-------|------|
| GET | `/v1/businesses/{business_id}/realtime/events` | `realtime.sse_events` | — | DISCOVERED | Medium | — | ☐ |
| GET | `/v1/businesses/{business_id}/realtime/recent` | `realtime.recent_events` | — | DISCOVERED | Medium | — | ☐ |

## Health APIs

| Method | Endpoint | Controller | Frontend | Status | Priority | Notes | Done |
|--------|----------|------------|----------|--------|----------|-------|------|
| GET | `/` | `health.root` | — | COMPLETED | Low | Live verified | ☑ |
| GET | `/docs` | `applications.swagger_ui_html` | — | DISCOVERED | Medium | — | ☐ |
| GET | `/docs/oauth2-redirect` | `applications.swagger_ui_redirect` | — | DISCOVERED | Medium | — | ☐ |
| GET | `/health` | `health.health` | — | COMPLETED | Low | Live verified | ☑ |
| GET | `/health/db-check` | `health.health_db_check` | — | DISCOVERED | Medium | — | ☐ |
| GET | `/health/live` | `health.health_live` | — | COMPLETED | Low | Live verified | ☑ |
| GET | `/health/ready` | `health.health_ready` | — | COMPLETED | Low | Live verified | ☑ |
| GET | `/openapi.json` | `applications.openapi` | — | DISCOVERED | Medium | — | ☐ |
| GET | `/redoc` | `applications.redoc_html` | — | DISCOVERED | Medium | — | ☐ |

## Other discovered APIs

| Method | Endpoint | Controller | Frontend | Status | Priority | Notes | Done |
|--------|----------|------------|----------|--------|----------|-------|------|
| GET | `/public/items/lookup` | `public_items.public_lookup` | — | DISCOVERED | Medium | — | ☐ |
| GET | `/public/items/{token}` | `public_items.public_item_page` | — | DISCOVERED | Medium | — | ☐ |
| GET | `/public/items/{token}.json` | `public_items.public_item_json` | — | DISCOVERED | Medium | — | ☐ |

