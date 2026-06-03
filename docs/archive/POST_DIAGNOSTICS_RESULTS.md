# POST / database diagnostics (2026-06-03)

## Live stack

| Layer | Target | Status |
|-------|--------|--------|
| Web | https://purchase-assiastant.vercel.app | `API_BASE_URL` → Render API (in deployed `main.dart.js`) |
| API | https://my-purchases-api.onrender.com | `GET /health/ready` → `db: ok`, alembic `056_purchase_damage_reports` |
| Database | Render Postgres `harisree-db` (`dpg-d8fu1p77f7vs73eooiu0-a`) | Migration complete; not Supabase live |
| Supabase | `xrkwlixlntujkhsaepbh` | Legacy copy (~2776 catalog items); API does **not** write here |

## POST shows "Failed" (no status)

Most likely **Render cold start** (30–90s idle). Mitigations applied in repo:

- [`api_warmup.dart`](../flutter_app/lib/core/api/api_warmup.dart): longer retries + `/health/ready` before traffic
- [`main.dart`](../flutter_app/lib/main.dart): banner *"Waking up server (can take up to a minute…)"*

**You should still:** open https://my-purchases-api.onrender.com/health/ready in a tab, then **Ctrl+Shift+R** on the PWA and re-login if needed.

## CORS

[`backend/app/main.py`](../backend/app/main.py) appends `https://purchase-assiastant.vercel.app` in production even if `CORS_ORIGINS` omits it. No CORS change required unless you use a **different** Vercel hostname.

## Catalog unit bug (ULUVA 30 KG)

Row was `default_unit=kg` + `package_type=SACK` + `default_kg_per_bag=30` → purchase blocked bags.

Fixed on Render via [`backend/scripts/fix_misconfigured_bag_units.py`](../backend/scripts/fix_misconfigured_bag_units.py):

- `ULUVA 30 KG` → `default_unit=bag`, `default_kg_per_bag=30`
- `THUVARA KING 50KG` → `default_unit=bag`, `default_kg_per_bag=50`

Re-run script anytime: `cd backend && python scripts/fix_misconfigured_bag_units.py`

## Deploy reminder

Local fixes (item create, stock 409 retry, warmup) are **not on Vercel** until you `git push` and Vercel rebuilds. `my-purchases-api` has `autoDeploy: no` — deploy API from Render Dashboard after backend changes.

## Render MCP

Workspace: **My Workspace** (`tea-ctr63al2ng1s73ersr5g`). Service: `my-purchases-api` (`srv-d7ea0il8nd3s73e4fvl0`). Postgres: `harisree-db` (`dpg-d8fu1p77f7vs73eooiu0-a`).
