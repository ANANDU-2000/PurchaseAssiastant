# HEXA Purchase Assistant — Master PRD (v1)

## 1. Vision

Build a **high-speed, intelligent purchase decision system** for business owners.

- **Input:** WhatsApp (primary) + Flutter app  
- **Output:** Clear decisions: profit, best supplier, risk signals

**Principle:** Fast input → clear data → smart decision.

---

## 2. Assumptions (Frozen for v1)


| Assumption   | Detail                                                                    |
| ------------ | ------------------------------------------------------------------------- |
| Landing cost | **Manual input** at entry time — not auto-calculated or guessed           |
| AI role      | **Parse and format only** — no business logic or guessing; ask if unclear |
| Backend      | FastAPI + PostgreSQL + Redis                                              |
| Clients      | Flutter (iOS, Android, Web, Desktop) + Super Admin web                    |


---

## 3. User Types


| Role                 | Description                                              |
| -------------------- | -------------------------------------------------------- |
| **Owner**            | Primary user; decisions; WhatsApp + app                  |
| **Staff** (optional) | Create/edit entries; limited settings                    |
| **Super Admin**      | Cross-tenant ops, cost, usage, APIs, logs, feature flags |


---

## 4. Goals

**User:** Entry < 5s where possible; clear profit; best supplier/risk visibility.  
**Business:** Daily usage, retention, paid conversion (₹499 / ₹999 / ₹1999 tiers — implementation Phase 4+).

---

## 5. Non-Goals (v1)

- Auto-deriving landing cost from market data  
- AI making purchase decisions without user confirmation  
- Full accounting / GST filing

---

## 6. Platforms

- **WhatsApp** via 360dialog (webhook in → API out)  
- **Flutter app** — bottom nav: Home, Entries, Analytics, Contacts, Settings

---

## 7. Core Modules

### 7.1 Home (Dashboard)

- Total purchase, total profit, alerts, top item  
- Actions: Quick entry, Voice entry, Scan bill

### 7.2 Quick Entry

- Single input → parse → auto-fill → **preview → confirm** (mandatory before save)

### 7.3 Entry (Full Form)

**Fields:** Item, category, qty, unit (kg / box / piece), price, **landing cost (manual)**, selling price, supplier, broker (optional), commission, transport, date, invoice no.

**Logic:** Profit = f(landing, selling, qty, units); duplicate detection (item + qty + date); missing-field prompts.

### 7.4 Units

- Supported: **KG, Box, Piece**  
- Store base unit per item; conversions (e.g. 1 box = N kg) for comparison and analytics

### 7.5 Analytics & Reports

- Overview: total purchase, qty (normalized), profit, purchase count  
- Item table; category; supplier; broker  
- Charts: line (trend), bar (comparison), pie (distribution)  
- Date filters: Today, Yesterday, Week, Month, Year, Custom

### 7.6 Price Intelligence Panel (PIP)

- Trigger: item selected / price typed / WhatsApp query  
- Show: avg, high, low, trend, % position on range; history; supplier comparison; profit view when selling price present  
- Backend: pre-aggregated or cached; rules in code, not in LLM

### 7.7 WhatsApp

- Entry, query, update, alerts — same preview/confirm pattern

### 7.8 Voice / OCR (Phase 4 in delivery plan)

- Voice: STT → parse → confirm  
- OCR: upload → extract → structure → validate → confirm

### 7.9 Security

- OTP + phone identity; JWT; rate limits; encryption at rest for secrets

### 7.10 Duplicate Control

- Match: same item + qty + date → prompt: “Duplicate — continue?”

### 7.11 Super Admin (Separate Surface)

- Users, revenue, cost, API usage, logs, feature flags (AI / Voice / OCR)

---

## 8. Risks & Mitigations


| Risk            | Mitigation                    |
| --------------- | ----------------------------- |
| Wrong entry     | Preview + confirm; validation |
| Duplicate       | Detection + user confirm      |
| AI error        | Parse-only; backend validates |
| Voice/OCR noise | Low confidence → re-ask       |


---

## 9. Success Metrics (Product)

- DAU, entries/day, queries/day, p95 API latency, error rate

---

## 10. Document Map

- Architecture: `docs/architecture.md`  
- Data model: `docs/data-model.md`  
- APIs: `docs/api/openapi.yaml`  
- UX / Figma: `docs/ux/screen-map.md`, `docs/ux/whatsapp-flows.md`  
- Ops: `docs/ops.md`  
- Phases: `docs/delivery-phases.md`