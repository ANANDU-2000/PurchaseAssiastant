# HEXA — Page-by-page UX audit results

**Method:** Analyze → Fix → Improve (audit-only deliverable).  
**Baseline:** [user-flow-inventory.md](user-flow-inventory.md), [audit-workflow.md](audit-workflow.md).  
**Date:** 2026-04-11

This document satisfies the **Page-by-Page UX Audit Plan**: per-area user flow, P0/P1/P2, keep/remove/merge, acceptance checks. Implementation of P0 is **out of scope** here unless separately confirmed.

---

## 1. Purchase Entry

**Primary files:** [entry_create_sheet.dart](../../flutter_app/lib/features/entries/presentation/entry_create_sheet.dart), [entries_page.dart](../../flutter_app/lib/features/entries/presentation/entries_page.dart), [home_page.dart](../../flutter_app/lib/features/home/presentation/home_page.dart), [voice_page.dart](../../flutter_app/lib/features/voice/presentation/voice_page.dart)

### 1.1 Current user flow

**Start points**

| # | Trigger | Result |
|---|---------|--------|
| A | Shell **FAB (+)** on any tab | `showEntryCreateSheet` |
| B | Home **Add entry** (gradient) / empty-state CTA | Same sheet |
| C | Entries empty state **Add entry** | Same sheet |
| D | Home **Voice** chip | `go('/ai')` — no prefill of sheet |
| E | AI tab: text → `aiIntent`; mic → `mediaVoicePreview` | Chat preview only; **Open Entries** + SnackBar — **no** JSON → sheet mapping |
| F | Home **Scan bill** | OCR API → SnackBar only — **no** handoff to sheet |

**Inside `EntryCreateSheet` (main controls)**

- **Advanced costs** switch (`_advancedEntryOptions`): off = hide invoice, commission, transport; on = show + `SegmentedButton` commission modes.
- **ExpansionTile** “Masters & quick-create”: chips (Supplier, Broker, Category, Item, Variant, Contacts hub).
- **Quick line** field + parse to line 1.
- **Entry date** picker.
- **Supplier** / **Broker** dropdowns (always visible in current layout).
- **Per line:** Item, Category, Qty, Unit, optional bag fields, purchase/landed field, landed readout (mode-dependent), SmartPricePanel (advanced landing), Selling, profit estimate.
- **Preview** → `AlertDialog` (lines + warnings) → **Save** calls `_confirmSave`.
- **`_confirmSave`** → bottom sheet “Confirm save” → `_runSaveAttempt` → client `checkDuplicate` → POST; **409** → duplicate dialog.

**Tap count (typical minimal path)**  
Open sheet (1) → fill line (many) → Preview (1) → Save in dialog (1) → Confirm & save in sheet (1) → **4+** chrome steps, not counting field entry.

### 1.2 Top UX problems

| ID | Severity | Issue |
|----|----------|--------|
| PE-P0-1 | P0 | **Double confirmation chrome:** Preview `AlertDialog` with Save immediately calls `_confirmSave`, which opens a **second** “Confirm save” bottom sheet. Users see two different “save” moments. |
| PE-P0-2 | P0 | **AI/Voice not integrated with entry sheet:** Intent JSON is display-only; **Add entry** goes to `/entries` list, not sheet with draft. Product promise “one pipeline” is broken for AI-started work. |
| PE-P1-1 | P1 | **Simple mode still heavy:** Supplier/broker, Masters expansion, Quick line, catalog icons remain visible — high cognitive load vs “landed + selling only” story. |
| PE-P1-2 | P1 | **Duplicate checks twice:** `checkDuplicate` before save + server 409 path — same risk, two surfaces (acceptable if copy is unified; currently easy to feel repetitive). |
| PE-P1-3 | P1 | **Preview dialog Save** label implies final save; actually triggers **another** confirm — naming/flow mismatch. |
| PE-P2-1 | P2 | OCR **Scan bill** implies data capture but only shows snack — set expectation in UI copy. |

### 1.3 Keep

