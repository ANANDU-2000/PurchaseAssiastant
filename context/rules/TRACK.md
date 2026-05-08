# PURCHASE ASSISTANT — TRACKER

Canonical copy for editing: repository root [TRACK.md](../../TRACK.md). Keep both in sync when changing priorities.

## CURRENT STATUS

PROJECT: Purchase Assistant ERP  
OWNER: HexaStack Solutions  
STATUS: ACTIVE DEVELOPMENT

---

# ACTIVE PRIORITIES

## PRIORITY 1 — CRITICAL BUG FIXES

- [ ] dashboard totals mismatch
- [ ] reports mismatch
- [ ] duplicate entries
- [ ] slow loading
- [ ] stale refresh state
- [ ] unit mismatch
- [ ] broken history edit
- [ ] horizontal layout issues
- [ ] ledger truncation

## PRIORITY 2 — AI SCANNER

- [ ] remove OCR fully
- [ ] OpenAI Vision integration
- [x] strict JSON schema + `not_a_bill` + invoice/fingerprint (prompt + pipeline + v3 parity)
- [ ] duplicate bill detection
- [ ] entity auto-create
- [ ] editable preview form
- [ ] multi-step purchase wizard

## PRIORITY 3 — PERFORMANCE

- [ ] query optimization
- [ ] dashboard aggregation API
- [ ] pagination
- [ ] client cache strategy (Flutter: e.g. Riverpod/cache managers as appropriate)
- [ ] skeleton loaders
- [ ] safe-area fixes

## PRIORITY 4 — UI/UX

- [ ] full viewport layouts
- [ ] responsive tables
- [ ] sticky headers
- [ ] vertical layouts only
- [ ] production styling system

---

# COMPLETED TASKS

## COMPLETED

- [x] Agent rules scaffold: `context/rules/*.md`, root `TRACK.md` / `TASKS.md` / `CHANGELOG.md`, `.cursor/rules/purchase-assistant-master.mdc`, slim `context/CURSOR_AGENT_EXECUTION_PROMPT.md` index
- [x] Purchase bill text fallback: OpenAI Vision only in `purchase_scan_service`; legacy `/scan-purchase` wraps scanner v2; `/scan-purchase-v2` user id bugfix
- [x] Scanner preview: BOX/TIN kg-aware line totals + broker affects `needs_review` (see CHANGELOG)

---

# CURRENT PHASE

PHASE: ARCHITECTURE REBUILD

---

# NEXT ACTION

1. Remove OCR
2. Create unified aggregation API
3. Fix unit normalization
4. Build AI scanner flow
5. Rebuild ledger tables

---

# KNOWN RISKS

- stale cache mismatch
- duplicated financial logic
- frontend-side totals
- invalid scanner parsing
- mobile viewport overflow
- exposed env secrets
