# HEXA Purchase Assistant — System Architecture

## Overview

```
Owner/Staff → Flutter App ──────────────→ FastAPI API ─→ PostgreSQL
                    │                         │
                    │                         ├→ Redis (cache, pub/sub, sessions)
                    │                         │
                    │                         ├→ AI assistant (`/ai/chat`, intent)
                    │                         ├→ OCR / STT workers (async)
                    │                         └→ Object storage (media)

Super Admin → Web App → FastAPI (admin routes, RBAC)
```

## Stack


| Layer                     | Choice                                     |
| ------------------------- | ------------------------------------------ |
| Mobile/Desktop/Web client | Flutter                                    |
| Admin                     | Web (React/Vite or Next — TBD at scaffold) |
| API                       | FastAPI (Python 3.11+)                     |
| DB                        | PostgreSQL 15+                             |
| Cache / realtime          | Redis 7+                                   |
| Assistant (in-app)        | FastAPI `POST .../ai/chat` + optional LLM   |
| AI parsing                | OpenAI (or compatible API)                 |
| OCR / STT                 | Pluggable (Vision API / Azure / Whisper)   |


## Backend Modules (`backend/app/`)


| Module               | Responsibility                                  |
| -------------------- | ----------------------------------------------- |
| `auth`               | Register/login (email, username, password), JWT access/refresh |
| `users`              | Profiles, memberships                           |
| `businesses`         | Tenant/business entity                          |
| `entries`            | CRUD, preview, duplicate detection              |
| `analytics`          | Aggregates, filtered reports                    |
| `price_intelligence` | PIP metrics, history, trends                    |
| `contacts`           | Suppliers, brokers                              |
| `ai_chat` / assistant | In-app chat, previews, optional LLM entity mapping |
| `voice`              | Upload, STT job, handoff to parse               |
| `ocr`                | Upload, OCR job, handoff to parse               |
| `admin`              | Super admin APIs                                |
| `billing`            | Plans, provider webhooks (e.g. Razorpay)        |
| `feature_flags`      | Tenant-scoped flags                             |
| `audit_logs`         | Immutable audit trail                           |


## Realtime

- On entry create/update: publish event to Redis channel or stream.
- Flutter/Admin subscribe via **WebSocket** or **SSE** for dashboard counters and alert badges.
- Analytics: prefer **precomputed snapshots** + incremental updates, not full recompute per request.

## Security

- TLS everywhere in production.
- JWT short-lived access + refresh rotation.
- Webhook signature verification for third-party billing (e.g. Razorpay) where used.
- Secrets only via environment / secret manager — never in repo.

## See Also

- `docs/data-model.md`
- `docs/api/openapi.yaml`
- `docs/ops.md`

