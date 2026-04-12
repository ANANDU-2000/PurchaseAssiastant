# HEXA UI/UX — Page-by-page audit workflow

**Principle:** Don’t rebuild blindly. **Analyze → Fix → Improve**, one screen at a time.  
**One line:** *First make it clean, then make it powerful.*  
**Another:** *Best apps are confusion-free, not feature-stuffed.*

**Latest consolidated audit:** [page-audit-results.md](page-audit-results.md) (P0/P1 backlog, per-area flows, acceptance checks).

---

## 1. How to work with Cursor (or a human)

1. Pick **exactly one** page/flow (see §3 order).
2. Run **one** analysis prompt (§4–§8). Point to **real file paths** in this repo.
3. Review output: **P0** (must fix) vs **P1** (should fix) vs **P2** (nice to have) + **acceptance checks**.
4. **Confirm** which items to implement (usually **P0 only** first).
5. Implement → quick device check → mark acceptance checks done → **next page**.

**Standard instruction to paste:**

```text
Audit [PAGE_NAME] only using workflow Analyze→Fix→Improve; use prompt #[N];
propose P0/P1 + acceptance checks; implement P0 after I confirm.
```

---

## 2. Audit order (recommended)


| #   | Area                      | Primary Flutter entry (typical)                                                      | Notes                                    |
| --- | ------------------------- | ------------------------------------------------------------------------------------ | ---------------------------------------- |
| 1   | **Purchase Entry**        | `flutter_app/lib/features/entries/presentation/entry_create_sheet.dart`              | Highest impact; simple vs advanced costs |
| 2   | **Dashboard**             | `flutter_app/lib/features/home/presentation/home_page.dart`                          | Decision snapshot, metrics, insights     |
| 3   | **Contacts**              | `flutter_app/lib/features/contacts/presentation/contacts_page.dart` (+ detail pages) | Suppliers, brokers, categories, items    |
| 4   | **Reports / Analytics**   | `flutter_app/lib/features/analytics/presentation/analytics_page.dart`                | Charts, filters, date range              |
| 5   | **Settings**              | `flutter_app/lib/features/settings/presentation/settings_page.dart`                  | Toggles, voice copy, grouping            |
| 6   | **Cross-app consistency** | Shell, theme, shared widgets                                                         | After individual pages are stable        |


**Shell / nav (reference):** `flutter_app/lib/features/shell/shell_screen.dart`, `flutter_app/lib/core/router/app_router.dart`

---

## 3. Workflow steps (per page)


| Step        | Action                                                                                                                                          |
| ----------- | ----------------------------------------------------------------------------------------------------------------------------------------------- |
| **Analyze** | UI (overflow, hierarchy, spacing), UX (inputs, labels, defaults), logic (validation, calculations, preview/save), gaps (guidance, empty states) |
| **Fix**     | Address **confirmed P0** (and P1 if agreed)                                                                                                     |
| **Improve** | Polish: copy, contrast, micro-interactions — without scope creep                                                                                |


---

## 4. Prompt #1 — Master analysis (any single screen)

```text
Context: Flutter app HEXA — analyze ONLY this screen (files: [PASTE PATHS]).

Audit and return:

A) UI — overflow risks, scroll/safe area, spacing, hierarchy, small-phone density
B) UX — clicks to complete primary task, field order, labels, empty/error states
C) Logic — validation, calculations, duplicate/confusing fields, preview/confirm
D) Gaps — missing guidance, defaults, accessibility
E) Performance — obvious rebuild issues, heavy build methods

Output format:
1. Issues (ranked P0 / P1 / P2)
2. For each P0/P1: exact file + widget to change (no code until “implement”)
3. “Fixed layout” sketch (bullet hierarchy: section → widgets)
4. Acceptance checks (3–5 testable bullets)

Do NOT write code until I say “implement”.
```

---

## 5. Prompt #2 — Purchase Entry (priority)

```text
Analyze Purchase Entry only (modal/sheet + line model): [PATHS].

Focus:
- Field count vs primary task (fast happy path)
- Simple vs advanced: landed cost clarity; optional invoice / commission / transport
- Profit visibility before save
- Mobile: bottom sheet + scroll behavior

Return:
1. P0/P1/P2 issues
2. “Simple” default field list vs “Advanced” expandable groups
3. Label copy fixes (exact strings)
4. Validation rules (what blocks Preview / Save)
5. Acceptance checks

No code until “implement”.
```

---

## 6. Prompt #3 — Dashboard

