# 10 — PERFORMANCE & COLD START

## C5 — Server “waking up” (Render / free tier)

**Client (done):** `flutter_app/lib/core/api/api_warmup.dart` — `pingHealth` calls `/health/ready` then `/health` with **5 attempts**, **12s** timeout per call, backoff between failures. `main.dart` shows a degraded banner while waiting.

**Session:** `startPeriodicHealth` pings every **5 minutes** while the app runs (tradeoff vs battery).

**Infra (ops):** Cold spins are inherent to free/sleepy tiers. Mitigations: paid instance, external cron hitting `/health`, or regional closer to users.
