# Super Admin Panel — Plan

## Purpose

Cross-tenant operations: health of the product, cost control, compliance with feature flags, and support diagnostics.

## Tech

- Web app under `admin_web/` (scaffold TBD: Vite + React + TS recommended).
- Same FastAPI backend with `super_admin` role guard on `/v1/admin/*`.

## Pages (Routes)

| Path | Function |
|------|----------|
| `/` | Overview — DAU, entries/day, error rate, estimated API burn |
| `/users` | Search users/businesses; suspend; impersonate read-only (optional) |
| `/subscriptions` | Plan distribution, MRR, failed payments |
| `/api-usage` | By provider: 360dialog, OpenAI, OCR, STT; cost estimates |
| `/feature-flags` | Global defaults + per-business overrides (AI, Voice, OCR) |
| `/logs` | Filter audit logs, webhook failures, job failures |
| `/integrations` | Webhook URL status, last ping, rotate secret workflow |
| `/settings` | Super admin profile, 2FA (future) |

## Data Sources

- `api_usage_logs`, `audit_logs`, `subscriptions`, `businesses`, aggregated metrics job.
- No raw user secrets; mask phone except last 4 when needed.

## Billing & Revenue

- Razorpay (or chosen provider) webhooks → update `subscriptions`.
- Admin shows revenue vs **estimated** COGS from `api_usage_logs.cost_estimate`.

## Feature Flags

- Keys: `ai_enabled`, `voice_enabled`, `ocr_enabled`.
- Resolution: business override → global default → env default.

## Observability Links

- Deep link to Sentry project, log viewer (e.g. CloudWatch/Datadog) from `/logs` help text.

## RBAC

- Only `super_admin` JWT can hit admin routes.
- Owner/staff JWT receives **403** on `/v1/admin/*`.

## Security

- Separate admin URL (`ADMIN_URL`); optional IP allowlist in production.
- All destructive actions through audited mutations.
