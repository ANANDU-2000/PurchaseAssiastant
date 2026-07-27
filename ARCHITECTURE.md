# HEXA Purchase Assistant — Architecture

## Stack

| Layer | Technology | Deploy Target |
|-------|-----------|---------------|
| Frontend | Flutter (Riverpod, GoRouter, Dio) | Vercel (PWA) |
| Backend | FastAPI (asyncpg, SQLAlchemy, Alembic) | Render Web Service |
| Database | PostgreSQL 16 | Render Postgres |
| Cache | Optional Redis (in-memory fallback) | Render / Memurai |
| CI/CD | GitHub Actions (db-backup, keep-alive) | GitHub |

## Folder Map

```
PurchaseAssiastant/
├── flutter_app/           # Flutter PWA (web-only after cleanup)
│   ├── lib/
│   │   ├── core/          # API, auth, providers, theme, router
│   │   ├── features/      # Feature modules (stock, purchase, barcode, reports...)
│   │   ├── shared/        # Reusable widgets
│   │   └── widgets/       # Generic hexa widgets
│   ├── web/               # PWA manifest, service worker, index.html
│   └── test/              # Flutter unit + widget tests
├── backend/               # FastAPI server
│   ├── app/
│   │   ├── routers/       # API route handlers
│   │   ├── services/      # Business logic (stock, JWT, OTP, AI...)
│   │   ├── models/        # SQLAlchemy models
│   │   ├── schemas/       # Pydantic request/response schemas
│   │   └── middleware/    # CORS, observability
│   ├── alembic/           # Database migrations
│   ├── tests/             # Pytest suite (255+ tests)
│   └── scripts/           # Seed, backfill, ops scripts
├── docs/
│   ├── TEST_RESULTS.md    # Test baseline + results
│   ├── env_audit/         # .env usage audit
│   └── archive/           # Historical docs (audits, plans, perf reports)
├── .env.example           # Master environment template
├── ARCHITECTURE.md        # This file
├── DEPLOYMENT.md          # Deploy instructions
├── PLAN.md                # Master execution plan
└── README.md              # Product overview
```

## Data Flow

```
Browser (PWA) ──HTTPS──> Vercel CDN ──> Flutter app
                    │
                    ▼
           API (Render) ──> PostgreSQL
                    │
                    ▼
           AI providers (OpenAI / Groq / Gemini)
```

## Key Patterns

- **State:** Riverpod `FutureProvider` / `StateNotifierProvider` — no setState for core data
- **Mutations:** Optimistic patches + deferred invalidation (immediate for user saves)
- **Stock:** Versioned with 409 conflict retry + `invalidateStockRowSaveSurfaces`
- **Auth:** JWT access/refresh tokens, 401 circuit breaker, single-flight refresh
- **Caching:** 30s stock list TTL, 45s shell tab return interval, ETag support

## Deploy Targets

- **Frontend:** `https://purchase-assiastant.vercel.app`
- **API:** `https://my-purchases-api.onrender.com`
- **Health:** `GET /health/ready` → `{"status":"ok","db":"ok","schema_ok":true}`
