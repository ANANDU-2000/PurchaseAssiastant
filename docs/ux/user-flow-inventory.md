# HEXA Flutter app — User flow inventory (current code)

**Purpose:** Single reference for **routes**, **shell**, **tabs**, **buttons**, **inputs**, and **primary flows** — for audits and QA.  
**Source:** `flutter_app/lib/core/router/app_router.dart` + feature `presentation/` screens (as implemented).

**Global rules (auth):** Unauthenticated users are redirected to **`/login`** except **`/splash`**. Logged-in users hitting **`/splash`** or **`/login`** redirect to **`/home`**.

---

## Route index (all top-level paths)

| Path | Screen | In bottom shell? |
|------|--------|------------------|
| `/splash` | Splash (session restore) | No |
| `/login` | Login / Register | No |
| `/home` | Dashboard | Yes — tab **Home** |
| `/entries` | Entries list | Yes — tab **Entries** |
| `/ai` | Voice / AI chat | Yes — tab **AI** |
| `/analytics` | Reports | Yes — tab **Reports** |
| `/settings` | Settings (full screen) | No — **AppBar** gear (`AppSettingsAction`) on Home / Entries / Reports / Contacts; AI tab has its own settings icon |
| `/catalog` | Item catalog | No — pushed from Home / Settings |
| `/contacts` | Contacts hub | No — pushed from Entries **people** icon / Settings |
| `/entry/:entryId` | Entry detail | No |
| `/supplier/:supplierId` | Supplier detail | No |
| `/broker/:brokerId` | Broker detail | No |
| `/contacts/category?name=` | Items in category | No |
| `/item-analytics/:itemKey` | Item analytics drill-down | No |

---

## Shell layout (logged-in main app)

**File:** `features/shell/shell_screen.dart`

| Zone | Content |
|------|---------|
| **Top strip** | HEXA hub icon + title · **Entries** shortcut (`TextButton` → switches to Entries tab) — **no Settings** here |
| **Body** | Current shell tab (IndexedStack) |
| **FAB** | **+** → opens **Purchase entry** bottom sheet (`showEntryCreateSheet`) |
| **Bottom `NavigationBar`** (4 items) | **Home** · **Entries** · **AI** · **Reports** |

**No Settings tab** — Settings is via **AppSettingsAction** on supported screens (and the AI tab’s settings `IconButton`), not from the shell strip.

---

## 1. Splash (`/splash`)

| Element | Action / output |
|---------|-----------------|
| Auto boot | `session.restore()` → if session OK → **`/home`** |
| Tokens but no session | Error + **Retry** |
| No tokens | **`/login`** |

---

## 2. Login (`/login`)

**File:** `features/auth/presentation/login_page.dart`  
**Layout:** `SafeArea` → header → **`TabBar`** (2 tabs) → content.

### Tabs (sub-pages)

| Tab | Inputs | Primary actions |
|-----|--------|-------------------|
| **Sign in** | Email, Password | **Sign in** → API login → **`/home`** |
| **Create account** | Username, Email, Password, Confirm password | **Create account** → register → **`/home`** |

### Other controls

| Control | Action |
|---------|--------|
| **Continue with Google** (if `GOOGLE_OAUTH_CLIENT_ID` set) | Google sign-in → **`/home`** |
| Error text | Generic message + `AppConfig.apiBaseUrl` hint |

---

## 3. Home — Dashboard (`/home`)

**File:** `features/home/presentation/home_page.dart`  
**Scaffold:** `AppBar` — Refresh · **AppSettingsAction** (`/settings`).

### Period filter (horizontal **ChoiceChips`)

Chips from `DashboardPeriod` (e.g. week / month / MTD — see `dashboard_period_provider`).

### Content sections (top → bottom)

1. **Decision snapshot** + date range caption  
2. **`_HeroProfitCard`** — total profit + optional % vs prior MTD  
3. **Metric rows** — Purchase, Profit, Margin, Purchases count, Qty base, Avg/purchase (cards)  
4. **Insights & alerts** (when `homeInsightsProvider` has data) — loss lines, top item, needs attention, best supplier, alert cards  
5. **Quick actions** (`_QuickActions`)

### Quick actions — buttons / clicks

