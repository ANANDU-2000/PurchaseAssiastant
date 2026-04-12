# HEXA — Premium SaaS UI / UX Blueprint

**Status:** Product north star (not implementation).  
**Audience:** Design, product, engineering.  
**Principle:** *Guide the business owner — don’t just show screens.*

---

## Executive summary (final truth)

| Dimension | Today | Target |
|-----------|--------|--------|
| **Function** | Strong (API, math, flows exist) | Keep |
| **Experience** | Fragmented; feature-first | **Journey-first** |
| **Feel** | Tool / admin | **Product** — calm, decisive, premium |

**One line:** Users should complete **Add purchase → See profit → Improve next decision** without guessing what to tap next.

**One line (critical):** *Make it guide the user — not just show screens.*

---

## Part A — The ONE journey (everything else serves this)

```
See clarity (profit + risk)
        ↓
Add or fix a purchase (fast)
        ↓
See impact immediately (feedback + trends)
        ↓
Decide better next time (insights, comparisons)
```

**Rule:** Every primary screen must answer one of:

1. **Where am I financially?** (Overview / Analytics)
2. **What do I add or fix now?** (Entry / AI assist)
3. **Who / what moves my numbers?** (Contacts enriched with history)
4. **What should I worry about?** (Alerts, “needs attention”)

If a screen doesn’t support (1)–(4), it’s secondary or should be merged/hidden.

---

## Part B — Ranked UX problems (priority order)

| Rank | Problem | User pain | Blueprint direction |
|------|---------|-----------|---------------------|
| **P0** | No single guided journey | Cognitive load; feels like disconnected tools | Single journey (above) + copy + default paths |
| **P0** | Entry: too much at once | No “5 second” feel | **Default lane:** Item → Qty → Landing → Selling → Preview → Save; rest under **Advanced** |
| **P1** | Contacts = CRUD graveyard | “Why am I here?” | Cards show **totals, avg price, profit, last purchase** (supplier); **margin, trend** (item) |
| **P1** | Category → Item → Variant unclear | Wrong mental model | **Enforced hierarchy:** Category → Item → Variant (copy + navigation + validation) |
| **P1** | Dashboard flat; no hierarchy | Doesn’t feel “premium” | Hero profit + **3 insight zones**: top profit item, needs attention, loss / risk |
| **P1** | Analytics = tables only | No decisions | Headline KPIs + **best/worst** + **comparisons** + simple charts (trend, profit by dimension) |
| **P2** | AI isolated from entry | “Separate product” | Draft → **same** preview/save pipeline; optional price hints on same screen |
| **P2** | Empty states generic | Dead feeling | **Action-led** copy + one primary CTA tied to journey |
| **P2** | Visual system inconsistent | Not “SaaS premium” | Tokenized **depth** (elevation, radius), **semantic colors** (profit / loss / warning), spacing scale |

---

## Part C — Simplified app flow (target)

```
Overview (Dashboard)
  ├─ Primary: profit hero + 2–3 insight cards + ONE clear “Add purchase”
  ├─ Secondary: period, refresh, contacts shortcut
  │
Purchase log (Entries)
  ├─ List with filters; tap → detail (history for that entry)
  ├─ Empty: one CTA “Add first purchase” + one line why it matters
  │
  + (global) → Entry sheet (FAST default + Advanced)
  │
Contacts (data that supports entries)
  ├─ Tabs: Suppliers | Brokers | Categories | Items
  ├─ Each row/card: identity + KPIs + last activity + drill to history
  └─ Structure messaging: Category → Item → Variant (breadcrumbs / labels)

Analytics
  ├─ Same date model as Overview
  ├─ Top: decisions (best/worst, comparisons)
  └─ Below: tables/charts as evidence

AI
  └─ Produces **draft** → Opens / fills entry sheet → Preview → Save (never a parallel save path)
```

**Remove / de-emphasize:** Duplicate “add” affordances on the same screen; duplicate nav labels; raw UUID fields in create flows (use pickers).

---

## Part D — Screen-by-screen premium spec

### D1 — Overview (Dashboard)

**Job:** *“Am I winning, and what needs attention?”*

| Element | Spec |
|---------|------|
| **Hero** | Single dominant profit number; optional subtle motion on load; gradient depth (not flat grey) |
| **Insight row** | **Top profit item** · **Needs attention** · **Loss / risk** (only when data exists) |
| **Period** | Obvious; affects everything below |
| **Primary CTA** | One: add purchase (not 3 competing buttons) |
| **Quick actions** | Secondary: Voice, Scan, Reports, History, Catalog — not clones of the same action |

**Avoid:** Same metric repeated 6 times with no ordering.

---

### D2 — Entry (sheet)

**Job:** *“Log a purchase in seconds; power when needed.”*

| Mode | Fields (default) |
|------|------------------|
| **Fast (default)** | Item · Qty · Unit · Landing cost · Selling price → Preview → Save |
| **Advanced** | Supplier, broker, invoice, transport, commission, catalog variant, etc. |

**Rules:**

- One visible “primary column” of inputs on mobile.
- Advanced is **collapsed** until toggled.
- Preview is **one** confirmation moment (not two different dialogs saying “save”).
- Copy explains: *Nothing is saved until you confirm.*

---

### D3 — Contacts

