# TASK_PROGRESS

## Current task

- Repo validation + migration docs; push to `origin/main` (see git log).

## Blockers

- None

## Completed fixes (Phases A–C)

- Bag kg auto-detect end-to-end (Flutter + backend)
- BAG rate modes (₹/kg vs ₹/bag)
- BOX/TIN count-only hardening (kg always 0)
- Continue never silently disabled (wizard block reasons shown)
- Shared packaged quantity display across reports/home/detail/ledgers/history
- Added `flat_box` commission mode and tightened `flat_bag` to bag/sack only

## Purchase History rebuild (this session) — completed

- **Flutter**: `purchase_home_page.dart` — metric pills, month summary card, 82/18 search + sheet, quick chips All/Due/Paid/Draft, compact cards (`purchaseHistoryPackSummary` / headline), latest-first sort toggle, advanced filters (dates API, package kind, supplier/broker), softer load error, empty state, PDF share invalidates workspace.
- **Flutter**: `line_display.dart` — `purchaseHistoryPackSummary`, month stats, pack-kind filter helpers (uses `reportEffectivePack`).
- **Flutter**: `trade_purchases_provider.dart` — fetch limit **4000**, `tradePurchasesForAlertsParsedProvider`, month stats provider, alerts from full list; date range + advanced state providers; paid via primary API.
- **Flutter**: removed `due_soon_banner.dart`; tests in `test/line_display_test.dart`.
- **Docs**: `61`–`70` + this tracker.

## QA (automated) — last full run

- **Backend**: `pytest tests -q` — **168 passed** ✅
- **Flutter**: `flutter analyze` — **No issues found** ✅
- **Flutter**: `flutter test` — **79 passed** (full suite) ✅

## Database / tables (production or staging)

- **Required:** `cd backend && python -m alembic upgrade head` with `DATABASE_URL` set (see `backend/README.md`).
- **Optional SQL:** `backend/scripts/migrations/README.md` (supplemental scripts vs Alembic).

## QA (manual) — Purchase History (`docs/70_HISTORY_QA_CHECKLIST.md`)

- Pending: device passes (iPhone 14/16 Pro, small Android, tablet), realtime after create/edit/delete/mark paid/share, 4000-row truncation messaging, Due vs Overdue pill taps, mixed invoices.

## QA (manual) — legacy checklist

- Sugar 50kg / 100 bags
- Rice 26kg / 100 bags
- Atta 30kg / 100 bags
- Oil tin / 50 tins
- Sunrich box / 200 boxes
- Mixed invoice: bag + box + tin
- Commission: `flat_bag`, `flat_box`, `flat_tin`
- Viewports: keyboard open

## Pending work

- **History @ scale**: cursor pagination + list virtualization beyond 4k fetch (`docs/68_HISTORY_PERFORMANCE.md`).
- **Share metadata row icons**: `docs/69_WHATSAPP_SHARE_TRACKING.md`.
- Device QA: AI scanner (handwriting, blur, weak network) per prior tracker items.

## Latest changes (AI scanner — prior)

- **Flutter**: scan multipart + legacy scan use **120s** Dio timeouts; v3 status poll **45s** receive (`hexa_api.dart`).
- **Flutter**: `shouldQueueScanOffline` — send/receive timeouts are **not** treated as offline (`auth_error_messages.dart`).
- **Flutter**: clearer timeout strings in `friendlyApiError` (no generic “check network” for slow reads).
- **Flutter**: scan preview — zoom (`InteractiveViewer`), progress bar from `stage_progress`, 95s poll budget, **Review** + **Resume saved offline scan** (`scan_purchase_v2_page.dart`).
- **Backend**: v3 merges **LLM dict + `_fallback_parse_text`** when items or charges are missing; richer fallback (labels, `P/S` rates, payment days) (`scanner_v3/pipeline.py`).
- **Backend**: CLAHE image variant; Vision HTTP timeout **120s** (`preprocess.py`, `purchase_scan_service.py`).
- **Tests**: `tests/scanner_v3/test_fallback_parse.py` extended (labeled layout).
- **Docs**: updated `71_AI_SCANNER_ARCHITECTURE.md`, `72_IMAGE_PREPROCESSING.md`, `76_OCR_ERROR_HANDLING.md`.
