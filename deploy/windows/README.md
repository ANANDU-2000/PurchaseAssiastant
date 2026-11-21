# HEXA backend on Windows Server 2022: runbook

Target: FastAPI on `127.0.0.1:8000` + PostgreSQL on `127.0.0.1:5432`, published only through a Cloudflare Tunnel at
`https://api.harisreeagency.online`. Frontend stays on Vercel. Sized for about 20 users on 2 CPU cores / 8 GB RAM.

**Status: scripts are prepared and syntax-checked but have NOT been run on the server yet.** Nothing here has touched
production, DNS or data.

```
Internet -> Cloudflare -> Tunnel (cloudflared service) -> http://127.0.0.1:8000 (HexaApi service) -> PostgreSQL 127.0.0.1:5432
```

## Server layout
```
C:\hexa\
  releases\<12-char-sha>\{backend, venv}   one folder per deploy, last 3 kept
  current                                    junction to the live release
  config\{backend.env, pgpass.conf, cloudflared.token, rclone.conf}   secrets, SYSTEM+Administrators only
  backups\   logs\   tools\{nssm.exe, cloudflared.exe}
```

## Order of operations
Do not skip steps; steps 1-2 are owner actions outside this repo.

1. **Domain**: complete registrant contact verification at Namecheap, confirm `harisreeagency.online` resolves to
   proper nameservers (not `verify-contact-details` / `failed-whois-verification`). Add the zone to Cloudflare and,
   only with owner approval, change the nameservers.
2. **Install prerequisites on the server**: Python 3.12 (with `py` launcher), PostgreSQL (client tools + server),
   `nssm.exe` and `cloudflared.exe` into `C:\hexa\tools`.
3. **PostgreSQL**: create database `hexa`, an app role (`hexa_app`) and a backup role (`hexa_backup`, read-only). Keep
   `listen_addresses = 'localhost'`. Do not open port 5432 in the firewall.
4. `powershell -ExecutionPolicy Bypass -File deploy\windows\install-server.ps1` (elevated). It reports anything missing.
5. Fill `C:\hexa\config\backend.env` from `backend.env.template` (strong JWT secrets, real DB password, CORS origin).
   The API refuses to start in production with weak or "change-me" secrets.
6. **Data migration (owner approval required before the restore step)**
   1. From Render: `pg_dump -Fc` the production database to a file; record size and `alembic_version`.
   2. Restore into the new local `hexa` database with `pg_restore --no-owner`.
   3. Compare exact row counts per table between Render and local (the query in `restore-test.ps1` does this).
   4. `alembic current` must equal the repo head. Test the API against it before any DNS/Vercel change.
   5. Keep Render untouched and running until the new server has passed every check below.
7. **First deploy** (creates `current`): run `deploy-release.ps1 -SourceDir <repo checkout> -Sha <commit>`.
8. `install-cloudflared.ps1` after creating the tunnel in Cloudflare (public hostname `api.harisreeagency.online`
   -> `http://localhost:8000`) and saving its token to `C:\hexa\config\cloudflared.token`.
9. **Verify from outside**: `/health/ready` = 200 over the public hostname, then login, a purchase, a stock count,
   a report, SSE, the AI assistant, a backup and a restore dry-run.
10. **Switch the frontend** only after step 9: set `API_BASE_URL=https://api.harisreeagency.online` in the Vercel project
    and redeploy. Keep the old value noted so you can switch back.

## Automated deploys (GitHub Actions)
Workflow `deploy-backend-windows.yml` runs on the server through a self-hosted runner: backup -> migrate -> switch ->
health check -> automatic rollback. `rollback-backend-windows.yml` is the manual rollback.

Runner setup (once): GitHub repo > Settings > Actions > Runners > New self-hosted runner (Windows), add labels
`hexa-prod`, run it as a service. Then:
- Create the `production` Environment with **required reviewers** (you), so every deploy needs approval.
- Add repository variables `PUBLIC_API_URL` and, when everything above is ready, `ENABLE_WINDOWS_DEPLOY=true`
  (the workflows are inert until then, so merging them does nothing).
- **Make the repository private**, require approval for outside collaborators, and protect `main`.
- The workflows never run on `pull_request`. Do not add that trigger: the runner would execute untrusted code.
- The runner account must be able to manage services; treat the server as high value (separate admin account, MFA on
  GitHub, no browsing on that machine).

## Backups and restore
- `HexaBackupDaily` (02:30): `backup-postgres.ps1` dumps, verifies, checksums, prunes (14 days daily, 60 days Sundays,
  365 days first-of-month) and copies offsite if `HEXA_OFFSITE_REMOTE` + rclone are configured. **Offsite is not set up
  until you do that**; a single-server backup does not survive losing the server.
- Monthly: `restore-test.ps1` restores the newest dump into a scratch database and compares counts.
- Real restore (owner approval): stop `HexaApi`, `pg_restore --clean --if-exists -d hexa <dump>`, start the service,
  check `/health/ready`.

## Monitoring
`HexaMonitor` runs `health-monitor.ps1` every 5 minutes: API live/ready, services (API, tunnel, PostgreSQL), disk,
memory, backup age, PostgreSQL connections. Output: `C:\hexa\logs\health.jsonl`; set `HEXA_ALERT_WEBHOOK` for alerts.
Review measured usage after two weeks before deciding on any hardware upgrade.

## Known limits
- One uvicorn worker on purpose: rate limiting and SSE realtime are in-process until Redis is configured.
- Migrations are not auto-reverted on rollback; the pre-deploy dump is the safety net.
- Scripts were written without server access; expect to adjust paths (PostgreSQL `bin`, Python launcher) on first run.
