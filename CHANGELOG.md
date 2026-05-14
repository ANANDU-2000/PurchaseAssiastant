# Changelog

All notable changes to this project are documented here. Append new entries under **Unreleased** when completing tasks (per MASTER_AGENT_RULES).

## Unreleased

### Fixed

- **Flutter production UX:** Purchase history KPI strip now derives from the same list provider as cards (with alerts-only fallback while loading); filter-empty state shows clear actions; `PurchaseHomePage` forces History shell branch after first frame if misaligned; purchase detail GET uses 15s timeout; optional `TradePurchase` seed via `GoRouter` `extra` for immediate body while refreshing; global `_HexaErrorBoundary` treats common layout/lifecycle errors as non-fatal in all build modes; wizard Terms fields gain focus-scroll bindings; add-item sheet scrolls on item focus; supplier quick-create name field uses focus-scroll padding; shell bottom bar adds extra padding from home indicator; reports stall banner after 1.5s.
- **Vercel / Flutter web:** `purchase_item_entry_sheet.dart` imported `lib/features/purchase/pricing/*` but those files were not in git, so `flutter build web` failed (deploy exit 3). The pricing modules are now tracked in the repository.

### Added

- `docs/production-readiness/`: ten runbooks (`PURCHASE_DETAILS_STABILITY_FIX.md`, `GLOBAL_ERROR_BOUNDARY_REWRITE.md`, `KEYBOARD_OVERLAY_SYSTEM.md`, `IPHONE_SAFEAREA_AUDIT.md`, `PURCHASE_LIST_RENDER_FIX.md`, `REPORTS_LOADING_AND_RECOVERY.md`, `ADD_ITEM_FORM_UX_REBUILD.md`, `TERMS_PAGE_KEYBOARD_FIX.md`, `APPSTORE_STYLE_BOTTOM_NAV.md`, `FINAL_PRODUCTION_VALIDATION.md`).
- `flutter_app/lib/shared/widgets/keyboard_lifted_footer.dart`: optional animated footer lift for IME-safe CTAs.
- `bindFocusNodeScrollIntoView` in `flutter_app/lib/core/widgets/form_field_scroll.dart`.
- `context/tax_rebuild/`: ten markdown specs for Indian trader GST/rate UX (flow, calc rules, PDF/ledger, validation, QA, backup, readiness).
- `flutter_app/lib/features/purchase/pricing/purchase_line_preview_narrative.dart`: trader-readable purchase line preview strings aligned with `calc_engine`.
- `flutter_app/lib/features/purchase/pricing/purchase_tax_prefs.dart`: SharedPreferences for last GST Extra / GST Included (global + optional per-supplier purchase, global selling).
- Purchase PDF line table: GST % and GST ₹ columns; summary line for summed line GST where meaningful.
- `purchaseBillGstFreightSubtitle` in `line_display.dart` for purchase history rows (GST + freight rollups from parsed lines).

### Changed

- **Flutter purchase add-item:** GST segments relabelled to GST Extra / GST Included; narrative preview card with soft validation banners; full-page sticky preview/footer; wizard passes `gstPrefs` and supplier id for remembered modes; bottom-sheet keyboard inset locals restored; `AddItemEntryPage` forwards `gstPrefs` / `preferredSupplierId`. **Rates & GST** card combines ₹/kg toggle, purchase/selling amounts, and GST mode; **More** holds discount/tax/freight only; reduced scroll min-height; focus scroll + dynamic `scrollPadding` for pinned preview; stacked rate fields on full-page / narrow width. **Edit** affordances: item name (`Icons.edit_outlined`), unit / bags vs kg / qty (`Icons.swap_vert_outlined`).

- **Flutter purchase wizard:** Resume-draft `MaterialBanner` is hidden while the fullscreen add-item sheet is open and re-evaluated after the sheet closes; opening add-item without a supplier shows a clear SnackBar instead of doing nothing.

- `docs/AI_PURCHASE_VALIDATION_AND_SAFETY.md`: strict validation, NEVER/ALWAYS, match engines, financial safety, duplicate detection alignment with server.
- `docs/SCAN_GUIDE_UX_SPEC.md`: full-screen Scan Guide UX (shortcodes, languages, multi-page, CTA).
- `docs/AI_PURCHASE_DRAFT_ENGINE.md`: enterprise draft-first architecture (Vision-only, 4-layer matching, wizard steps, DB tables, UX rules).
- `backend/app/services/purchase_draft_engine.py`: shared confidence thresholds for future draft-first pipeline.

