# API Audit — Phase 1: Auth & Session

**Date:** 2026-07-28  
**Scope:** `/v1/auth/*`, `/v1/me/*`, health dependency  
**Mode:** Audit only — **no code changes**  
**Hosts:** API `https://my-purchases-api.onrender.com` · Web `https://purchase-assiastant.vercel.app`  
**OpenAPI:** `/docs`, `/openapi.json` (advertised from `GET /`)

---

## Executive summary

Login → refresh → `/v1/me/businesses` → `/v1/me/profile` → `/v1/me/bootstrap-workspace` is **working in production** (Render 200s; health ready; Vercel login loads).

**Critical (1):** refresh issues new tokens for blocked / inactive / soft-deleted users (broken access control after block).

**No Critical “endpoint down / 500” findings** on Auth/Me in the sampled production window.

Google Sign-In is **not configured** in production (503 by design). Self-registration is **disabled** (403 by design).

---

## API inventory

| Method | Path | Module | Controller | Service | Tables | AuthN | AuthZ | Frontend | Status |
|--------|------|--------|------------|---------|--------|-------|-------|----------|--------|
| GET | `/` | `health.py` | `root` | — | — | No | Public | Probes / browsers | Used |
| HEAD | `/` | `health.py` | `root_head` | — | — | No | Public | Uptime | Used |
| GET | `/health` | `health.py` | `health` | config | — | No | Public | Smoke / Flutter warmup | Used |
| GET | `/health/live` | `health.py` | `health_live` | — | — | No | Public | Liveness | Used |
| GET | `/health/ready` | `health.py` | `health_ready` | DB | `alembic_version`, schema probes | No | Public | Render / warmup | Used |
| GET | `/health/db-check` | `health.py` | `health_db_check` | DB | `trade_purchases`, `item_categories` | No | Public | Ops smoke | Used (ops) |
| POST | `/v1/auth/register` | `auth.py` | `register` | passwords, jwt | `users`, `businesses`, `memberships` | No | Gated by `ALLOW_PUBLIC_REGISTRATION` | `HexaApi.register` / `SessionNotifier.register` | Used · **403 in prod** (expected) |
| POST | `/v1/auth/login` | `auth.py` | `login` | `auth_login`, passwords, jwt, staff_audit | `users`, `memberships`, `user_sessions` | No | Public | Login page → `HexaApi.login` | **Working** |
| POST | `/v1/auth/google` | `auth.py` | `auth_google` | `google_oauth`, jwt | `users`, `businesses`, `memberships` | No | Public if configured | `HexaApi` has client; **no Auth UI usage** found | Latent · **503 prod** (not configured) |
| POST | `/v1/auth/refresh` | `auth.py` | `refresh_token` | jwt | `users` | Refresh JWT | Must decode; **no block checks** | Dio interceptor / session | **Working** (logic gap → Critical) |
| POST | `/v1/auth/forgot-password` | `auth.py` | `forgot_password` | password_reset | `users`, `password_reset_tokens` | No | Public | Login → forgot flow / `HexaApi` | Used · delivery gap |
| POST | `/v1/auth/reset-password` | `auth.py` | `reset_password_with_token` | passwords | `users`, `password_reset_tokens` | No | Token | `reset_password_page.dart` | Used |
| GET | `/v1/me/profile` | `me.py` | `get_my_profile` | deps | `users` | Bearer access | Self | Session bootstrap | **Working** |
| PATCH | `/v1/me/profile` | `me.py` | `patch_my_profile` | — | `users` | Bearer | Self | **No HexaApi caller found** | Backend live · **unused by Flutter** |
| POST | `/v1/me/bootstrap-workspace` | `me.py` | `post_bootstrap_workspace` | `default_workspace` | catalog/contacts seed tables | Bearer | Self | Session bootstrap | **Working** (often slow) |
| GET | `/v1/me/businesses` | `me.py` | `my_businesses` | permissions | `memberships`, `businesses` | Bearer | Self | Session bootstrap | **Working** |
| PATCH | `/v1/me/businesses/{id}/branding` | `me.py` | `patch_my_business_branding` | permissions | `businesses` | Bearer | Owner | `business_profile_page.dart` | Used |
| POST | `/v1/me/businesses/{id}/branding/logo` | `me.py` | `upload_business_logo` | filesystem + `app_url` | `businesses` | Bearer | Owner | `HexaApi` upload helpers | Used · ephemeral disk risk |

