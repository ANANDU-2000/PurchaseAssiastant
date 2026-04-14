# HEXA — production security baseline

This document mirrors the **env-security-baseline** workstream: what must be true before production traffic.

## Environment

- **Single checklist**: root [`.env.example`](../.env.example) — remove unused keys from deployment secrets or load them explicitly in `Settings`.
- **`APP_ENV=production`**: `Settings.validate_production_safety()` runs at startup (JWT length/placeholder, `DEV_RETURN_OTP=false`).
- **`TRUSTED_HOSTS`**: set behind a reverse proxy so `TrustedHostMiddleware` can reject unknown `Host` headers.
- **`CORS_ORIGINS`**: explicit app + admin origins only (no `*` in production configs).

## Auth & sessions

- **JWT**: strong `JWT_SECRET` / `JWT_REFRESH_SECRET` (≥32 chars, not placeholders).
- **OTP**: `DEV_RETURN_OTP` / `DEV_OTP_CODE` only in local/dev; production uses `OTP_*` provider keys.
- **Rate limiting**: OTP requests per IP (`OTP_REQUESTS_PER_MINUTE_PER_IP`) enforced in auth router.
- **OTP storage**: Redis-backed store when `REDIS_URL` is set (`RedisOtpStore`); in-memory only acceptable for local dev.

## Data & migrations

- **Postgres**: `DATABASE_URL` with TLS in managed clouds.
- **Migrations**: prefer Alembic for production schema changes; see [migrations.md](migrations.md). Dev may use `create_all` for speed.

## Integrations

- **WhatsApp webhook (360dialog)**: HMAC verification when `DIALOG360_WEBHOOK_SECRET` is set; idempotent processing via message id in Redis.
- **WhatsApp webhook (Authkey)**: optional shared secret — when `AUTHKEY_WEBHOOK_SECRET` is set, inbound requests must send header `X-Authkey-Webhook-Secret` (or `X-Webhook-Secret`) with the same value.
- **Future webhooks** (Razorpay, etc.): verify signatures before mutating state.

## Observability

- **`SENTRY_DSN`**: optional error reporting (initialized in `main.py` when set).
- **`LOG_LEVEL`**: `INFO` or `WARNING` in production.

## Feature flags (backend)

- **`ENABLE_AI`**, **`ENABLE_OCR`**, **`ENABLE_VOICE`**, **`ENABLE_REALTIME`**: enforced on relevant routes — UI flags alone are not sufficient.

## Super admin

- Bootstrap via `SUPERADMIN_BOOTSTRAP_PHONE` for first admin; thereafter use DB role `is_super_admin`.