```text
Analyze Dashboard only: [PATHS + providers if any].

Check:
- First seconds: profit vs cost vs next action
- Color semantics (profit / loss / cost) and contrast
- Insights (top item, risk, best supplier) when data exists
- Quick actions vs bottom nav overlap

Return:
1. Visual hierarchy (top → bottom)
2. P0/P1 issues
3. Card / color recommendations
4. Empty-state copy
5. Acceptance checks

No code until “implement”.
```

---

## 7. Prompt #4 — Contacts

```text
Analyze Contacts (list + detail flows): [PATHS].

Check:
- Navigation and sections (suppliers, brokers, categories, items)
- Supplier ↔ broker visibility
- Search / scanability / quick actions

Return:
1. Information architecture suggestion
2. P0/P1 issues
3. Search/filter gaps
4. Scope-disciplined quick wins vs backlog
5. Acceptance checks

No code until “implement”.
```

---

## 8. Prompt #5 — Reports / Analytics

```text
Analyze Reports/Analytics page: [PATHS].

Check:
- Chart readability (labels, units, range)
- Filters discoverability
- Summary vs detail for decisions

Return:
1. P0/P1 issues
2. “Above the fold” summary (≤3 metrics)
3. Filter UX improvements
4. Acceptance checks

No code until “implement”.
```

---

## 9. Prompt #6 — Settings

```text
Analyze Settings: [PATHS].

Check:
- Grouping (workspace, preferences, voice/AI)
- Label + subtitle clarity
- Toggles that are noop or confusing

Return:
1. Section order + group titles
2. Label rewrites
3. P0/P1 issues
4. Acceptance checks

No code until “implement”.
```

---

## 10. Prompt #7 — Cross-app consistency (after pages done)

```text
Cross-app consistency review (Flutter): [LIST MAIN ROUTES / FILES].

Compare:
- AppBar patterns (back, settings)
- Primary CTA vs FAB
- Money formatting + semantic colors (profit / loss / cost)
- Loading / error / empty patterns

Return:
1. Inconsistency table
2. Single “HEXA pattern” recommendation
3. P0-only file list

No code until “implement”.
```

---

## 11. Prompt #8 — Final polish & ship checklist

```text
Final polish — no new features.

Summarize recent UI changes, then provide:
- Regression checklist (login, entry preview/save, dashboard, contacts, reports)
- Copy pass for confusing strings
- Deferred P2 backlog

Output: go/no-go checklist (≤10 items).
```

---

## 12. Product targets (reference — not all at once)

These align with clarity-first delivery; implement **only** what each page’s audit confirms.


| Theme              | Direction                                                                                              |
| ------------------ | ------------------------------------------------------------------------------------------------------ |
| **Purchase Entry** | Default: **landed + selling**; **Advanced:** invoice, commission, transport                            |
| **Landing**        | Simple mode = **manual all-in landed** per line; advanced = split + commission math (document in UI)   |
| **Viewport**       | Prefer `SafeArea`, scroll, avoid rigid fixed heights on small screens                                  |
| **Nav**            | **4 tabs:** Home · Entries · AI · Reports; **Settings** top-right; **Contacts** reachable from Entries |
| **Colors**         | Profit → green, loss → red, cost → grey/neutral (see `HexaColors`)                                     |
| **Dashboard**      | Insights: top profit item, risk/attention, best supplier (when API provides)                           |
| **Risk control**   | Keep **Preview → Save**; don’t auto-save money from AI/voice without confirm                           |


---

## 13. Backend / AI env (separate from UI audit)

For local API (example only — see repo `.env.example`):

- `API_BASE_URL` / `DATABASE_URL` / JWT / feature flags  
- AI: `OPENAI_`*, `ENABLE_AI`  
- Voice: `ENABLE_VOICE`, `STT_*` (push-to-talk product policy is app copy + UX, not only env)

Malayalam + English: parsing/display policies belong in **AI + entry preview** specs, not in a blanket “rewrite all UI” prompt.

---

## 14. Related docs

- `docs/ux/user-flow-inventory.md` — **full route / tab / button / input map** (per-page flows)  
- `docs/ux/screen-map.md` — high-level screen map (links inventory)  
- `docs/flutter-architecture.md` — app structure  
- `.env.example` — environment template  

---

## 15. Critical risks & production gaps (tracked)

Use this table to prioritize work — **not** as a “rewrite everything” prompt.