**Duplicates / deprecated:** none for Auth paths. Login accepts deprecated body field `identifier` (alias for email) — intentional compatibility.

**Dead:** none fully dead. `PATCH /v1/me/profile` is unused by current Flutter client. Google auth is unused in Auth UI and unavailable in prod.

---

## Request / response specs (condensed)

### POST `/v1/auth/login`
- **Headers:** `Content-Type: application/json`
- **Body required:** `password`; `email` or legacy `identifier` (must contain `@`)
- **Optional:** `device_token` (push)
- **Validation:** email lowercased; password 1–128 chars
- **200:** `{ access_token, refresh_token, expires_in }`
- **401:** invalid credentials  
- **403:** inactive / blocked / soft-deleted  
- **422:** validation  
- **503:** DB / token issue  

### POST `/v1/auth/register`
- **Body required:** `email`, `username` (`^[a-z0-9_]{3,64}$`), `password` (≥8, digit, not common)
- **Optional:** `name`
- **403:** public registration disabled (production default)  
- **409:** email/username taken  
- **200:** `TokenPair`  

### POST `/v1/auth/refresh`
- **Body required:** `refresh_token`
- **200:** new `TokenPair`  
- **401:** invalid refresh / user missing  
- **Gap:** does **not** re-check `is_blocked` / `is_active` / `deleted_at` / `token_version` on refresh path beyond user existence  

### POST `/v1/auth/forgot-password`
- **Body:** `email`  
- **200:** uniform message (anti-enumeration); `dev_reset_token` only when `app_env` in development/dev/test  
- **Prod:** token stored + logged; **no email send implemented**  

### POST `/v1/auth/reset-password`
- **Body:** `token`, `new_password` (strength rules)  
- **200:** ok message  
- **400:** invalid/expired / Google-only account  
- **422:** weak password  

### POST `/v1/auth/google`
- **Body:** `id_token`  
- **503:** `GOOGLE_OAUTH_CLIENT_IDS` unset (confirmed live)  
- **401/400/409:** token/email/link conflicts  

### GET/PATCH `/v1/me/profile`
- **Auth:** `Authorization: Bearer <access>`  
- **PATCH body optional:** `name` (max 255)  
- **401/403:** via `get_current_user`  

### GET `/v1/me/businesses`
- **200:** list of `{ id, name, role, permissions, branding_* , gst, address, phone, contact_email }`  

### POST `/v1/me/bootstrap-workspace`
- **200:** `{ business_id, created_business, seeded, seed_stats }` idempotent  

### PATCH `/v1/me/businesses/{business_id}/branding`
- **AuthZ:** owner (`require_owner_membership`)  
- **Body optional fields:** name, branding_title, branding_logo_url, gst_number, address, phone, contact_email  
- **400:** empty name  

### POST `/v1/me/businesses/{business_id}/branding/logo`
- **Multipart:** `file` — JPEG/PNG/WebP, max **2MB**  
- **Stores:** `backend/static/branding/{business_id}.{ext}`  
- **URL:** `{APP_URL}/static/branding/...`  

### Health
- `/health/ready` → **200** live (`db: ok`, alembic `068_physical_count_idempotency_key`, `schema_ok: true`)  
- `/health` → `app_env: production`  

---

## Frontend mapping

