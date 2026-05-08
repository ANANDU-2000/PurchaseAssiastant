# PURCHASE ASSISTANT — TASKS

Agent policy (verbatim): `context/rules/MASTER_CURSOR_RULES.md`, `context/rules/AUTONOMOUS_CURSOR_EXECUTION_RULES.md`.

Each item below should eventually note **priority**, **modules**, **dependencies**, **validation** when you pick it up.

Section order matches **AUTONOMOUS_CURSOR_EXECUTION_RULES.md** (TASKS structure).

---

# Pending

## Dashboard & reports

- [ ] **P1** — Single aggregation endpoint / contract for home KPIs — _Validation: parity test vs purchase detail_
- [ ] **P1** — Fix stale refresh after mutations — _Modules: providers — Validation: create purchase → home updates_
- [ ] **P2** — Skeleton loaders, pull-to-refresh — _Flutter home_

## AI scanner & extraction

- [ ] **P1** — Charges/terms extraction completeness (freight, bilty, delivered, commission, broker figure, PD) — _backend scanner + prompt — Validation: golden bills_
- [ ] **P2** — Multi-page `images[]` merge — _API + Flutter picker — Validation: 2+ photos one draft_
- [ ] **P2** — Malayalam / Manglish normalization dictionary — _backend normalize — Validation: fixture texts_

## Match engines

- [ ] **P1** — Supplier match (aliases, phone, history) — no silent create — _backend + Flutter confirm UX_
- [ ] **P1** — Broker match — same — _backend + Flutter_
- [ ] **P1** — Item match priority chain + fuzzy + confidence — _MATCH_ENGINE.md_
- [ ] **P2** — Duplicate bill / purchase detection UX — _fingerprint API_

## UI / UX (ERP table, viewport)

- [ ] **P2** — ERP-style item table (columns: Item, Qty, Unit, P, S, Profit, Confidence) + expandable rows — _wizard + tokens_
- [ ] **P2** — iPhone 16 Pro (393×852) safe-area + bottom bar equal width — _scan + wizard_
- [ ] **P2** — Keyboard-safe modals / full-screen edit option — _edit sheets_

## Performance & infra

- [ ] **P2** — Debounced search, pagination/virtualization for long lists — _catalog, history_
- [ ] **P3** — DB indexes, scan logs table (if not present) — _migrations_

---

# In progress

- [ ] **P0** — Matcher follow-ups (supplier-scoped search param, ranking, aliases) after pack gate + edit autocomplete — _Modules: `scanner_v2/matcher.py`, `search.py` — Validation: golden scans_
- [ ] **P2** — Align scan **preview** with policy (minimal edit on scan screen; heavy edit only in draft wizard) — _Modules: `scan_purchase_v2_page.dart`, wizard — Validation: UX review_

---

# Completed

- [x] Purchase bill path: OpenAI Vision–based extraction (legacy OCR stacks removed from bill flow) — _see CHANGELOG_
- [x] Strict scan JSON / normalization helpers (baseline) — `scanner_v2`/`scanner_v3`
- [x] Purchase **draft wizard** route (`/purchase/scan-draft`) — scan does not single-button create purchase — _Flutter_
- [x] Scanner **pack gate** (kg hint + bag/piece channel) demotes unsafe auto item matches — `scanner_v2/pack_gate.py`, tests `test_scan_pack_gate.py`
- [x] Scan draft **item edit** live catalog suggestions — debounced `GET /v1/businesses/{id}/search` (`catalog_items`) in `scan_draft_edit_item_sheet.dart`; tap sets `matched_catalog_item_id` + optional last rates
- [x] Flutter **purchase detail cache** — shared `tradePurchaseDetailProvider`; invalidated after successful delete from detail, purchase home (single+bulk), supplier/broker/item ledgers, contacts trade ledger
- [x] Repo trackers + verbatim policy docs; **TASKS.md** section order per autonomous rules

# Blocked

- _(none — add row when dependency on external vendor/schema blocks work)_

---

# Critical

| Priority | Task | Affected modules | Dependencies | Validation |
|----------|------|------------------|--------------|------------|
| P0 | Wrong item match (wholesale line → wrong retail SKU) | scanner pipeline, matchers, catalog | DB aliases, item master fields | Scan sugar line → never maps to unrelated 1kg SKU |
| P0 | Unit / pack-size safety (bag/kg vs piece) | matcher, validation, item master | `bag_weight`, unit enums | Auto-match blocked on unit conflict |
| P0 | Reports/dashboard/detail/charts single source of truth | backend aggregates, Flutter providers | one contract per KPI | Month dashboard ↔ trade-summary parity test; extend to all KPI surfaces |
| P1 | Delete purchase → data & UI parity | delete API, soft-delete filters, Riverpod/cache | DB schema | Backend month KPIs drop after delete; Flutter all paths + stale UI TBD |

---

## Legacy phase backlog (reference)

<details>
<summary>Older PHASE 0–6 checklist (migrate items into sections above over time)</summary>

- Phase 0: Remove OCR packages/UI/client parsing where still present; compression helpers; toasts.
- Phase 1: History search, ledger tables, reports pagination.
- Phase 3–6: Wizard validation depth, idempotency keys, theme/table systems, pooling.

</details>
