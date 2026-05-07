# AI Scan Engine Rebuild (Production) — Master

## Absolute success requirement (non-negotiable)

The handwritten note used in this project **MUST** extract the following **without failure**:

- **Supplier**: Surag
- **Broker**: kkk
- **Item**: Sugar 50kg
- **Quantity**: 100 bags
- **Purchase rate**: 57
- **Selling rate**: 58
- **Delivered rate**: 56
- **Payment days**: 7

## Goal

Rebuild the purchase bill/note scanner so it feels:

- **Fast**
- **Intelligent**
- **Alive (realtime progress)**
- **Reliable**
- **Trustworthy**
- **Production-ready**

## Core principles

- **Never blank**: if any signal is detected, the review screen must show it.
- **Partial success**: OCR/parse can be incomplete, but scan must still open in review.
- **Multi-pass everything**: preprocessing + OCR + parse + inference are multi-pass with merge.
- **Trader-first UX**: clear, specific messages (no generic “something went wrong”).
- **Deterministic fallbacks**: regex/rule parsing for common trader note formats.

## Architecture overview

### Backend (FastAPI)

- **Start**: `POST /v1/me/scan-purchase-v3/start` → `scan_token`
- **Poll**: `GET /v1/me/scan-purchase-v3/status?scan_token=...` → `ScanResult` (partial, live)
- **Confirm**: existing v2 confirm flow remains the “save after review” gate

Scanner v3 runs a background job that updates:

- `scan_meta.stage` (backend truth)
- `scan_meta.stage_progress` (0–1)
- `scan_meta.stage_log` (history of steps + timestamps)
- `scan_meta.error_*` (typed, UX-safe error hints)

### Frontend (Flutter)

`ScanPurchaseV2Page` uses v3 start/status:

- Shows **live progress list** (from `scan_meta.stage_log`)
- Shows image preview + extracted fields + editable rows
- Never shows empty review

## Work breakdown (docs 91–109)

- `docs/91_MULTIPASS_OCR_ARCHITECTURE.md`
- `docs/92_HANDWRITING_ENGINE.md`
- `docs/93_AI_SEMANTIC_PARSE.md`
- `docs/94_SUPPLIER_MATCHING_ENGINE.md`
- `docs/95_BROKER_MATCH_ENGINE.md`
- `docs/96_PACKAGE_DETECTION_ENGINE.md`
- `docs/97_RATE_INFERENCE_SYSTEM.md`
- `docs/98_PROGRESSIVE_VALIDATION_UI.md`
- `docs/99_FIELD_CONFIDENCE_SYSTEM.md`
- `docs/100_PARTIAL_SUCCESS_MODE.md`
- `docs/101_OFFLINE_SCAN_QUEUE.md`
- `docs/102_IMAGE_PREPROCESSING.md`
- `docs/103_RETRY_AND_TIMEOUT_SYSTEM.md`
- `docs/104_ERROR_MESSAGE_GUIDELINES.md`
- `docs/105_SCAN_REVIEW_SCREEN.md`
- `docs/106_SCAN_QA_CHECKLIST.md`
- `docs/107_WHOLESALE_TRADE_PARSE_RULES.md`
- `docs/108_MALAYALAM_HANDLING.md`
- `docs/109_AI_SCAN_PERFORMANCE.md`

## Definition of done

- The critical handwritten note parses exactly as required (see top).
- Progress UI shows real stages (no fake spinner).
- Review screen always has content (partial success).
- Field confidence is shown as **HIGH / MEDIUM / LOW**.
- Automated tests cover critical note + negative cases.

