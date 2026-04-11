# HEXA Purchase Assistant

WhatsApp-first + Flutter purchase tracking with profit clarity, analytics, and Price Intelligence (PIP).

## Docs

| Doc | Description |
|-----|-------------|
| [Master PRD](docs/master-prd.md) | Product scope, roles, non-goals |
| [Architecture](docs/architecture.md) | System diagram and modules |
| [Data model](docs/data-model.md) | Entities and relationships |
| [OpenAPI](docs/api/openapi.yaml) | API contract (v0.1) |
| [Flutter architecture](docs/flutter-architecture.md) | App structure, state, offline |
| [Screen map & UX](docs/ux/screen-map.md) | Pages and Figma workflow |
| [WhatsApp flows](docs/ux/whatsapp-flows.md) | Webhook conversation patterns |
| [Super Admin](docs/admin-panel.md) | Admin surface plan |
| [Ops](docs/ops.md) | Rate limits, webhooks, monitoring |
| [Delivery phases](docs/delivery-phases.md) | MVP → Phase 4 + testing |

## Quick start

1. **Database:** `docker compose up -d` (or use your own Postgres).
2. **Env:** copy [.env.example](.env.example) to `backend/.env` and set `DATABASE_URL`, e.g.  
   `postgresql+asyncpg://hexa:hexa@localhost:5432/hexa` when using the compose Postgres.
3. **API:**
   ```bash
   cd backend
   python -m venv .venv
   .venv\Scripts\pip install -r requirements.txt
   .venv\Scripts\python -m uvicorn app.main:app --reload
   ```
4. **Admin:** `cd admin_web && npm install && npm run dev` → http://localhost:5173  
5. **Flutter:** install Flutter SDK, then `cd flutter_app && flutter create . && flutter pub get && flutter run`

## Environment

Copy [.env.example](.env.example) to `backend/.env` and fill secrets. Never commit real keys.

## Repo layout

- `flutter_app/` — Flutter client (run `flutter create .` after installing Flutter — see `flutter_app/README.md`)
- `backend/` — FastAPI API (`backend/.venv`, `uvicorn app.main:app --reload`)
- `admin_web/` — Super admin (`npm run dev` in `admin_web/`)
- `docker-compose.yml` — local PostgreSQL + Redis

## Principles

- **Landing cost** is always **manual** at entry.
- **AI** parses and formats only; **backend** owns logic and profit math.
- **Preview → confirm** before persisting any entry.

## Figma

UI work follows `.cursor/rules/figma-design-system.mdc` and the UX docs above.