### Changed

- **Docs:** wizard steps in `AI_PURCHASE_DRAFT_ENGINE.md` aligned to screenshot flow (bill overview → item table → item matching → financial → validation); ASCII diagram updated.

- **Docs:** expanded screenshot backlog checklist + stakeholder wizard labels + four-layer worked example in `AI_PURCHASE_DRAFT_ENGINE.md`.

- **Docs:** synced `AI_PURCHASE_DRAFT_ENGINE.md`, `AI_PURCHASE_VALIDATION_AND_SAFETY.md`, `SCAN_GUIDE_UX_SPEC.md` with full screenshot-gap list, DB table names, numbered risks, Scan Guide prompt/normalization sections, explicit Riverpod-not-React-Query performance note.

- **Docs:** `docs/05_AI_SCANNER.md` — Related docs links to draft engine, validation safety, Scan Guide; expanded `AI_PURCHASE_DRAFT_ENGINE.md` (canonical 5-step wizard, draft vs persistence).
- **Flutter:** bootstrap failure screen shows exception text in debug builds; staged `[bootstrap]` logs in debug; GoRouter `errorBuilder` logs URI and offers Home / Login.
- **Flutter scan bill:** removed OCR-style checklist; Vision-first stage labels; confirm dialog before creating purchase; edit-item bottom sheet uses `useSafeArea`, scroll, keyboard padding.

- Agent rule sources under `context/rules/` (`MASTER_AGENT_RULES.md`, `TRACK.md`, `TASKS.md`, `AI_SCANNER_SYSTEM_PROMPT.md`, `CURSOR_AGENT_EXECUTION_PROMPT.md`).
- Repository root trackers `TRACK.md` and `TASKS.md` aligned with Flutter/FastAPI stack wording.
- Cursor always-on rule `.cursor/rules/purchase-assistant-master.mdc` pointing agents to those sources.

- `context/CURSOR_AGENT_EXECUTION_PROMPT.md` reduced to an index pointing at `context/rules/` (avoid maintaining duplicate mega-prompt in two places).

- **Scanner / OCR policy:** `purchase_scan_service.image_bytes_to_text` now uses **OpenAI Vision only** (preprocess variants still allowed); Google Vision and Gemini image→text removed from the purchase-bill path.
- **Legacy `POST /v1/me/scan-purchase`:** delegates to `scan_purchase_v2` and maps `ScanResult` → legacy response (no `ocr_parser` regex path).
- **`POST /v1/me/scan-purchase-v2`:** fixed `UnboundLocalError` from `del user` before `user_id=user.id`; docstrings aligned with Vision-first pipeline.
- **Docs:** `docs/05_AI_SCANNER.md` pipeline updated; `ocr_parser.py` module doc clarified as non-scan-path helper.
- **Flutter:** comment on `scanPurchaseBillV2Multipart` updated (Vision, not OCR).

- **Scanner prompt + schema alignment:** `scanner_v2/prompt.py` unified strict instructions (`not_a_bill`, invoice/fingerprint fields, item aliases). Pipeline normalizes `item_name` / `unit` / `total_weight_kg`; optional `ScanResult` bill metadata; `NOT_A_BILL` + `TOTAL_MISMATCH` handling; confirm uses scanned `invoice_number` when request omits it. Scanner v3 parity for `not_a_bill`, normalization, broker commission, bill metadata. Tests: `tests/test_scanner_llm_normalize.py`. Flutter shows `NOT_A_BILL` messaging.

- **Scanner preview totals (BOX/TIN):** same ₹/kg vs ₹/piece heuristic as BAG for rates under ₹500: use `total_kg × rate`, else `qty × weight_per_unit_kg × rate`, else `qty × rate` for large per-unit rates; `BOX_TIN_WEIGHT_MISSING` warning when kg cannot be inferred. Broker match state now keeps `needs_review` true unless broker is `auto` (v2 + v3). Tests: `tests/test_scanner_preview_line_total.py`.
- **Vision prompt:** BOX/TIN lines asked to include `total_kg` or `weight_per_unit_kg`+`qty` when rate is per kg.