| UI | Navigates / opens |
|----|---------------------|
| **Add entry** (primary gradient) | `showEntryCreateSheet(context)` |
| **Voice** chip | `context.go('/ai')` |
| **Scan bill** chip | OCR snack (API preview) |
| **Reports** chip | `context.go('/analytics')` |
| **History** chip | `context.go('/entries')` |
| **Catalog** chip | `context.push('/catalog')` |

**Pull to refresh:** invalidates dashboard + home insights.

---

## 4. Entries (`/entries`)

**File:** `features/entries/presentation/entries_page.dart`  
**AppBar actions:** **People** (`/contacts`) · Dashboard (`/home`) · **Settings** · **Filters** (badge) · **Refresh** · **Advanced search**

### Main controls

| Control | Behavior |
|---------|----------|
| **SearchBar** | Filters list by `entrySearchQueryProvider` |
| **List tiles** | Tap → **`/entry/:entryId`** |
| **Filters** (modal) | From / To date, supplier → Apply |
| **Advanced search** (dialog) | Item name contains |

### FAB / add

Shell **+** FAB opens entry sheet (same as Home).

---

## 5. Purchase entry (modal bottom sheet)

**File:** `features/entries/presentation/entry_create_sheet.dart`  
**Opened from:** Shell **+** (any tab).

### Structure

- `DraggableScrollableSheet` + `ListView` · bottom **live totals** bar (cost / kg / revenue / profit)  
- **`SwitchListTile` — Advanced costs** — off = simple landed path; on = invoice, commission, transport, commission mode **`SegmentedButton`** (₹ Total / % / ₹ per unit)

### Sections (approximate order)

| Section | Inputs / controls |
|---------|-------------------|
| Title | “Smart purchase entry” |
| Advanced toggle | As above |
| **ExpansionTile** “Masters & quick-create” | Chips: Supplier, Broker, Category, Item, Variant, **Contacts hub** |
| **Quick line** | TextField + parse chip / downward to line 1 |
| **Entry date** | ListTile → date picker |
| **Supplier** | Dropdown |
| **Broker** | Dropdown + add broker icon |
| **If Advanced** | Invoice no., Commission, SegmentedButton modes, Transport ₹ |
| **Line items** | Repeat `_lineCard` |

### Per line (`_lineCard`)

| Field | Notes |
|-------|--------|
| Item * | Text + variant + catalog pickers |
| Category | Text |
| Qty * · Unit | kg / Bag / box / pc |
| If Bag | Kg per bag + quick chips 25/50 |
| Purchase / Landed | Label depends on Advanced |
| Landed readout OR one-line summary | Advanced vs simple |
| If Advanced | SmartPricePanel landing |
| Selling | Per unit or per kg for bags |
| SmartPricePanel selling | |
| Profit row | Estimate |

### Footer actions

| Button | Action |
|--------|--------|
| **Preview** | POST entry `confirm:false` → `preview_token` |
| **Save** | Enabled when preview token set → confirm sheet → POST `confirm:true` |
| Duplicate flows | `check-duplicate` / 409 → dialogs **Continue anyway** with `force_duplicate` |

---

## 6. Entry detail (`/entry/:entryId`)

**File:** `features/entries/presentation/entry_detail_page.dart`  
**Purpose:** Read purchase lines, totals, navigate back. (See file for exact AppBar actions.)

---

## 7. AI / Voice (`/ai`)

**File:** `features/voice/presentation/voice_page.dart`

### Main controls

| Control | Behavior |
|---------|----------|
| Chat list | User + assistant bubbles |
| **Text field** | Type intent → `_sendText` → `ai/intent` API |
| **Tap to speak** / mic | Short session → voice preview pipeline (when enabled) |
| **Settings** link | `context.go('/settings')` (if present in UI) |

**Product rule:** Push-to-talk only; preview in chat; **no auto-save** — copy directs to Entries for save.

---

## 8. Reports / Analytics (`/analytics`)

**File:** `features/analytics/presentation/analytics_page.dart`  
**AppBar:** Title **Reports** · **AppSettingsAction** · **`TabBar`** (5 tabs, scrollable)

### Sub-tabs (`TabBar` → `TabBarView`)

