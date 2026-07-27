# Verification gates — purchase system rebuild

## Backend

- [ ] `GET /health` returns `200`.
- [ ] `GET /openapi.json` lists `/trade-purchases` and `/reports/trade-summary`.
- [ ] Authenticated `GET /v1/businesses/{id}/trade-purchases` returns `200` (empty list OK).
- [ ] `PUT /v1/businesses/{id}/trade-purchases/draft` then `GET` round-trip returns same `step` + `payload`.
- [ ] `POST` create with one line returns `201` and `human_id` matching `PUR-YYYY-NNNN`.
- [ ] Duplicate `POST /check-duplicate` returns `duplicate: true` when reusing same payload.
- [ ] `alembic upgrade head` (when using Alembic) or cold start `create_all` creates `trade_purchases` tables without error.

## Flutter (mobile + web)

- [ ] Shell shows five tabs: Home, Purchase, Reports, Contacts, Assistant.
- [ ] Purchase tab lists trade purchases (or empty state) without nested scroll warnings.
- [ ] `/purchase/new` wizard: single scroll body, fixed bottom CTA, back shows “Save draft?” when dirty.
- [ ] Save completes and returns to purchase list; pull-to-refresh or reopen shows new row.
- [ ] Offline banner still appears; draft PUT retries when back online (manual smoke).

## Assistant (unchanged backend)

- [ ] `/assistant` still loads; AI chat requests unchanged.
- [ ] No regression on preview → confirm flows that still target legacy entries until explicitly rewired.

## Data safety

- [ ] No destructive migration on existing `entries` / `entry_line_items`.
- [ ] Supplier/broker PATCH accepts new optional wholesale fields without breaking older clients.
