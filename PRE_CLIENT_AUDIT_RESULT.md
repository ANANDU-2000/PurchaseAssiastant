# Pre-client delivery audit result

**Project:** Harisree Purchase Assistant (Purchase Assistant)  
**Audit date:** June 2026  
**Production API:** `https://my-purchases-api.onrender.com`

---

## Fixes applied

- [x] **A1:** Fresh stock fetch before sheet — `openQuickStockWithFreshItem` in [`flutter_app/lib/features/stock/presentation/stock_sheet_launch.dart`](flutter_app/lib/features/stock/presentation/stock_sheet_launch.dart); barcode scan path uses it; `showUpdateStockSheet` delegates to same helper.
- [x] **A2:** 409 auto-retry centralized — `patchStockItemWithRetry`, `updatePhysicalStockWithRetry`, `verifyStockCountWithRetry` in [`flutter_app/lib/core/api/hexa_api.dart`](flutter_app/lib/core/api/hexa_api.dart); callers updated (quick stock sheet, warehouse scan, scan result, offline sync, item verification card).
- [x] **A3:** Saving guard — `_saving` + `_canSave` confirmed on quick stock and warehouse scan sheets; save via post-frame callback to avoid double tap.
- [x] **B1:** Camera permission persisted — `camera_perm_granted` in SharedPreferences ([`barcode_scan_page.dart`](flutter_app/lib/features/barcode/presentation/barcode_scan_page.dart)).
- [x] **B2:** `permissions-policy` meta tag — [`flutter_app/web/index.html`](flutter_app/web/index.html).
- [x] **C1:** Supplier optional in item wizard — no `_supplierIds.isEmpty` guard in [`item_wizard_page.dart`](flutter_app/lib/features/contacts/presentation/item_wizard_page.dart).
- [x] **C2:** HSN/tax not blocking — `_validateBasic()` only requires category, name, unit.
- [x] **D1:** WhatsApp null safety — dialog + `PdfActionResult` when number missing; no crash on null.
- [x] **D2:** Settings WhatsApp input — [`accounts_whatsapp_field.dart`](flutter_app/lib/features/settings/widgets/accounts_whatsapp_field.dart) + business profile.
- [x] **E3:** Duplicate SQL filenames — removed duplicate `033_trade_line_qty_in_stock_unit.sql`; renamed `034b_master_fix_v3_prod_parity.sql`, `035b_schema_parity_confirm.sql`; [`backend/sql/MIGRATION_INDEX.md`](backend/sql/MIGRATION_INDEX.md) updated.

---

## Verified already working

- [x] Desktop `NavigationRail` — [`flutter_app/lib/features/shell/shell_screen.dart`](flutter_app/lib/features/shell/shell_screen.dart)
- [x] Alembic chain intact — production reports `056_purchase_damage_reports` at `/health/ready` (deploy may lag repo head `057`)
- [x] Render keep-alive workflow — [`.github/workflows/render-keepalive.yml`](.github/workflows/render-keepalive.yml) every 10 min
- [x] Damage reports backend — router + migration 056+
- [x] WhatsApp share service — [`purchase_accounts_share.dart`](flutter_app/lib/core/services/purchase_accounts_share.dart)
- [x] DB weekly backup — [`.github/workflows/db-backup.yml`](.github/workflows/db-backup.yml) (pgdump + plain SQL, 90-day retention)
- [x] Unknown barcode flow — create item / assign / manual in [`barcode_scan_page.dart`](flutter_app/lib/features/barcode/presentation/barcode_scan_page.dart)
- [x] Owner export & backup — Settings → Export & Backup (stock Excel, purchases PDF, ZIP)

---

## Pre-client checklist results

| ID | Result | Notes |
|----|--------|-------|
| G1 | **PASS** | `GET /health/ready` → `{"status":"ok","db":"ok",...}` (2026-06-03 curl) |
| G2 | **MANUAL** | Physical count save — retest on iOS/Android PWA after this deploy |
| G3 | **MANUAL** | System stock save — retest on device after deploy |
| G4 | **MANUAL** | iOS Safari PWA: second scanner open should skip re-prompt (prefs + policy) |
| G5 | **MANUAL** | Create item without supplier — code allows; confirm on owner device |
| G6 | **MANUAL** | Purchase Save & Share — set `accounts_whatsapp_number` in Business Profile first |
| G7 | **MANUAL** | Desktop Chrome on Vercel PWA — confirm NavigationRail visible |
| G8 | **MANUAL** | Low stock list loads &lt; 5s on production |
| G9 | **MANUAL** | Staff damage report on delivered purchase |
| G10 | **MANUAL** | DevTools: no `ref disposed` during shell tab navigation |
| G11 | **MANUAL** | GitHub → Actions → **db-backup** → last run within 7 days |
| G12 | **MANUAL** | GitHub → Actions → **Render API keep-alive** → last run &lt; 10 min |

---

## Files modified

- `flutter_app/lib/core/api/hexa_api.dart`
- `flutter_app/lib/features/stock/presentation/stock_sheet_launch.dart` (new)
- `flutter_app/lib/features/stock/presentation/update_stock_sheet.dart`
- `flutter_app/lib/features/stock/presentation/quick_stock_action_sheet.dart`
- `flutter_app/lib/features/stock/presentation/widgets/scan_stock_result_sheet.dart`
- `flutter_app/lib/features/barcode/presentation/barcode_scan_page.dart`
- `flutter_app/lib/features/barcode/presentation/warehouse_scan_action_sheet.dart`
- `flutter_app/lib/features/catalog/presentation/widgets/item_physical_verification_card.dart`
- `flutter_app/lib/core/services/stock_offline_sync.dart`
- `flutter_app/lib/core/services/purchase_accounts_share.dart`
- `backend/sql/MIGRATION_INDEX.md`
- `backend/sql/034b_master_fix_v3_prod_parity.sql` (renamed)
- `backend/sql/035b_schema_parity_confirm.sql` (renamed)
- `README.md`
- `PRE_CLIENT_AUDIT_RESULT.md` (this file)

---

## Remaining manual actions (Anandu)

1. **Deploy** Flutter web + Render API with this commit, then run G2–G10 on real devices.
2. **GitHub Actions:** Confirm **Render API keep-alive** and **db-backup** are enabled and recent.
3. **Business profile:** Set **accounts staff WhatsApp** before demoing Save & Share.
4. **Render env:** Confirm `DATABASE_URL`, `JWT_SECRET`, and `preDeployCommand: alembic upgrade head` in dashboard / `render.yaml`.
5. **Alembic:** Production at `056`; run `alembic upgrade head` if repo head is `057` and features need it.

---

## Client handoff summary

**Ready after deploy + device smoke:** purchases, stock browse/search, barcode (including unknown → create/assign), reports, users, damage reports, desktop shell, exports/backup.

**Communicate:** first open after long idle may be slow (~5–10s); iOS camera needs one OS grant once; hold barcode steady 1–2s on older phones.

**Do not hand off until:** G2 and G3 pass on a physical phone with this build.
