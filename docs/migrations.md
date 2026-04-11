# Database migrations

## Current state

The FastAPI app runs `Base.metadata.create_all` on startup for **local development** convenience.

## Production recommendation

1. Install Alembic in the backend environment: `pip install alembic`.
2. From `backend/`, run `alembic init alembic` (once) or use the repo’s `alembic/` folder when added.
3. Point `sqlalchemy.url` at the same database as `DATABASE_URL` (use a **sync** driver URL for Alembic, e.g. `postgresql+psycopg2://...` if you use asyncpg at runtime).
4. Set `target_metadata = Base.metadata` importing `Base` from `app.models`.
5. Generate revisions: `alembic revision --autogenerate -m "describe change"`.
6. Apply: `alembic upgrade head`.

## Contract

After schema changes, update [`docs/api/openapi.yaml`](api/openapi.yaml) if API payloads change, and run app/backend tests.
