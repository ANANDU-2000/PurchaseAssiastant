# Deployment — HEXA Purchase Assistant

## Frontend (Vercel)

1. **Build:**
   ```
   cd flutter_app
   flutter build web --release
   ```
2. **Deploy:** Vercel project `purchase-assiastant` auto-deploys from `main` branch
   - Build command: `flutter build web --release`
   - Output directory: `flutter_app/build/web`
   - `vercel.json` in repo root configures SPA rewrites
3. **Env vars in Vercel:**
   - `API_BASE_URL` — the Render API URL (`https://my-purchases-api.onrender.com`)
4. **Hard refresh after deploy:** Ctrl+Shift+R to bust cached `main.dart.js`

## Backend (Render)

1. **Service:** `my-purchases-api` — Web Service connected to `main` branch
2. **Pre-deploy command:** `alembic upgrade head` (run from `backend/` rootDir)
3. **Runtime:** Python 3.11+, uvicorn
4. **Env vars in Render Dashboard:**
   - `DATABASE_URL` — internal Render Postgres URL
   - `JWT_SECRET`, `JWT_REFRESH_SECRET` — strong random values
   - `AI_PROVIDER` + matching API key (optional)
   - `SUPERADMIN_BOOTSTRAP_EMAIL` — first admin email
   - `CORS_ORIGINS` — must include the Vercel domain
   - `AUTO_MIGRATE=0`, `AUTO_STOCK_BACKFILL_ON_START=false`
5. **Health check:** `GET /health/ready` → 200 with `db: ok`, `schema_ok: true`

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