| # | Tab | Content |
|---|-----|---------|
| 1 | **Overview** | KPIs + charts (`_OverviewTab`) |
| 2 | **Items** | Sortable table (`_ItemsTab`) |
| 3 | **Categories** | (`_CategoriesTab`) |
| 4 | **Suppliers** | (`_SuppliersTab`) |
| 5 | **Brokers** | (`_BrokersTab`) |

### Date controls (above tabs)

| Control | Behavior |
|---------|----------|
| **From** / **To** | `OutlinedButton` → date pickers → invalidates KPI + tables |
| **Chips** | Today, Yesterday, This week, This month, This year, Last 7 days |

---

## 9. Settings (`/settings`)

**File:** `features/settings/presentation/settings_page.dart`  
**AppBar:** Back → pop or **`/home`**

### Sections (vertical list)

| Section | Tiles / controls |
|---------|------------------|
| **Workspace** | Business name + role (read-only) |
| **Preferences** | Smart autofill **Switch** · Notifications **Switch** |
| **Voice & AI** | Info tiles (push-to-talk, confirm before save) |
| **Data** | **Suppliers & brokers** → `push /contacts` · **Item catalog** → `push /catalog` · Units (info) |
| **Sign out** | Logout → **`/login`** |

---

## 10. Contacts hub (`/contacts`)

**File:** `features/contacts/presentation/contacts_page.dart`  
**AppBar:** Search field · **AppSettingsAction** · **Refresh** (typical)

### Sub-tabs (4)

| Tab | List content | Row actions (typical) |
|-----|--------------|------------------------|
| **Suppliers** | Cards / list | Tap → `/supplier/:id` · phone **dial** if present |
| **Brokers** | List | Tap → `/broker/:id` |
| **Categories** | List | Tap category → `/contacts/category?name=` |
| **Items** | Catalog items | Tap → item flows |

**Search:** Debounced (`_searchMinLen` = 2 chars) filters in-tab content.

**FAB:** Context-dependent add (supplier / broker / category / item — see implementation).

---

## 11. Supplier detail (`/supplier/:supplierId`)

**File:** `features/contacts/presentation/supplier_detail_page.dart`  
**Content:** Supplier fields, broker link, metrics, related actions (see file).

---

## 12. Broker detail (`/broker/:brokerId`)

**File:** `features/contacts/presentation/broker_detail_page.dart`

---

## 13. Category items (`/contacts/category?name=`)

**File:** `features/contacts/presentation/category_items_page.dart`  
Lists items in named category.

---

## 14. Item catalog (`/catalog`)

**File:** `features/catalog/presentation/catalog_page.dart`  
**AppBar:** Back · title **Item catalog** · **`TabBar`** (2 tabs)

| Tab | FAB |
|-----|-----|
| **Categories** | **+ Category** |
| **Items** | **+ Item** |

---

## 15. Item analytics detail (`/item-analytics/:itemKey`)

**File:** `features/analytics/presentation/item_analytics_detail_page.dart`  
Drill-down for one item name (encoded in path).

---

## Cross-cutting navigation map

```text
                    ┌─────────────┐
                    │   /splash   │
                    └──────┬──────┘
                           │
              ┌────────────┴────────────┐
              ▼                         ▼
        ┌──────────┐            ┌──────────┐
        │  /login  │            │  /home   │◄── shell tab Home
        └────┬─────┘            └────┬─────┘
             │                     │
             └──────────┬──────────┘
                        │
        ┌───────────────┼───────────────┐
        ▼               ▼               ▼
   /entries        /ai            /analytics
   /contacts       /settings       /catalog
   /entry/:id      /supplier/:id
                   /broker/:id
                   /contacts/category
                   /item-analytics/:key
```

---

## WhatsApp / backend-only flows

Inbound WhatsApp parsing and webhooks are **not** separate Flutter screens; they follow the same **preview → confirm** rules on the server. Mention in product docs, not in this widget tree.

---

## Related docs

- `docs/ux/audit-workflow.md` — how to audit page-by-page  
- `docs/ux/screen-map.md` — older high-level map (may drift; **this file** is code-truth for navigation)

---

*Generated from codebase structure; update when routes or major widgets change.*