**Job:** *“People and catalog that explain my purchases — not a separate database admin.”*

**Supplier card (list or detail):**

- Name, phone (actions)
- **Total purchases** (period or all-time — pick one and be consistent)
- **Avg buy / landed** (as relevant)
- **Profit attributed** (if computable)
- **Last purchase date**
- **CTA:** View entries / history filtered to this supplier

**Item card:**

- Name, category
- **Avg landing**, **avg selling**
- **Margin %** (or profit per base unit)
- **Trend** (↑ ↓ flat) vs prior period if data allows
- Link to **entries** using this item

**Structure (enforced in UI + copy):**

```text
Category (e.g. Oil)
  → Item (e.g. Sunflower oil)
      → Variant (e.g. 1L, 5L, box)
```

Breadcrumbs on item/variant screens; create flows that **force** category before item, item before variant.

---

### D4 — Analytics

**Job:** *“What should I change this week?”*

**Above the fold:**

- Best performing item(s)
- Worst / risky item(s)
- Optional: supplier comparison (who delivers margin)

**Below:**

- Tables and charts as **proof**, not the main headline.

---

### D5 — AI

**Job:** *“Accelerate entry — not replace trust.”*

- Output = **structured draft** + short explanation.
- **Always** lands in the same entry + preview + save path.
- No separate “AI saved” story.

---

## Part E — Empty states (copy + action)

| Context | Headline direction | Primary CTA |
|---------|---------------------|-------------|
| No purchases in range | “No purchases in this period — add one to see profit here.” | Add purchase |
| No entries ever | “Add your first purchase to start tracking profit.” | Add purchase |
| Contacts empty | “Add suppliers and catalog so entries are faster.” | Add supplier / category |

**Avoid:** Generic “No data” with no next step.

---

## Part F — Premium UI system (non-negotiables)

| Layer | Rule |
|-------|------|
| **Color** | Primary: deep teal/blue; **Profit**: green; **Loss**: red; **Warning**: amber; background: soft grey / surface tiers |
| **Depth** | Cards: elevation or border; consistent **radius** (e.g. 16–24 for hero) |
| **Typography** | One display style for hero numbers; clear label vs value |
| **Spacing** | 4/8/12/16/24 scale; generous vertical rhythm on Overview |
| **Motion** | Subtle: hero number, insight cards (optional v1.5) |

**Avoid:** Flat white pages with equal-weight text blocks.

---

## Part G — Entity connection model (every entity earns its place)

For **Supplier, Broker, Item, Category, Variant**:

Each detail surface should offer:

1. **History** — entries / lines linked
2. **Analytics** — rollups (even if lightweight at MVP)
3. **Actions** — edit, add purchase with context pre-filled where possible

**If an entity has no link to entries,** the UI should say how it will be used soon — or hide until needed.

---

## Part H — What to remove or merge

| Remove / merge | Why |
|----------------|-----|
| Multiple “add entry” heroes on one screen | One mental model |
| Second confirmation step that feels like “save” twice | Trust + clarity |
| Duplicate navigation labels (title = tab name) | Reduces confusion |
| Raw technical IDs in user-facing forms | Use search/select |
| “Screens for screens’ sake” settings | Tie to journey |

---

## Part I — Success metrics (how we know it’s “premium”)

| Metric | Target direction |
|--------|-------------------|
| Time to first saved entry (new user) | Down |
| Taps to save after opening entry | Down |
| Support questions (“where do I…”) | Down |
| % sessions that reach Overview after entry | Up |
| Subjective: “feels like one product” | Qual / beta |

---

## Part J — Cursor / engineering handoff (one block)

Use this as the single prompt for phased implementation:

```text
Implement HEXA against docs/ux/premium-saas-blueprint.md.

Phase 1 — Journey + entry: default fast path (Item→Qty→Landing→Selling→Preview→Save); Advanced collapsed; single confirm; empty states from blueprint.

Phase 2 — Overview: hero + 3 insight slots + one primary CTA; reduce duplicate actions.

Phase 3 — Contacts: supplier/item cards with KPIs + links to filtered entries; category→item→variant enforced in navigation and copy.

Phase 4 — Analytics: headline insights + charts as supporting evidence.

Phase 5 — AI: draft → same entry pipeline only.

Phase 6 — Visual polish: color tokens, elevation, spacing per Part F.
```

---

## Closing line

**You built the engine. This blueprint is the chassis and the dashboard — so the owner feels guided from first open to every next purchase.**

---

## Implementation status (engineering)

| Phase | Status | Notes |
|-------|--------|--------|
| **Phase 1 — Journey + entry** | **In progress** | Flutter `EntryCreateSheet`: default path is date → line items → Preview / Save; optional fields live under **Supplier, catalog & extra costs** (collapsed). Preview dialog uses **Confirm & save**; sheet **Save** uses the same finalize path (no second confirmation sheet). Duplicate-entry 409 dialog unchanged. Overview empty state copy aligned (“this period”, first-purchase CTA). |
| Phase 2 — Overview | Partial | Hero + date chips + empty CTA; further deduping of actions TBD. |
| Phase 3 — Contacts | Not started | — |
| Phase 4 — Analytics | Not started | — |
| Phase 5 — AI | Not started | — |
| Phase 6 — Visual polish | Not started | — |

*End of blueprint.*
