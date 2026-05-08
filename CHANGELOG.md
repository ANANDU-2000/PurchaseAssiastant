# Changelog

All notable changes to this project are documented here. Append new entries under **Unreleased** when completing tasks (per MASTER_AGENT_RULES).

## Unreleased

### Added

- Agent rule sources under `context/rules/` (`MASTER_AGENT_RULES.md`, `TRACK.md`, `TASKS.md`, `AI_SCANNER_SYSTEM_PROMPT.md`, `CURSOR_AGENT_EXECUTION_PROMPT.md`).
- Repository root trackers `TRACK.md` and `TASKS.md` aligned with Flutter/FastAPI stack wording.
- Cursor always-on rule `.cursor/rules/purchase-assistant-master.mdc` pointing agents to those sources.

### Changed

- `context/CURSOR_AGENT_EXECUTION_PROMPT.md` reduced to an index pointing at `context/rules/` (avoid maintaining duplicate mega-prompt in two places).

- **Scanner / OCR policy:** `purchase_scan_service.image_bytes_to_text` now uses **OpenAI Vision only** (preprocess variants still allowed); Google Vision and Gemini image→text removed from the purchase-bill path.
- **Legacy `POST /v1/me/scan-purchase`:** delegates to `scan_purchase_v2` and maps `ScanResult` → legacy response (no `ocr_parser` regex path).
- **`POST /v1/me/scan-purchase-v2`:** fixed `UnboundLocalError` from `del user` before `user_id=user.id`; docstrings aligned with Vision-first pipeline.
- **Docs:** `docs/05_AI_SCANNER.md` pipeline updated; `ocr_parser.py` module doc clarified as non-scan-path helper.
- **Flutter:** comment on `scanPurchaseBillV2Multipart` updated (Vision, not OCR).

- **Scanner prompt + schema alignment:** `scanner_v2/prompt.py` unified strict instructions (`not_a_bill`, invoice/fingerprint fields, item aliases). Pipeline normalizes `item_name` / `unit` / `total_weight_kg`; optional `ScanResult` bill metadata; `NOT_A_BILL` + `TOTAL_MISMATCH` handling; confirm uses scanned `invoice_number` when request omits it. Scanner v3 parity for `not_a_bill`, normalization, broker commission, bill metadata. Tests: `tests/test_scanner_llm_normalize.py`. Flutter shows `NOT_A_BILL` messaging.

- **Scanner preview totals (BOX/TIN):** same ₹/kg vs ₹/piece heuristic as BAG for rates under ₹500: use `total_kg × rate`, else `qty × weight_per_unit_kg × rate`, else `qty × rate` for large per-unit rates; `BOX_TIN_WEIGHT_MISSING` warning when kg cannot be inferred. Broker match state now keeps `needs_review` true unless broker is `auto` (v2 + v3). Tests: `tests/test_scanner_preview_line_total.py`.
- **Vision prompt:** BOX/TIN lines asked to include `total_kg` or `weight_per_unit_kg`+`qty` when rate is per kg.
