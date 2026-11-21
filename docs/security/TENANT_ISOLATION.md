# Tenant isolation (one app, many client companies)

## How isolation works today
Every business route is `/v1/businesses/{business_id}/...`. The `require_membership` dependency loads the caller's membership
for that `business_id` and returns **403** if there is none; queries then filter by `business_id`. A user in company A who
sends company B's id in the path gets 403, and company B's record ids used inside company A's path get 404 or 400.
This is the **only** effective control; see the next section.

Verified by `backend/tests/test_tenant_isolation.py` (two independent companies, owner and staff accounts):
foreign business path (14 endpoints), unauthenticated and forged tokens, foreign record ids on read/update/delete,
search, staff of one company entering another, and 20+ write actions that take another record's id.

### Bug found and fixed by these tests
`POST` and `PUT /trade-purchases` accepted a **supplier, broker or catalog item belonging to another company**
(201 Created). Company B could attach company A's records to its own purchase and then commit stock against A's
catalog. `_collect_foreign_reference_errors` now rejects any id not owned by the caller's business (HTTP 422).

## PostgreSQL row-level security is NOT an effective control
Migration 054 enables RLS with policy `business_id = current_setting('app.current_business_id')` on 43 tables, but:
- the application never sets `app.current_business_id` (no `set_config` / `SET LOCAL` anywhere);
- RLS is not `FORCE`d, so the **table owner bypasses it**. The app connects as the owner (it ran the migrations).

Measured on PostgreSQL 16 with the migrated schema: table owner sees every row (2,674); a non-owner role with SELECT sees
**0 rows** until the variable is set, then only that business.

### Deployment trap (Windows Server plan)
If the API connects as a **non-owner** role (for example a least-privilege `hexa_app` while the tables are owned by
`postgres` after `pg_restore --no-owner`), every query returns **zero rows** and the API looks empty. Either:
1. make the API's role the **owner** of the tables (what production does today): restore with that role, or
   `REASSIGN OWNED BY postgres TO hexa_app`; or
2. implement RLS properly first: set `app.current_business_id` per request/transaction in `get_db`, `FORCE ROW LEVEL SECURITY`,
   connect as a non-owner role, and test with two tenants (this is real defense in depth, but it is a code change).

Do not combine a non-owner role with the current code.

## Not yet covered (follow-ups)
Exports/backup/restore endpoints across tenants, the AI agent / MCP tools (they take a business id), realtime SSE
streams, `public_items` token pages, notifications targeting, and per-role (manager vs staff) permission tests across
two companies.
