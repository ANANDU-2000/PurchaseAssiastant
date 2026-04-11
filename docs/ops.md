# Operations — HEXA Purchase Assistant

## Environments

| Env | Purpose |
|-----|---------|
| `development` | Local API + local DB |
| `staging` | Pre-prod, real-like webhooks in sandbox |
| `production` | Live users |

## Secrets

- Store in **cloud secret manager** or encrypted CI vars.
- Rotate: JWT secrets, webhook secrets, API keys — documented in runbook.
- Never log request bodies containing OTP or tokens.

## Rate Limits

- **OTP request:** e.g. 3/hour per phone + IP throttle.
- **API:** per user / per business — e.g. 1000 req/hour default.
- **WhatsApp outbound:** respect 360dialog and Meta policies; queue bursts.

## Webhooks

- Verify `DIALOG360_WEBHOOK_SECRET` (or provider-specific HMAC).
- **Idempotent** processing on provider message id.
- Retry outbound on 5xx with exponential backoff; dead-letter queue after N tries.

## Database

- Backups: daily full + PITR if cloud Postgres.
- Migrations: Alembic (or equivalent) — no manual DDL in prod.

## Redis

- Persistence optional; treat as cache — sessions can rebuild from DB.

## Monitoring

- **Sentry** for API and Flutter.
- **Uptime** on `/health` and webhook endpoint.
- Alerts: error rate &gt; 1%, p95 latency &gt; 500ms, queue depth.

## Incident Response

1. Identify scope (API vs WhatsApp vs provider).
2. Toggle feature flags (`ENABLE_AI`, etc.) if AI provider outage.
3. Communicate on status page / in-app banner if prolonged.

## Compliance

- Data residency: document region for DB and object storage.
- User deletion: anonymize phone + cascade business data per policy.