| # | Risk | Target state | Repo status (honest) | Typical tier |
|---|------|--------------|----------------------|--------------|
| **R1** | Entry cost confusion (buy vs landed vs fees) | **One truth:** default = **manual landed / unit**; advanced = split (buy invoice, commission, transport) | **Partial:** `entry_create_sheet` has `_advancedEntryOptions`; simple still shows **line fields** (item, category, qty, catalog) — can feel busy | **P0** UX polish |
| **R2** | Mobile viewport / keyboard | `SafeArea`, `viewInsets` padding, scroll, avoid rigid fixed heights | Sheet uses `showModalBottomSheet` + `viewInsets` padding + `DraggableScrollableSheet` — **spot-check** small phones | **P0** QA + targeted fixes |
| **R3** | No strict design system | Tokens: spacing, radius, type scale, semantic colors | `HexaColors` exists; **no** `HexaSpacing` / `HexaRadius` **files** yet — add shared tokens + apply incrementally | **P1** |
| **R4** | Many entry “modes” (app, voice, WhatsApp, quick line) | **One pipeline:** normalize → **preview** → **confirm** → save | App entry matches; **align copy** on voice/WhatsApp with same rule; backend already preview-token based | **P1** product + copy |
| **R5** | Validation not documented in one place | Written rules + same checks client/server | Client validates before preview; server authoritative — **document canonical rules** (§16) | **P1** |
| **R6** | Analytics slow / empty flash | Stale-while-revalidate: show **cached** dashboard, then refresh | Riverpod invalidates on refresh — **optional** `keepAlive` + last-good snapshot | **P2** |
| **R7** | AI overreach | **Parse / suggest only**; **no** auto-save; **no** trusted math from model | Backend intent stub + app preview flow — **keep** guardrails in docs + API | **P0** policy |

**Dashboard insights** (best item, risk, best supplier): wired via `homeInsightsProvider` when API returns data — **empty state** and **loading** UX are the usual gaps, not missing endpoints.

**Offline queue:** not implemented — treat as **phase** (sync status UI + conflict rules).

**PIP / supplier comparison / % position:** map to `price_intelligence` / analytics APIs when product locks scope.

---

## 16. Canonical validation rules (purchase line — document of record)

Align Flutter + backend behavior; adjust only with a version note.

| Rule | Requirement |
|------|----------------|
| Item name | Required (non-empty trim) |
| Quantity | `> 0` |
| Unit | One of app-supported units (e.g. kg, bag, box, piece) |
| **Landed cost** | In **simple** mode: user’s landed field is **all-in** per unit (and maps to server `buy_price` / `landing_cost` as today). In **advanced**: invoice “purchase” per unit + commission/transport rules → **server** computes final landing. |
| Selling price | Optional for validation **warning**; required for profit display |
| Save | Only after **preview** + **`preview_token`** + explicit **confirm** (except duplicate override flow) |

Duplicate detection: server + `check-duplicate` / 409 path in app — **already present**; keep UX clear when forcing save.

---

## 17. Design system tokens (proposal — implement incrementally)

| Token | Suggested values | Flutter home |
|-------|------------------|--------------|
| **HexaSpacing** | `4, 8, 12, 16, 20, 24, 32` | New `lib/core/theme/hexa_spacing.dart` (or extend theme extensions) |
| **HexaRadius** | `12, 16, 20` (cards / sheets) | Same |
| **HexaColors** | `profit`, `loss`, `cost`, `primary` (+ existing) | `lib/core/theme/hexa_colors.dart` — already has profit/loss/cost |
| **Typography** | `display`, `title`, `body`, `label`, `money` | `ThemeData` text theme + one `HexaTextStyles` if needed |

**Rule:** new screens use tokens; old screens migrate when touched (page-by-page audit).

---

## 18. “Ultimate” full-project audit prompt (analysis only)

Use when you want a **roadmap document**, not an automatic rewrite:

```text
Do a production READ-ONLY audit of HEXA Purchase Assistant (Flutter + backend contracts).

Cover: UI/UX, purchase entry cost model, navigation, design tokens, validation, preview/save, AI/voice guardrails, analytics loading, performance red flags.

OUTPUT ONLY:
1. P0 / P1 / P2 issue list (file pointers where possible)
2. Architecture / consistency recommendations
3. Per-page refactor suggestions (no code)
4. Risk areas

Do NOT write or rewrite code in this task.
```

---

*Last updated: added §15–§18 (critical risks, validation, design tokens, audit-only mega-prompt).*