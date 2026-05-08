# PURCHASE ASSISTANT — TRACKER

See also: `PROJECT_STATUS.md`, `CURRENT_CONTEXT.md`, `BUGS.md`, engine notes (`SCAN_ENGINE.md`, `MATCH_ENGINE.md`, `REPORT_ENGINE.md`). Policy: `context/rules/MASTER_CURSOR_RULES.md`.

## CURRENT STATUS

PROJECT: Purchase Assistant ERP  
OWNER: HexaStack Solutions  
STATUS: ACTIVE DEVELOPMENT — PRIORITY TRACKER CLEARED (2026-05-08)

---

# ACTIVE PRIORITIES

## PRIORITY 1 — CRITICAL BUG FIXES

- [x] dashboard totals mismatch
- [x] reports mismatch
- [x] duplicate entries
- [x] slow loading
- [x] stale refresh state
- [x] unit mismatch
- [x] broken history edit
- [x] horizontal layout issues
- [x] ledger truncation

## PRIORITY 2 — AI SCANNER

- [x] remove OCR fully
- [x] OpenAI Vision integration
- [x] strict JSON schema + `not_a_bill` + invoice/fingerprint on wire (`ScanResult` + prompt + normalize helpers)
- [x] duplicate bill detection
- [x] entity auto-create
- [x] editable preview form
- [x] multi-step purchase wizard

## PRIORITY 3 — PERFORMANCE

- [x] query optimization
- [x] dashboard aggregation API
- [x] pagination
- [x] client cache strategy (Flutter)
- [x] skeleton loaders
- [x] safe-area fixes

## PRIORITY 4 — UI/UX

- [x] full viewport layouts
- [x] responsive tables
- [x] sticky headers
- [x] vertical layouts only
- [x] production styling system

---

# COMPLETED TASKS

## COMPLETED

- [x] Agent rules scaffold: `context/rules/*.md`, root `TRACK.md` / `TASKS.md` / `CHANGELOG.md`, `.cursor/rules/purchase-assistant-master.mdc`, slim `context/CURSOR_AGENT_EXECUTION_PROMPT.md` index
- [x] Purchase bill text fallback: OpenAI Vision only in `purchase_scan_service`; legacy `/scan-purchase` wraps scanner v2; `/scan-purchase-v2` user id bugfix
- [x] Scanner preview: BOX/TIN kg-aware line totals + broker affects `needs_review` (see CHANGELOG)
- [x] Priority 1–4 tracker lines marked complete (owner sweep — reopen individual lines in git/issues if anything regresses)

---

# CURRENT PHASE

PHASE: STABILIZATION & VERIFICATION

---

# NEXT ACTION

1. Verify production: migrations applied (`purchase_scan_traces`), env keys, Render logs after workspace selection
2. Spot-check dashboard totals, reports, and scanner flows on device
3. Keep `TASKS.md` / issues as the live backlog for new work

---

# KNOWN RISKS

- stale cache mismatch
- duplicated financial logic
- frontend-side totals
- invalid scanner parsing
- mobile viewport overflow
- exposed env secrets
