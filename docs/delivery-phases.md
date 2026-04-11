# Delivery Phases — HEXA Purchase Assistant

## Phase 1 — Core MVP

**Scope**

- OTP auth + JWT; business + membership.
- Flutter shell: bottom nav, theme, routing.
- Entry: full form + **manual landing cost** + selling price; profit preview; confirm save.
- Entries list + search + date filter.
- Home dashboard: totals + top item (simplified).
- Suppliers CRUD minimal.
- Duplicate check: item + qty + date → confirm modal.

**Backend**

- FastAPI skeleton; PostgreSQL schema for core tables; Redis optional for Phase 1.
- REST: auth, entries CRUD, basic analytics summary.

**Testing**

- API: pytest for auth + entry validation + duplicate rule.
- Flutter: widget tests for form validation.

**Rollout**

- Internal dogfood; 1–3 pilot businesses.

---

## Phase 2 — Insights & PIP

**Scope**

- Analytics tabs: overview, items, categories, suppliers, brokers.
- Charts: line, bar, pie.
- Date filters: today → custom.
- Item detail drill-down; PIP card + expanded history.
- Unit normalization + `item_unit_conversions`.

**Backend**

- Aggregates jobs or materialized queries; `price_history`; PIP endpoint with caching.

**Testing**

- Golden datasets for analytics parity; API contract tests vs OpenAPI.

**Rollout**

- Staging load test on analytics endpoints.

---

## Phase 3 — WhatsApp + AI Parse

**Scope**

- 360dialog webhook; conversation state in Redis.
- `entries/parse` AI draft only; same preview/confirm as app.
- Admin: API usage logs, basic dashboard.

**Testing**

- Webhook signature tests; idempotency; malformed payload handling.

**Rollout**

- Sandbox numbers first; monitor `api_usage_logs`.

---

## Phase 4 — Media, Realtime, Billing

**Scope**

- Voice upload → STT → parse flow.
- OCR upload → structure → confirm.
- WebSocket/SSE for live dashboard updates.
- Razorpay subscriptions; feature flags per tenant.
- Super admin panel full (users, revenue, logs, flags).

**Testing**

- E2E with sample invoices/audio; chaos test Redis failure.

**Rollout**

- Gradual flag enablement for OCR/voice per business.

---

## Exit Criteria (Global)

| Metric | Target |
|--------|--------|
| Entry create p95 | &lt; 300ms API |
| Dashboard load (cached) | &lt; 1s perceived |
| WhatsApp reply (simple) | &lt; 2s |
| Error rate | &lt; 0.5% 5xx |

---

## Document Index

- PRD: `docs/master-prd.md`
- Phases (this file): `docs/delivery-phases.md`
