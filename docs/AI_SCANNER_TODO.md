# AI Purchase Scanner V2 — Build TODO

Mandatory rule: **complete one task → update `PROGRESS_TRACKER.md` → run tests → only then move to the next**.

Tasks marked `[ ]` are pending, `[x]` done, `[~]` in progress, `[!]` blocked. Each task lists its acceptance condition.

---

## Phase A — Documentation (single source of truth)

- [x] **A1.** Write the 11 docs (`AI_SCANNER_SPEC.md`, `AI_SCANNER_TODO.md`, `AI_SCANNER_RISKS.md`, `AI_SCANNER_VALIDATIONS.md`, `AI_SCANNER_JSON_SCHEMA.md`, `AI_SCANNER_MATCHING_ENGINE.md`, `AI_SCANNER_UI_FLOW.md`, `AI_SCANNER_ERROR_HANDLING.md`, `AI_SCANNER_DUPLICATE_PREVENTION.md`, `AI_SCANNER_TEST_CASES.md`, `PROGRESS_TRACKER.md`).
  - **Done when:** all 11 markdown files exist under `/docs/` with the content this build refers to.

## Phase B — Backend foundation

- [ ] **B1.** Create package skeleton:
  - `backend/app/services/scanner_v2/__init__.py`
  - `backend/app/services/scanner_v2/types.py` — Pydantic `ScanResult` matching `AI_SCANNER_JSON_SCHEMA.md`.
  - `backend/app/services/scanner_v2/prompt.py` — system prompt for `gpt-4o-mini`.
  - **Done when:** `python -c "from app.services.scanner_v2 import ScanResult"` works inside `backend/.venv`.

- [ ] **B2.** Implement `scanner_v2/bag_logic.py` per `AI_SCANNER_MATCHING_ENGINE.md` §Unit type detection.
  - Tests: `backend/tests/scanner_v2/test_bag_logic.py` — 14 cases (50/30/25/15/10/5 kg bag, tin, ltr-tin, total-kg → bags, remainder warning, kg unit not multiplied).
  - **Done when:** all bag tests pass.

- [ ] **B3.** Implement `scanner_v2/matcher.py`.
  - Inputs: business_id, raw text, type ∈ `{supplier, broker, item}`.
  - Pipeline: alias exact → rapidfuzz token_sort → Manglish normalize → bucket.
  - Tests: `test_matcher_buckets.py` — `suraj` → SURAJ TRADERS auto, `barly` → BARLI RICE confirm, gibberish → unresolved.
  - **Done when:** matcher tests pass.

- [ ] **B4.** Implement `scanner_v2/validators.py` covering 13 rules.
  - Tests: `test_validators.py` for each code in `AI_SCANNER_VALIDATIONS.md`.
  - **Done when:** validators tests pass and integration tests show structured warnings in JSON.

- [ ] **B5.** Implement `scanner_v2/duplicate_detector.py` (extends `trade_purchase_service`).
  - Adds `total_kg ± 1%` and item-set Jaccard ≥ 0.7.
  - Tests: `test_duplicate_detector.py`.
  - **Done when:** tests pass; existing `force_duplicate` flag still bypasses.

- [ ] **B6.** Implement `scanner_v2/pipeline.py`.
  - Sequence: Vision → fallback to OpenAI multimodal → fallback to existing Gemini/Groq.
  - Then OpenAI `gpt-4o-mini` text-to-JSON; then matcher → bag-logic → validators → duplicate hint.
  - Tests: `test_pipeline_e2e.py` with mocked HTTP.
  - **Done when:** end-to-end mocked tests pass.

- [ ] **B7.** `scan_token` HMAC sign / verify in `scanner_v2/token.py` (re-uses `JWT_SECRET` if dedicated `SCAN_TOKEN_SECRET` not set).
  - Tests: `test_scan_token.py`.

## Phase C — Backend endpoints

- [ ] **C1.** Add `POST /v1/me/scan-purchase-v2` to [routers/me.py](../backend/app/routers/me.py).
  - Returns the canonical JSON + `scan_token`.
  - Tests: `test_endpoint_v2.py` (multipart upload, full JSON shape).
  - **Done when:** endpoint reachable; test green.

