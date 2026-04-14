# WhatsApp on production (Render + Authkey + Supabase)

## Where the webhook URL comes from (read this first)

You **do not** copy the webhook URL from Authkey, Vercel, or Supabase. You **construct** it:

`https://` + **your Render backend hostname** + `/v1/webhooks/whatsapp/authkey`

Example: if Render shows `https://my-purchases-api.onrender.com`, then the webhook URL is:

`https://my-purchases-api.onrender.com/v1/webhooks/whatsapp/authkey`

Rules:

- Must start with `https://`
- Must be the **public API** (Render service URL), not the Flutter/Vercel site
- Must include the full path `/v1/webhooks/whatsapp/authkey`
- Method **POST**, body **JSON** (fields like `mobile`, `message`), as configured in Authkey

After saving in Authkey, send `Hi` from WhatsApp and confirm **Render logs** show `POST /v1/webhooks/whatsapp/authkey`.

This backend needs **two directions** working:

1. **Outbound** (API → WhatsApp user): `AUTHKEY_API_KEY` and sender fields so `send_text_message` can reach Authkey.
2. **Inbound** (user → API): Authkey dashboard **webhook URL** must point at your **API host**, not Vercel.

## URLs

| Item | Value |
|------|--------|
| API base | Your Render service URL, e.g. `https://your-api.onrender.com` |
| Webhook | `POST https://YOUR_API_HOST/v1/webhooks/whatsapp/authkey` |
| Health | `GET https://YOUR_API_HOST/health` — returns `status`, `ai_provider`, `whatsapp_outbound_authkey`, `redis_url_set`, `webhook_max_per_minute`, etc. |
| Flutter web | Hosted on Vercel; build with `API_BASE_URL` = same API host as above. |

## Authkey dashboard

1. Set **Webhook / callback URL** to `/v1/webhooks/whatsapp/authkey` on the API host.
2. Payload should include `mobile` (or `from`) and `message` (or `text` / `body`).
3. Optional: configure Authkey to send header `X-Authkey-Webhook-Secret` matching `AUTHKEY_WEBHOOK_SECRET` on the API.

## Environment (Render)

Minimum for WhatsApp:

- `AUTHKEY_API_KEY`
- `AUTHKEY_FROM_NUMBER` (or as required by Authkey)
- `APP_URL` = public API URL
- `DATABASE_URL` or `DATABASE_POOLER_URL` for Supabase from Render (see `.env.example`)

AI (optional but recommended for parsing + optional reply polish):

- `AI_PROVIDER=openai` | `groq` | `gemini` + matching API key
- `WHATSAPP_LLM_REPLY=true` — LLM rephrases **query** reports only
- `WHATSAPP_LLM_AGENT=true` — also polishes previews, confirmations, clarify/help (higher cost)

## Redis

For **multiple Render instances**, set `REDIS_URL` so webhook **idempotency** and rate limits are consistent. Single instance can run with Redis unset (see release notes in code).

## Vercel (Flutter web)

- Set `API_BASE_URL` to your Render API URL at build time.
- Backend `CORS_ORIGINS` must include your Vercel origin in production.

## Verification

1. `GET /health` — 200 and `whatsapp_outbound_authkey: true` if Authkey key is set.
2. Send a WhatsApp message; check Render logs for `whatsapp_authkey` and `whatsapp_outbound` lines (phone shown as last 4 digits only).

## Behaviour (agent safety)

- **Rules first, LLM second:** When regex/rules match with high confidence (see `RULES_SKIP_LLM_MIN_CONFIDENCE` in `whatsapp_transaction_engine.py`), the transactional LLM parse is **skipped** to save cost and reduce drift.
- **Strict prompts:** All WhatsApp LLM calls use `STRICT_WHATSAPP_LLM_PREFIX` — no guessing numbers; server validates purchases.
- **Purchase validation:** `build_entry_create_request` requires positive qty and strictly positive buy/landing prices before preview.
- **Duplicates:** `entry_create_pipeline.find_duplicates` + WhatsApp `duplicate_pending` / `YES FORCE` flow.
- **Rate limits:** Authkey inbound webhook is limited per phone (defaults **20 / minute** and **120 / hour**, configurable via `WEBHOOK_MAX_PER_MINUTE` / `WEBHOOK_MAX_PER_HOUR`). In-process only; use **Redis** on Render for idempotency and safer multi-instance behaviour.
- **Multi-turn draft (Redis):** If a `create_entry` parse is missing fields, the server stores partial `data` when `REDIS_URL` is set. The user can send **follow-up lines** (`qty: 10`, `buy: 100`, etc.) to merge into that draft until a full preview is possible. Without Redis, this memory is not available.

## Display name

The **business name shown in WhatsApp** is configured in **Meta / Authkey WABA**, not in the Flutter app.