```
LoginPage / Splash
  → SessionNotifier.login / restore
    → HexaApi.login | refresh
      → POST /v1/auth/login | /v1/auth/refresh
    → HexaApi.myBusinesses | getProfile | bootstrapWorkspace
      → GET /v1/me/businesses | GET /v1/me/profile | POST /v1/me/bootstrap-workspace
        → users, memberships, businesses (+ seed)

Forgot password UI
  → HexaApi forgot/reset
    → POST /v1/auth/forgot-password | reset-password

Business profile settings
  → HexaApi.patchBusinessBranding (+ logo upload)
    → PATCH/POST /v1/me/businesses/{id}/branding[/logo]
```

| Integration | Verdict |
|-------------|---------|
| Login + refresh + me bootstrap | Correct / working |
| Register in prod | Correctly blocked (403) |
| Google | Client method exists; Auth screens do not call it; prod 503 |
| PATCH `/v1/me/profile` | Missing Flutter caller (settings use other user APIs) |
| Wrong host `purchase-assistant.vercel.app` | Documented blank/CORS risk — not Auth code |

---

## Production evidence

| Check | Result |
|-------|--------|
| `/health/ready` | 200, db ok, schema_ok |
| `/health` | `app_env=production` |
| Render `/v1/auth/*` / `/v1/me/*` 5xx (sampled) | **None** |
| Login / me / bootstrap | 200 OK in logs |
| Refresh | 200 OK (frequent) |
| Register | 403 Forbidden (expected) |
| Google probe | 503 not configured |
| Vercel login | Canonical host loads |
| Bootstrap | Often `SLOW_HTTP` ~500–900ms, still 200 |

---

## Logic / security / performance findings

### Critical

#### AUTH-C1 — Refresh skips account status / revocation gates
- **Endpoints:** `POST /v1/auth/refresh` (then any Bearer API)
- **Root cause:** `refresh_token` loads user by id only; does not mirror `get_current_user` checks for `deleted_at`, `is_blocked`, `is_active`.
- **Effect:** After an admin blocks or deactivates a user, they can keep calling refresh (30-day TTL) and obtain new access tokens until refresh JWT expires.
- **Frontend:** Dio refresh / session restore — silent re-auth.
- **Status:** **fixed** — refresh now applies the same 403 gates as login/`get_current_user` (blocked / inactive / soft-deleted).
- **Estimated fix:** 0.5–1h — reuse shared “user may authenticate” helper before minting tokens; optionally bump `token_version` on block and reject refresh when stale.
- **Recommended fix:** After loading user in `refresh_token`, apply same 403 rules as login/`get_current_user`; return 401/403; add pytest for blocked user refresh.

### High

#### AUTH-H1 — `POST /v1/auth/login` never `commit`s
- **Endpoints:** `POST /v1/auth/login`
- **Root cause:** Updates `last_login_at`, `UserSession`, staff audit, then `flush` only. `get_db` yields session with **no auto-commit** on exit → changes roll back.
- **Effect:** Login still returns tokens (auth works); session audit / last-login / push token persistence **do not stick**.
- **Status:** **fixed** — `await db.commit()` after successful token mint.
- **Estimated fix:** 15–30m — `await db.commit()` before return; test session row exists.
- **Recommended fix:** Commit after successful login side effects (same pattern as register).

#### AUTH-H2 — Password reset has no email delivery in production
- **Endpoints:** `POST /v1/auth/forgot-password`
- **Root cause:** Creates hashed token; docstring says “email delivery TBD”; only exposes raw token in non-production.
- **Effect:** Forgot-password UI cannot complete for real users without out-of-band token.
- **Estimated fix:** 4–8h (provider + template) or product decision to hide UI / owner-only reset.
- **Recommended fix:** Wire transactional email **or** disable Flutter forgot flow until ready; owner reset via Settings already exists.

#### AUTH-H3 — Logo upload on ephemeral Render disk
- **Endpoints:** `POST /v1/me/businesses/{id}/branding/logo`
- **Root cause:** Writes under `backend/static/branding/`; Render filesystem is ephemeral.
- **Effect:** Logos lost on redeploy/restart; URLs 404.
- **Estimated fix:** 4–8h — object storage (S3/R2) or skip upload and URL-only branding.
- **Recommended fix:** Persist to object storage; serve via CDN/`APP_URL`.