- Server **`preview_token`** + confirm save contract.
- **`_advancedEntryOptions`** split for power users.
- Duplicate detection + `force_duplicate` escape hatch.
- Live totals bar (cost / kg / revenue / profit).
- Push-to-talk safety + AI “no auto-save” messaging on Voice page.

### 1.4 Remove / collapse / merge (recommendations)

- **Merge** Preview dialog + Confirm save into **one** read-only review step with single primary **Confirm & save** (keep token semantics).
- **Progressive disclosure:** In simple mode, move **Supplier/Broker** under same expansion as “More options” or below the fold.
- **AI:** Add **“Apply draft to entry”** (maps intent fields into sheet `initialLines` / `showEntryCreateSheet` args) — product scope.

### 1.5 Acceptance checks (for future P0 implementation)

1. After Preview, user sees **at most one** blocking confirmation before network save (or intentional explicit duplicate override only).
2. From AI tab, user can reach **prefilled sheet** OR clear copy that manual copy is required (pick one product rule).
3. Simple mode: primary visible fields ≤ **item, qty, unit, landed, sell** without scrolling past marketing blocks on a small phone.

---

## 2. Dashboard (Home)

**Primary files:** [home_page.dart](../../flutter_app/lib/features/home/presentation/home_page.dart), [home_insights_provider.dart](../../flutter_app/lib/core/providers/home_insights_provider.dart), [dashboard_period_provider.dart](../../flutter_app/lib/core/providers/dashboard_period_provider.dart)

### 2.1 Current user flow

- **AppBar:** Back (if stack), Refresh, `AppSettingsAction` → `/settings`.
- **Period:** Horizontal **ChoiceChips** (Today / Week / Month / Year — from `DashboardPeriod`).
- **Content order:** Range caption → **Hero profit** card → (if not empty) metric rows (Purchase, Profit | Margin, Purchases | Qty, Avg/purchase) → **Insights & alerts** (when `homeInsightsProvider` has data: loss lines, top item, needs attention, best supplier, API alerts) → **Quick actions**.
- **Quick actions:** Add entry (primary), chips: Voice, Scan bill, Reports, History (`/entries`), Catalog (`/catalog`).
- **Pull-to-refresh** invalidates dashboard + insights.

### 2.2 Top UX problems

| ID | Severity | Issue |
|----|----------|--------|
| DB-P1-1 | P1 | **Metric density:** Many cards in sequence — “decision snapshot” competes with raw counts; primary action vs scan order unclear. |
| DB-P1-2 | P1 | **Insights conditional:** When API thin/empty, dashboard feels “numbers only” — empty state for insights should explain next action. |
| DB-P2-1 | P2 | Quick actions partially overlap shell **FAB** (both add entry) — redundant but reinforces habit; optional consolidation. |

### 2.3 Keep

- Hero profit + period chips.
- Insights block when data exists (top item, risk, best supplier).
- Refresh + pull-to-refresh.

### 2.4 Remove / collapse / merge

- Consider **one** primary row: Profit + Purchase + one CTA strip; demote secondary metrics behind “Details” or Reports.
- Align **Scan bill** copy with actual OCR behavior (snack-only vs future handoff).

### 2.5 Acceptance checks

1. First screenful answers: **“Am I up or down?”** and **“What do I do next?”** within 5 seconds on a phone.
2. At least one **insight or empty-state CTA** visible when purchases exist.

---

## 3. Contacts

**Primary files:** [contacts_page.dart](../../flutter_app/lib/features/contacts/presentation/contacts_page.dart), [supplier_detail_page.dart](../../flutter_app/lib/features/contacts/presentation/supplier_detail_page.dart), [broker_detail_page.dart](../../flutter_app/lib/features/contacts/presentation/broker_detail_page.dart), [category_items_page.dart](../../flutter_app/lib/features/contacts/presentation/category_items_page.dart)

### 3.1 Current user flow

