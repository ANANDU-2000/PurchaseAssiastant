# Deployment — HEXA Purchase Assistant

## Frontend (Vercel)

1. Vercel project `purchase-assiastant` auto-deploys from `main` via `scripts/vercel-flutter-build.sh`.
2. `API_BASE_URL` = `https://my-purchases-api.onrender.com` (the build script also forces this if the env still holds the old tunnel host).
3. Hard refresh after deploy (Ctrl+Shift+R) to bust cached `main.dart.js`.

## Backend (Render, current production)

1. **Service:** Render web service `my-purchases-api` -> `https://my-purchases-api.onrender.com`
2. **DB:** Render Postgres `harisree_db` (Singapore), internal URL in `DATABASE_URL`.
3. **Migrations:** `AUTO_MIGRATE=1` runs `alembic upgrade head` on boot. `/health/ready` must show `schema_ok: true`.
4. **Health:** `GET /health/ready` -> 200.

## Backend (client Windows server, FUTURE)

Planned move to the client's own server (Windows Server, NSSM + Cloudflare Tunnel at `api.harisreeagency` .online). Not live. Do not point builds at it until it passes `/health/ready`.

## Database Migrations

```
cd backend
alembic upgrade head          # Apply pending
alembic current               # Check current head
alembic heads                 # List heads (should be one)
```

## CI/CD

| Workflow | Trigger | Action |
|----------|---------|--------|
| `db-backup.yml` | Weekly (Sunday) | `pg_dump` → GitHub Actions artifact, 90-day retention |
| `render-keepalive.yml` | Every 10 min | Pings `/health/ready` to prevent Render free-tier sleep |

## Rollback

1. **Frontend:** Vercel → Deployments → select previous deploy → ... → Promote to Production
2. **Backend:** Render → service → Manual Deploy → Deploy previous Docker image
3. **Database:** Restore from latest `db-backup` artifact → `pg_restore`
4. If JWT secrets change on rollback, all users must sign in again

## Production checklist (after every deploy)

- [ ] `GET /health/ready` → 200, `db: ok`, `alembic_version` matches repo head
- [ ] Sign in on desktop Chrome — no blank page
- [ ] Stock list loads — save a physical count — column updates immediately
- [ ] GitHub Actions → db-backup — last run within 7 days
- [ ] GitHub Actions → keep-alive — last run < 10 min
