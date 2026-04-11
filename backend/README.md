# HEXA — FastAPI backend

## Setup

1. Copy [../.env.example](../.env.example) to `backend/.env` (or symlink). With Docker Compose from repo root:

   `DATABASE_URL=postgresql+asyncpg://hexa:hexa@localhost:5432/hexa`

2. Create venv and install:

   ```bash
   python -m venv .venv
   .venv\Scripts\pip install -r requirements.txt
   ```

3. Run (from `backend/`):

   ```bash
   .venv\Scripts\python -m uvicorn app.main:app --reload
   ```

   API: http://localhost:8000 — OpenAPI: http://localhost:8000/docs

## Dev auth

- `POST /v1/auth/register` with `{"email":"you@example.com","username":"you","password":"your-secure-password"}` → JWT (`TokenPair`).
- `POST /v1/auth/login` with `{"email_or_username":"you@example.com","password":"..."}` (or use username instead of email) → JWT.
- `POST /v1/auth/refresh` with `{"refresh_token":"..."}` → new tokens.
- `GET /v1/me/businesses` — use `Authorization: Bearer <access>`.

Optional: set `SUPERADMIN_BOOTSTRAP_EMAIL` to your first account email to grant super admin on registration.

- `POST /v1/auth/google` with `{"id_token":"<Google ID token>"}` — requires `GOOGLE_OAUTH_CLIENT_IDS` in `.env` (same Web client ID as Flutter `GOOGLE_OAUTH_CLIENT_ID`). See [flutter_app README](../flutter_app/README.md) for Google Cloud and iOS URL scheme setup.

## Layout

See [docs/architecture.md](../docs/architecture.md) and [docs/api/openapi.yaml](../docs/api/openapi.yaml).

## Tests

Requires `DATABASE_URL` (same as runtime). Install test deps:

```bash
.venv\Scripts\pip install -r requirements.txt
.venv\Scripts\python -m pytest tests\ -q
```