- **Route:** `/contacts` (from Entries people icon, Settings Data section).
- **AppBar:** Search (body-integrated), `AppSettingsAction`, **+** menu (add supplier / broker / category / item by tab).
- **Tabs (4):** Suppliers | Brokers | Categories | Items.
- **Search:** Debounced; at ≥2 chars replaces tab view with unified search results (suppliers, brokers, items, categories) with navigation to detail routes.
- **Supplier row:** tap → detail; phone **tel:**; overflow edit/delete (owner).

### 3.2 Top UX problems

| ID | Severity | Issue |
|----|----------|--------|
| CT-P1-1 | P1 | **Four tabs + search** feels like a mini admin — heavier than “contacts for entry” mental model. |
| CT-P1-2 | P1 | **Broker UUID** style fields in some dialogs (if still present) — high friction for linking supplier↔broker. |
| CT-P2-1 | P2 | **CRUD-first:** Limited “intelligence” (performance, avg price) on list — may live on detail/API; document as P2 if product wants list-level signals. |

### 3.3 Keep

- Global search ≥2 chars.
- Dial from supplier when phone exists.
- Tab separation by entity type.

### 3.4 Remove / collapse / merge

- Consider **default tab = Suppliers** + “More” for Categories/Items if most users only fix people.
- **Picker-based broker link** instead of raw UUID in create flows (UX polish).

### 3.5 Acceptance checks

1. New user finds **Contacts** from Entries or Settings in ≤2 tries (discoverability).
2. Create supplier **without** reading internal IDs (broker optional with picker).

---

## 4. Reports / Analytics

**Primary files:** [analytics_page.dart](../../flutter_app/lib/features/analytics/presentation/analytics_page.dart), [item_analytics_detail_page.dart](../../flutter_app/lib/features/analytics/presentation/item_analytics_detail_page.dart)

### 4.1 Current user flow

- **AppBar:** Title “Reports”, `AppSettingsAction`.
- **Tabs (5):** Overview | Items | Categories | Suppliers | Brokers (`TabBar` scrollable).
- **Date strip:** From / To pickers + chips: Today, Yesterday, This week, This month, This year, Last 7 days.
- **Per tab:** KPI or sortable tables; row taps navigate to item/supplier/broker detail where implemented.

### 4.2 Top UX problems

| ID | Severity | Issue |
|----|----------|--------|
| RP-P1-1 | P1 | **Two strong dimensions at once:** date controls + five tabs — high cognitive load for quick answers. |
| RP-P2-1 | P2 | Chart readability on small width — verify labels and scroll. |

### 4.3 Keep

- Preset date chips + custom From/To.
- Tab breakdown by business dimension.
- Drill-down to item analytics.

### 4.4 Remove / collapse / merge

- Optional **single summary strip** above tabs: profit, purchase, margin for range — then tabs for breakdown.
- Collapse presets into a **single** “Date range” control on mobile (P2).

### 4.5 Acceptance checks

1. User can answer **“How did we do this month?”** from Overview without switching tabs.
2. Changing date range updates all tabs consistently (invalidation already in code).

---

## 5. Settings

**Primary files:** [settings_page.dart](../../flutter_app/lib/features/settings/presentation/settings_page.dart), [app_settings_action.dart](../../flutter_app/lib/shared/widgets/app_settings_action.dart)

### 5.1 Current user flow

- **Route:** `/settings` (full screen, not shell tab).
- **Entry:** `AppSettingsAction` on Home, Entries, Reports, Contacts; **IconButton** on Voice page; Settings tiles in **Data** section also link to Contacts/Catalog.
- **Sections:** Workspace (business card) → Preferences (Smart autofill, Notifications) → Voice & AI (info tiles) → Data (Contacts, Catalog, Units info) → Sign out.

### 5.2 Top UX problems

| ID | Severity | Issue |
|----|----------|--------|
| ST-P1-1 | P1 | **Settings entry inconsistent:** Shell has **no** Settings icon (only per-screen AppBar + Voice); users may hunt for gear. |
| ST-P2-1 | P2 | **Units** row is informational only — label should not imply full unit editor until built. |

