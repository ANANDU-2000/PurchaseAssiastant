# Harisree SaaS — bundle / resell + WhatsApp + AI (roadmap)

This document tracks **what exists**, **what was added**, and **recommended next builds** for a non-technical customer base that pays for WhatsApp + usage-based features.

## Already in the product (high level)

- **Mobile app**: entries, contacts, analytics, settings, optional local notifications.
- **Backend**: multi-tenant businesses, entries, catalog, contacts, **360dialog webhook** + outbound text, **feature flags** (e.g. `whatsapp_bot`), admin API.
- **Super admin**: can patch **feature flags**, view **integrations status**, and — **now** — update **API keys in the database** without redeploying the server.

## New: platform API keys without redeploy

- **Table**: `platform_integration` (singleton row `id=1`).
- **Admin API**:
  - `GET /v1/admin/platform-integration` — masked key tails + whether value comes from **database** vs **environment**.
  - `PUT /v1/admin/platform-integration` — set or update keys; **empty string** clears the DB override for that field (falls back to `.env` / host env).
- **Effective credentials**: outbound WhatsApp and webhook signature verification use **DB first**, then **Settings** (env).
- **Deprecated**: `POST /v1/admin/env-update` (points to PUT above).

**Security**: restrict admin to HTTPS + strong `ADMIN_API_TOKEN`; protect database backups; consider **encryption at rest** for `platform_integration` in a later phase.

## Business model you described (bundle / resell)

1. **Customer pays you** (monthly + optional usage) — implement via **Razorpay** subscriptions + `membership` / `plan` rows (partially stubbed in `.env.example`).
2. **Show pricing in-app**: base app vs **WhatsApp assistant add-on** vs **AI voice** — Flutter screens + server-side **entitlement checks**.
3. **360dialog / Meta**: you still pay **360dialog subscription + Meta conversation charges**; your customer price should **cover** that + margin + support.

## WhatsApp bot — current capabilities vs your full wish list

| Capability | Status |
|------------|--------|
| Inbound webhook, idempotency, link user by phone | Done |
| Queries: today, month, best supplier | Done |
| Draft purchase → **YES/NO** confirm → save entry | Done |
| Supplier/broker/category/item **create/edit/delete** purely via free-text WhatsApp | **Not done** — needs intent routing, validation, duplicate detection, confirmations |
| Voice notes → STT → same pipeline | **Not done** — needs STT provider + media download |
| “Intelligent” strict rules (no guessing) | Partially (confirm path); full LLM guardrails + structured extraction **next** |
| Per-tenant usage + cost | **Partial** — admin placeholders; needs usage logs |

## Suggested build order (next tasks)

1. **Entitlements**: `business` or `subscription` flags — `whatsapp_enabled`, `ai_enabled`, `voice_enabled`; enforce in webhook + AI routes.
2. **Billing UI**: Razorpay plan picker; show **estimated** Meta/360dialog **informational** costs (you maintain a small config table).
3. **WhatsApp intents v2**: map messages to commands (`ADD_SUPPLIER`, `ADD_ENTRY`, …) with **required fields** and **confirm** step; handle duplicates with **“already exists: X — reply MERGE or NEW”**.
4. **AI**: wire `effective_openai_key` (or Gemini) into `/ai/intent` with JSON schema + **refuse** if confidence low.
5. **Admin usage**: log each AI/WhatsApp action → **api_usage_logs** → real **cost estimates**.

## Where to put keys (operators)

| Method | When |
|--------|------|
| **`backend/.env`** (or host env) | Default for dev/staging; survives DB reset. |
| **`PUT /v1/admin/platform-integration`** | Production hot-swap without redeploy; stored in DB. |

Never commit real keys; rotate any key that was pasted in chat or tickets.
