# 00 — MASTER STATUS DASHBOARD

> Place ALL files in `flutter_app/.cursor/` folder. Cursor agent reads them via `@.cursor/filename.md`
> Start every session: `@.cursor/00_STATUS.md` then the specific file for your task.

---

## VERIFIED CURRENT STATE (from screenshots + code, 6 May 2026)

### 🔴 CRITICAL — Broken, blocks usage


| #   | Bug                                                    | File                                    | Spec                                                                      |
| --- | ------------------------------------------------------ | --------------------------------------- | ------------------------------------------------------------------------- |
| C1  | Reports shows ₹0 / "No purchases in period" every time | `reports_provider.dart`                 | `06_REPORTS.md` — ✅ summary + unfiltered fallback                         |
| C2  | OCR scan reads raw JPEG bytes (JFIF binary shown)      | `purchase_scan_service.py`              | `13_SCAN_OCR.md` — ✅ fixed earlier                                        |
| C3  | WhatsApp "create broker" shows "Type: Supplier"        | `entity_preview_card.dart` + LLM intent | `14_WHATSAPP.md` — ✅ fixed earlier                                        |
| C4  | WhatsApp "Save schedule" + "Send test" do nothing      | `settings_page.dart`                    | `14_WHATSAPP.md` — ✅ fixed earlier                                        |
| C5  | Server waking up every time (cold start)               | Render free tier                        | `10_PERFORMANCE.md` — ⚠️ app: longer `/health` warm-up (`api_warmup.dart`); host tier is ops |
| C6  | Back button broken on some pages                       | Router/GoRouter                         | `17_NAVIGATION.md` — ✅ dialogs/sheets use `context.pop` (app-wide; `Navigator.pop` removed) |


### 🟡 PARTIAL — Works but wrong


| #   | Bug                                                      | File                                        | Spec                                                |
| --- | -------------------------------------------------------- | ------------------------------------------- | --------------------------------------------------- |
| P1  | Commission — unit type picker (bag/kg) missing in Terms  | `purchase_terms_only_step.dart`             | `03_TERMS.md` — ✅ Fixed ₹ + “Commission applies to” |
| P2  | Item unit selector not showing options (no dropdown)     | `purchase_item_entry_sheet.dart`            | `02_ITEM_ENTRY.md` — ✅ dropdown                     |
| P3  | Workspace name field "not editable" (save not working)   | `business_profile_page.dart` + branding API | `09_SETTINGS.md` — ✅                                |
| P4  | After Terms → shows item list instead of going to Review | Wizard step logic                           | `01_WIZARD.md` — ✅ Party→Terms→Items→Review         |
| P5  | Reports page tabs take huge space, bad layout            | `reports_page.dart`                         | `06_REPORTS.md` — ✅ compact row                     |
| P6  | Basmathu shows ₹1,300→₹1,350 instead of ₹26→₹27/kg       | `reports_item_metrics.dart`                 | `15_REPORTS_FIX.md` — ✅                             |
| P7  | Alerts & Reminders page empty                            | `notifications_page.dart`                   | `14_WHATSAPP.md` — ✅ filter empty state             |


### ❌ NOT DONE — Features missing


| #   | Feature                                              | Spec                                               |
| --- | ---------------------------------------------------- | -------------------------------------------------- |
| N1  | Broker list not seeded in DB                         | `16_SEED_DATA.md` — ⚠️ **ops:** run `seed_catalog_and_suppliers` (loads `data/brokers_seed.json`) |
| N2  | Products/categories not seeded                       | `16_SEED_DATA.md` — ⚠️ **ops:** same script + `data/files/*.json` |
| N3  | Supplier ledger search (invoice/item)                | `12_SUPPLIER_DETAIL.md` — ✅ human id + PUR id      |
| N4  | Broker ledger/history page                           | `broker_history_page` + `/broker/:id/ledger` — ✅   |
| N5  | PDF download/print from detail                       | `08_PDF.md` — ✅ detail AppBar + PDF                |
| N6  | Bag qty label ("No. of bags")                        | `02_ITEM_ENTRY.md` — ✅                             |
| N7  | Line display helper (bags•kg everywhere)             | `02_ITEM_ENTRY.md` — ✅                             |
| N8  | Compact history cards                                | `04_HISTORY.md` — ✅ tighter row (~64pt min, denser type) |
| N9  | "Total spend" removed everywhere                     | `04_HISTORY.md` — ✅ (no copy)                      |
| N10 | Draft WIP card in History tab                        | `07_DRAFT.md` — ✅                                  |
| N11 | WhatsApp auto-report scheduling (real notifications) | `09_SETTINGS.md` — ✅ local schedule + tap opens WhatsApp with report; ❌ no server-push/cron |
| N12 | Broker statement PDF                                 | `08_PDF.md` — ✅ `broker_statement_pdf` + broker UI |


### ✅ DONE — Confirmed working


| Feature                                                  |
| -------------------------------------------------------- |
| Suggestion tap fix (`_pick()` sync)                      |
| Auto-advance removed (supplier pick stays on party step) |
| Draft auto-save 800ms                                    |
| Resume draft banner                                      |
| DB pool pre_ping                                         |
| Reports date filter uses `purchase_date`                 |
| Item entry kg per bag field                              |
| Rate toggle ₹/kg vs ₹/bag                                |
| ML last-trade rate auto-fill                             |
| WhatsApp assistant for purchases (basic)                 |
| "Server waking up" banner on cold start                  |
| Commission % and Fixed ₹ toggle                          |
| Total kg/bags/boxes/tins in reports overview             |


---

## SESSION WORKFLOW

### To fix C1 (Reports ₹0):

```
@.cursor/06_REPORTS.md  fix all ❌ tasks
```

### To fix C2 (OCR binary):

```
@.cursor/13_SCAN_OCR.md  fix all ❌ tasks
```

### To fix C3+C4 (WhatsApp):

```
@.cursor/14_WHATSAPP.md  fix all ❌ tasks
```

### To seed broker + product data:

```
@.cursor/16_SEED_DATA.md  run Supabase MCP tasks
```

### To fix item entry bag logic:

```
@.cursor/02_ITEM_ENTRY.md  fix all ❌ tasks
```

---

## NEVER CHANGE

- `PurchaseDraft` model JSON keys
- `OfflineStore` key names  
- GoRouter route names/paths
- `HexaColors.brandPrimary`
- `alembic/versions/` files
- Backend Pydantic request schemas

## ALWAYS DO

- `InkWell` not `GestureDetector` for suggestion tiles
- `MediaQuery.viewInsetsOf(context)` for keyboard padding
- Try/catch + SnackBar on all async button actions
- `_isSaving` guard to disable buttons during async
- `if (!mounted) return;` after every await