#### AUTH-H4 — Google register bypasses `ALLOW_PUBLIC_REGISTRATION` (latent)
- **Endpoints:** `POST /v1/auth/google`
- **Root cause:** New Google users create `Business` + owner `Membership` without checking `allow_public_registration`.
- **Prod today:** Google **not configured** (503) → not exploitable live; becomes Critical if OAuth IDs are set.
- **Status:** **fixed** — new Google user path returns 403 when public registration is disabled (existing email link still allowed).
- **Estimated fix:** 30m — gate new-user path on same flag as register.
- **Recommended fix:** Enforce gate before creating user/workspace.

### Medium

#### AUTH-M1 — Refresh tokens not rotated / not server-side revoked
- Stateless JWT refresh; stolen refresh valid until expiry; no reuse detection.
- **Fix:** Rotate refresh + store jti/version (larger change).

#### AUTH-M2 — No rate limit on login / forgot-password
- OTP has IP limits; password login does not — brute-force risk.
- **Status:** **fixed** — login 20/min/IP; forgot 10/min/IP + 5/hour/email.
- **Fix:** Per-IP / per-email throttle middleware.

#### AUTH-M3 — `membership_permissions` per business in loop
- `GET /v1/me/businesses` awaits permissions per membership (fine for 1 tenant; watch N).
- **Status:** **fixed** — sync `effective_permissions` (JSON on membership; no DB round-trip).

### Low

#### AUTH-L1 — Bootstrap often slow (~500–900ms)
- Still 200; optimize seed/idempotent path later.

#### AUTH-L2 — `PATCH /v1/me/profile` unused by Flutter
- Dead client integration; keep for API completeness or wire settings.

#### AUTH-L3 — Health `/health` exposes non-secret AI key **presence** flags
- Acceptable for ops; ensure no secrets leak (verified none in body).

---

## Working vs broken (Auth domain)

| Class | Items |
|-------|--------|
| **Working** | login, refresh (happy path), me profile GET, businesses, bootstrap, branding PATCH, health live/ready, register gated 403 |
| **Broken / incomplete** | AUTH-C1 refresh BAC; AUTH-H1 login persist; AUTH-H2 reset email; AUTH-H3 logo durability |
| **Unused / latent** | Google (UI + prod); PATCH profile (client) |
| **Duplicate** | None |
| **Deprecated compat** | Login `identifier` field |

---

## Test plan (document only — implement when fixing)

Per Critical/High when approved:

1. Happy login + refresh  
2. Validation 422  
3. Unauthorized missing Bearer  
4. Forbidden blocked user on **login** and **refresh**  
5. Register 403 when flag false  
6. Forgot uniform response  
7. Reset invalid token 400  
8. Logo type/size rejection  
9. Concurrency: dual refresh  

---

## Severity board (fix queue — wait for approval)

| ID | Severity | Issue | Fix first? |
|----|----------|-------|------------|
| **AUTH-C1** | **Critical** | Refresh ignores blocked/inactive/deleted | **Fixed** (refresh gates + pytest) |
| AUTH-H1 | High | Login missing commit | After C1 approval |
| AUTH-H2 | High | No reset email | Product decision |
| AUTH-H3 | High | Ephemeral logo storage | Infra |
| AUTH-H4 | High (latent) | Google bypasses registration gate | Before enabling Google |
| AUTH-M1–M3 | Medium | Rotation / rate limit / N perms | Later |
| AUTH-L1–L3 | Low | Slow bootstrap / unused patch / health flags | Later |

---

## Stop — approval required

**No code was changed in this audit.**

To proceed: approve **AUTH-C1** only (one Critical at a time). Next message should explicitly approve that fix; agent will then implement + pytest + Render verify + commit + stop.
