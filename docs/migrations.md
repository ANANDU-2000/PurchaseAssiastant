# Database migrations (manual / Render / Supabase)

`Base.metadata.create_all` **does not** add columns to existing tables. The API includes **startup self-heal** in `backend/app/main.py` for common drift (e.g. `catalog_items.type_id`).

If production still errors on a missing column (e.g. deploy before self-heal ran), apply the SQL scripts in `backend/scripts/migrations/` in order:

1. `001_add_catalog_item_default_kg_per_bag.sql` (if needed)
2. `002_add_catalog_items_type_id.sql` — fixes `UndefinedColumnError: column catalog_items.type_id does not exist`
3. `003_add_ai_decision_engine_tables.sql` — adds `assistant_sessions`, `assistant_decisions`, `catalog_aliases`

Run against your Postgres connection (Supabase SQL editor or `psql`). Then redeploy or restart the Render service so ORM and DB match.

## Post-deploy checks (Render / Vercel)

1. **Render (API):** open the service **Logs** and confirm no `UndefinedColumnError: column catalog_items.type_id does not exist` after a fresh deploy. The app runs startup self-heal in `backend/app/main.py`; if logs still show the error, run `002_add_catalog_items_type_id.sql` manually, then restart.
2. **Health:** `GET /health` (or your health route) should return OK.
3. **Vercel (Flutter web):** ensure the web app’s API base URL matches the Render service URL and that CORS allows your Vercel domain in production (`CORS_ORIGINS`).
4. **Smoke:** open unified search (`/v1/businesses/{id}/search?q=...`) and catalog list; both should return 200 without 500s.
