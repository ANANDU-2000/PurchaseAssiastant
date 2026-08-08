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
   - `API_BASE_URL` — Cloudflare Tunnel API (`https://api.harisreeagency.online`)
4. **Hard refresh after deploy:** Ctrl+Shift+R to bust cached `main.dart.js`

## Backend (Windows Server + Cloudflare Tunnel)

1. **Public URL:** `https://api.harisreeagency.online` → `http://localhost:8000` via cloudflared
2. **Service:** NSSM `PurchaseAssistantAPI` on the Windows Server
3. **Deploy:** `git pull origin main` then `nssm restart PurchaseAssistantAPI`
4. **Env vars:** in `backend/.env` on the server (Postgres local, CORS includes Vercel domain)
5. **Health check:** `GET /health` and `GET /health/ready` → 200

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