### 5.3 Keep

- Voice & AI policy copy (push-to-talk, confirm before save).
- Data links to Contacts and Catalog.
- Sign out.

### 5.4 Remove / collapse / merge

- Unify Settings access: **either** add one shell-level Settings **or** document “gear in each screen” as intentional and remove conflicting copy elsewhere.

### 5.5 Acceptance checks

1. User can reach Settings from **Home** in one obvious action.
2. Copy matches behavior for Units and notifications.

---

## 6. Cross-app navigation and consistency

**Primary files:** [app_router.dart](../../flutter_app/lib/core/router/app_router.dart), [shell_screen.dart](../../flutter_app/lib/features/shell/shell_screen.dart), [login_page.dart](../../flutter_app/lib/features/auth/presentation/login_page.dart), [splash_page.dart](../../flutter_app/lib/features/splash/presentation/splash_page.dart)

### 6.1 Canonical model (code)

- **Auth:** `/splash` → restore → `/home` or `/login`.
- **Shell (4 branches):** `/home`, `/entries`, `/ai`, `/analytics`.
- **FAB:** Opens entry sheet globally.
- **Shell top strip:** HEXA + **Entries** `TextButton` only — **no Settings** in shell.
- **Settings:** `/settings` via `AppSettingsAction` / Voice settings icon — `go`, full screen.
- **Contacts:** `/contacts` — not a tab.

### 6.2 Doc/code gaps fixed in repo (see git diff with this change)

- [user-flow-inventory.md](user-flow-inventory.md) shell row updated to match `shell_screen.dart` (no ⚙️ in strip).
- [shell_screen.dart](../../flutter_app/lib/features/shell/shell_screen.dart) class comment updated.
- [app_router.dart](../../flutter_app/lib/core/router/app_router.dart) comment updated.

### 6.3 Top UX problems

| ID | Severity | Issue |
|----|----------|--------|
| NA-P0-1 | P0 | **Inventory doc claimed shell ⚙️** — misleads QA/design; **corrected** in docs + comments. |
| NA-P1-1 | P1 | **Duplicate Entries affordance:** Shell top “Entries” + bottom tab **Entries** — same destination; consider removing strip shortcut or repurposing (e.g. Contacts). |
| NA-P1-2 | P1 | **Voice** uses custom settings `IconButton` instead of shared `AppSettingsAction` — minor inconsistency. |

### 6.4 Keep

- 4-tab shell + full-screen settings route.
- IndexedStack for tab state.

### 6.5 Acceptance checks

1. `docs/ux/user-flow-inventory.md` matches **shell_screen.dart** for top strip and FAB.
2. No doc states “5 tabs” or “Settings tab” for main shell.

---

## 7. Consolidated P0 / P1 backlog (cross-page)

| Priority | ID | Area | Summary |
|----------|-----|------|--------|
| P0 | PE-P0-1 | Entry | Unify Preview + final confirm into one step |
| P0 | PE-P0-2 | Entry + AI | Draft handoff from AI to sheet OR explicit product copy |
| P0 | NA-P0-1 | Docs | Align shell/settings docs with code (done in this pass) |
| P1 | PE-P1-1 | Entry | Collapse simple mode surface (supplier/broker/masters) |
| P1 | DB-P1-1 | Dashboard | Strengthen decision hierarchy / empty insights |
| P1 | CT-P1-1 | Contacts | Reduce admin feel; broker linking UX |
| P1 | RP-P1-1 | Reports | Summary-first layout option |
| P1 | ST-P1-1 | Settings | Unified Settings discoverability |
| P1 | NA-P1-1 | Shell | Resolve duplicate Entries shortcut |

---

## 8. Related documents

- [audit-workflow.md](audit-workflow.md) — how to run the next audit round  
- [user-flow-inventory.md](user-flow-inventory.md) — route/button inventory (keep in sync)  
- [screen-map.md](screen-map.md) — high-level map  

---

*End of page-by-page UX audit results.*
