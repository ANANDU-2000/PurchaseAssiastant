# Alembic revisions

Apply with `alembic upgrade head` against the same Postgres URL as the API (`DATABASE_URL`).

## Revision numbering

Revisions are named `NNN_short_description.py`. **026** and **027** are absent in git history (jumps from **025** → **028**). Do not renumber existing revisions on production without a coordinated deploy plan — document gaps only.

## Stock / purchase notes

- **037** — `stock_movements` idempotency: `UNIQUE (business_id, idempotency_key)` (no duplicate P1-015 index).
- **044** — `catalog_items.current_stock >= 0` CHECK; run on Render before API deploy when shipping stock engine rebuild.
