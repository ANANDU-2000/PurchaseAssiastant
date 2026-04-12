# Screen Map & UX — HEXA Purchase Assistant

> **Code-truth inventory (routes, tabs, buttons, flows):** see `**[user-flow-inventory.md](user-flow-inventory.md)`**.

## Navigation (Flutter — Owner / Staff)

Bottom navigation (**4 tabs**) + **Settings** via app bar actions (`AppSettingsAction` on most screens; AI tab has its own settings icon — **not** in the shell top strip):

1. **Home** — Dashboard
2. **Entries** — List + search + filters (+ entry to **Contacts**)
3. **AI** — Voice / intent chat
4. **Reports** — Analytics tabs

**Settings** — full-screen route `/settings` (not a tab). **Contacts** — `/contacts` from Entries or Settings.

Staff: same shell; hide or restrict destructive settings per RBAC.

---

## Home (Dashboard)


| Element       | Notes                                    |
| ------------- | ---------------------------------------- |
| Hero card     | Total profit (primary KPI)               |
| Secondary     | Total purchase, alerts (chips), top item |
| Quick actions | Add entry (1 tap), Voice, Scan bill      |
| Optional      | Swipeable insight cards                  |


**Goal:** ≤3 taps to start entry.

---

## Entries


| Screen                           | Content                                                                                                                 |
| -------------------------------- | ----------------------------------------------------------------------------------------------------------------------- |
| List                             | Search; filters: date, item, supplier; FAB add                                                                          |
| Entry form (modal / full screen) | Item, category, qty, unit, price, **landing (manual)**, selling, supplier, broker, commission, transport, date, invoice |
| Preview                          | Read-only summary before save                                                                                           |
| Duplicate modal                  | “Same item + qty + date — continue?”                                                                                    |
| Detail                           | Full row + edit history link                                                                                            |


**PIP:** Compact card when item + price context available (auto-expand or pinned top).

---

## Analytics


| Tab        | Content                                                      |
| ---------- | ------------------------------------------------------------ |
| Overview   | Totals: purchase, qty (base), profit, count + date filter    |
| Items      | Table: item, qty, avg price, landing, selling, profit, count |
| Categories | Profit, qty, best item per category                          |
| Suppliers  | Deals, avg price, qty, profit signal                         |
| Brokers    | Commission total, deals, impact                              |


**Charts:** Line (trend), Bar (compare), Pie (category share).  
**Filters:** Today, Yesterday, This week, This month, This year, Custom.

---

## Item Detail (Drill-down)

- Totals, avg cost, selling, profit per base unit  
- Line chart: price over time  
- Frequency; supplier breakdown  
- Link to full history

---

## Supplier Detail

- Deals, avg price, ledger-style list  
- Profit impact vs others  
- Compare action

---

## Broker Detail

- Deal count, commission total, impact on profit

---

## Contacts

- Tabs or segments: Suppliers | Brokers  
- CRUD minimal fields per PRD

---

## Settings

- Autofill on/off  
- Notifications  
- Default units / per-item conversions (where exposed)  
- Account / logout

---

## Super Admin (Web)


| Page          | Purpose                                         |
| ------------- | ----------------------------------------------- |
| Overview      | KPIs: users, revenue, cost, API health          |
| Users         | Tenants, roles, status                          |
| Subscriptions | Plans, MRR, churn                               |
| API usage     | By provider (360dialog, OpenAI, OCR, STT)       |
| Feature flags | Per tenant: AI, Voice, OCR                      |
| Logs          | Audit + error traces                            |
| Integrations  | Webhook status, keys metadata (not raw secrets) |
| Settings      | Super admin profile, bootstrap                  |


---

## Figma Workflow (Aligned with Skills)

1. **Discover** design system in target file (`search_design_system` or existing screens).
2. **Build** screens incrementally with `figma-use` + `figma-generate-design` — one major section per script; wrapper frame first.
3. **Rules** — After components stabilize, run `create_design_system_rules` and save `.cursor/rules/figma-design-system.mdc`.
4. **Code Connect** — After published components + code exist, map with `get_code_connect_suggestions` / `send_code_connect_mappings`.

**Screens to produce in Figma first:** Dashboard, Quick entry sheet, Entries list, Analytics overview, Item detail, Supplier detail, PIP card + expanded sheet, Super admin overview table.

---

## Retention / Platform Notes

- **iOS:** Generous tap targets, SF Pro–friendly scale, bottom sheets for quick entry.  
- **Android:** Material 3 motion; same information hierarchy.  
- **Web/Desktop:** Sidebar optional for analytics; tables wider.

Use design-system tokens for color/spacing — no hardcoded hex in specs.