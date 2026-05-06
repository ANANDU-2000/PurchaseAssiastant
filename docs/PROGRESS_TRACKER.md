# PROGRESS TRACKER — AI Purchase Scanner V2

_Updated by every task in `AI_SCANNER_TODO.md`. Most-recent state at the top._

---

# Current Goal

Ship a production-grade AI Purchase Scanner V2 that converts handwritten / printed / WhatsApp purchase notes (English / Malayalam / Manglish / mixed) into validated, editable, structured `trade_purchases` rows with zero duplicates and zero invented data.

# Current Task

**B4 — Backend validation engine (in progress).**
Implementing `backend/app/services/scanner_v2/validators.py` + tests for the 13 trader-critical validation rules in `docs/AI_SCANNER_VALIDATIONS.md`.

# Completed

- Repo exploration: confirmed existing scan v1 endpoint at `POST /v1/me/scan-purchase`, reusable services (`purchase_scan_service.py`, `purchase_scan_ai.py`, `fuzzy_catalog.py`, `trade_purchase_service.py`), `CatalogAlias` table, and Flutter scaffolding (`PurchaseBillScanPanel`, `purchase_entry_wizard_v2`, `OfflineStore`, PDF builders, Riverpod state).
- Plan committed (see `.cursor/plans/ai_purchase_scanner_v2_*.plan.md`).
- **A1. Docs bootstrap** completed (all 11 docs created under `/docs/`):
  - `docs/AI_SCANNER_SPEC.md`
  - `docs/AI_SCANNER_TODO.md`
  - `docs/AI_SCANNER_RISKS.md`
  - `docs/AI_SCANNER_VALIDATIONS.md`
  - `docs/AI_SCANNER_JSON_SCHEMA.md`
  - `docs/AI_SCANNER_MATCHING_ENGINE.md`
  - `docs/AI_SCANNER_UI_FLOW.md`
  - `docs/AI_SCANNER_ERROR_HANDLING.md`
  - `docs/AI_SCANNER_DUPLICATE_PREVENTION.md`
  - `docs/AI_SCANNER_TEST_CASES.md`
  - `docs/PROGRESS_TRACKER.md`

- **B1. Backend types + prompt** completed:
  - `backend/app/services/scanner_v2/__init__.py`
  - `backend/app/services/scanner_v2/types.py`
  - `backend/app/services/scanner_v2/prompt.py`
  - Import check: `from app.services.scanner_v2 import ScanResult` OK.

- **B2. Bag logic** completed:
  - `backend/app/services/scanner_v2/bag_logic.py`
  - Tests: `backend/tests/scanner_v2/test_bag_logic.py` (36/36 pass)

- **B3. Matching engine** completed:
  - `backend/app/services/scanner_v2/matcher.py`
  - Tests: `backend/tests/scanner_v2/test_matcher_buckets.py` (11/11 pass)
  - Scanner_v2 tests total: `47 passed`.

# Pending

In strict order (one task at a time per `AI_SCANNER_TODO.md`):

- **B1.** scanner_v2 package skeleton + `types.py` (Pydantic ScanResult) + `prompt.py`.
- **B2.** `bag_logic.py` + tests (T-A.01 … T-A.14).
- **B3.** `matcher.py` + tests (T-B.01 … T-B.10).
- **B4.** `validators.py` + tests (T-C.01 … T-C.14).
- **B5.** `duplicate_detector.py` + tests (T-D.01 … T-D.10).
- **B6.** `pipeline.py` + e2e tests (T-E.01 … T-E.15).
- **B7.** `token.py` (HMAC scan_token).
- **C1.** `POST /v1/me/scan-purchase-v2`.
- **C2.** `POST /v1/me/scan-purchase-v2/correct` (alias learning, T-F.*).
- **C3.** `POST /v1/me/scan-purchase-v2/confirm` (save).
- **C4.** Run pytest, fix regressions.
- **D1–D8.** Flutter API client → state provider → widgets → page → route → flag → PopScope guard.
- **E1.** Flutter widget tests (T-G.01 … T-G.15).
- **E2.** PDF cleanup pass.
- **E3.** `/search` real-only mode.
- **E4.** Final QA gate (T-H.01 … T-H.10).

# Bugs

_None recorded yet._

# Blockers

_None._

# Next Action

Finish **B4** validators + tests. Then start **B5** duplicate detector extension (`scanner_v2/duplicate_detector.py`) + tests.

# Validation Status

| Layer | Status | Notes |
| --- | --- | --- |
| Specs (`/docs/AI_SCANNER_*.md`) | ✅ pass | A1 complete |
| Backend pipeline | 🟡 in progress | B4 validators in progress |
| Backend tests | 🟡 partial | scanner_v2 tests passing (47); full suite later |
| Flutter UI | ⏳ pending | starts at D1 |
| Flutter tests | ⏳ pending | starts at E1 |
| PDF | ⏳ pending | E2 |
| /search hardening | ⏳ pending | E3 |
| Manual smoke (T-H.*) | ⏳ pending | E4 |

---

## Update protocol (read me before editing)

1. When you start a task, move it from **Pending** to **Current Task** and set `# Validation Status` row to "🟡 in progress".
2. When you finish, move it to **Completed** with a one-line summary. Update **Next Action** to the next task in `AI_SCANNER_TODO.md` order.
3. If something breaks, log it in **Bugs** with reproduction steps. If it stops the build, also list it in **Blockers**.
4. Run the relevant tests and update **Validation Status** with result (✅ pass / ❌ fail / 🟡 partial).
5. Never delete history. This file is append-mostly; it is the project's memory.
