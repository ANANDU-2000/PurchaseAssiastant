# PURCHASE ASSISTANT — TASKS

Canonical copy for editing: repository root [TASKS.md](../../TASKS.md). Keep both in sync when changing phases.

Agent policy: [MASTER_CURSOR_RULES.md](./MASTER_CURSOR_RULES.md), [AUTONOMOUS_CURSOR_EXECUTION_RULES.md](./AUTONOMOUS_CURSOR_EXECUTION_RULES.md).

# PHASE 0 — CLEANUP

- [ ] Remove OCR packages
- [ ] Remove OCR UI
- [ ] Remove OCR parsing
- [x] Remove OCR backend — **purchase bill path:** Google Vision + Gemini image extract removed from `purchase_scan_service`; bills use OpenAI Vision only (see CHANGELOG)
- [ ] Flutter: client-side image compression and stable upload helpers (where missing)
- [ ] Flutter: toasts / snackbars for scan and save flows (match existing patterns)
- [ ] Flutter: state/cache patterns consistent with existing app architecture

---

# PHASE 1 — CORE BUG FIXES

## Dashboard

- [ ] Create single aggregation endpoint
- [ ] Fix total calculations
- [ ] Fix stale refresh
- [ ] Add skeleton loader
- [ ] Add pull refresh

## Reports

- [ ] Pagination
- [ ] Date filtering
- [ ] Error boundaries
- [ ] Empty states

## History

- [ ] Search
- [ ] Multi select
- [ ] Bulk delete
- [ ] Edit flow
- [ ] Swipe actions

## Ledger

- [ ] Horizontal scroll table
- [ ] Sticky headers
- [ ] Prevent truncation
- [ ] Responsive columns

---

# PHASE 2 — AI SCANNER

## Scanner UI

- [ ] Camera capture
- [ ] Gallery upload
- [ ] Compression
- [ ] Loading state
- [ ] Error state

## OpenAI Vision

- [x] Add strict system prompt (`scanner_v2/prompt.py`; includes `not_a_bill`, invoice/fingerprint)
- [x] JSON validation / normalization (alternate keys → matcher schema)
- [ ] Error handling (broader edge cases)

## Entity Engine

- [ ] Supplier matching
- [ ] Broker matching
- [ ] Item matching
- [ ] Auto-create entities

## Duplicate Prevention

- [ ] Fingerprint generation
- [ ] Duplicate modal
- [ ] Existing bill detection

---

# PHASE 3 — PURCHASE FORM

- [ ] Multi-step wizard
- [ ] Step validation
- [ ] Unit conversion engine
- [ ] Margin calculation
- [ ] Rate validation
- [ ] Dynamic items
- [ ] Final review screen

---

# PHASE 4 — DATABASE

- [ ] Idempotency key
- [ ] Fingerprint index
- [ ] Performance indexes
- [ ] Scan logs
- [ ] Pagination support
- [ ] Aggregation queries

---

# PHASE 5 — UI SYSTEM

- [ ] Safe area
- [ ] Theme system
- [ ] Typography system
- [ ] Table system
- [ ] Skeleton system
- [ ] Toast system

---

# PHASE 6 — PERFORMANCE

- [ ] Client caching strategy (Flutter)
- [ ] Optimistic updates
- [ ] Lazy loading
- [ ] Memoization
- [ ] Query optimization
- [ ] DB pooling