- [ ] **C2.** Add `POST /v1/me/scan-purchase-v2/correct`.
  - Body: `{scan_token, corrections: [{type, raw_text, ref_id}, …]}`.
  - Idempotent upsert into `catalog_aliases` (workspace scoped).
  - Tests: `test_alias_learning.py`.

- [ ] **C3.** Add `POST /v1/me/scan-purchase-v2/confirm`.
  - Body: edited payload + `scan_token` + `force_duplicate?: bool`.
  - Verifies token, runs validators, runs duplicate detector, calls `trade_purchase_service.create_trade_purchase`.
  - Returns `{trade_purchase_id, human_id}`.
  - Tests: `test_endpoint_v2_confirm.py` (happy path, dup 409, force=true success).

- [ ] **C4.** Run `pytest backend/tests -q`. Fix any regressions before moving to Flutter.

## Phase D — Flutter foundation

- [ ] **D1.** Extend [HexaApi](../flutter_app/lib/core/api/hexa_api.dart) with `scanPurchaseV2Multipart`, `scanPurchaseV2Correct`, `scanPurchaseV2Confirm`.
  - **Done when:** `flutter analyze` clean.

- [ ] **D2.** Add `scan_v2_provider.dart` (Riverpod `NotifierProvider`).
  - Holds `ScanResult`, dirty flag, undo edits, autosave to `OfflineStore` Hive box every 800 ms.
  - Computes derived totals as user edits.

- [ ] **D3.** Build widgets (`flutter_app/lib/features/purchase/presentation/widgets/scan_v2/`):
  - `scan_v2_table.dart` (5-col compact table, no horizontal scroll).
  - `scan_v2_row.dart` (inline-edit cells + "more" overflow icon).
  - `scan_v2_confidence_pill.dart`.
  - `scan_v2_advanced_section.dart` (delivered/billty/freight/payment-days/commission/discount, collapsed).
  - `scan_v2_save_bar.dart` (sticky bottom with running ₹ total + Save button).

- [ ] **D4.** Sheets:
  - `scan_v2_match_picker_sheet.dart` ("Did you mean X?" with top-3 + full picker fallback).
  - `scan_v2_line_more_sheet.dart` (line-level extras).

- [ ] **D5.** Build `ScanPurchaseV2Page`:
  - Image thumb + Re-scan button at top.
  - Supplier and broker rows below thumb.
  - Items table.
  - Advanced expander.
  - Sticky save bar.

- [ ] **D6.** Wire route `/purchase/scan-v2` in [app_router.dart](../flutter_app/lib/core/router/app_router.dart).

- [ ] **D7.** Feature flag in [purchase_home_page.dart](../flutter_app/lib/features/purchase/presentation/purchase_home_page.dart): if `ENABLE_AI_SCANNER_V2` (build define, default true) push v2; else legacy.

- [ ] **D8.** `PopScope` exit guard with confirmation dialog ("Unsaved purchase will be lost. Discard / Keep editing").

## Phase E — Quality gates

- [ ] **E1.** Widget tests:
  - `scan_v2_table_test.dart` — 5 cols visible at 393 pt, no horizontal scroll.
  - `bag_logic_client_test.dart` — local recompute on cell edit.
  - `popscope_unsaved_test.dart` — dirty + back triggers dialog.
  - `match_picker_test.dart` — confidence buckets render correct pills.
  - `confirm_save_test.dart` — payload sent matches server contract.

- [ ] **E2.** PDF cleanup pass: dedupe totals, hero numbers off, add Selling Rate column. Tests in `flutter_app/test/services/purchase_invoice_pdf_test.dart` (golden).

- [ ] **E3.** `/search` real-only mode: tests under `backend/tests/test_search_real_only.py`.

- [ ] **E4.** Final QA gate:
  - `pytest backend/tests -q` — green.
  - `flutter analyze` — 0 errors / 0 warnings.
  - `flutter test` — green.
  - Manual: scan handwritten Malayalam image, save, confirm History + Reports + Item Detail show the new row.
  - Update `PROGRESS_TRACKER.md` to "Done".

---

## Definition of Done (per task)

A task is **only** done when:

1. Code compiles / passes lint (`flutter analyze` for client, `ruff` if configured for backend).
2. All new tests for that task pass and **no existing test regresses**.
3. `PROGRESS_TRACKER.md` updated with the moved status, validation result, and next action.
4. The acceptance condition stated above is observably true (do not check off blindly).
