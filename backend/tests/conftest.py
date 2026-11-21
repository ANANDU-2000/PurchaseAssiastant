import asyncio
import os
import sys
from pathlib import Path

# Ensure `app` package resolves when running pytest from repo root or backend/
_root = Path(__file__).resolve().parents[1]
if str(_root) not in sys.path:
    sys.path.insert(0, str(_root))

# Use shared-cache in-memory SQLite so async API sessions and sync seed helpers
# see the same schema without touching user temp/OneDrive folders.
# Force test mode so Settings prefers env over .env (see app/config.py settings_customise_sources).
os.environ["APP_ENV"] = "test"
# Tests bootstrap users via POST /v1/auth/register (disabled in production by default).
os.environ["ALLOW_PUBLIC_REGISTRATION"] = "1"
# Default: in-memory SQLite. Set HEXA_TEST_DATABASE_URL (postgresql+asyncpg://...) to run the same
# suite against a real PostgreSQL database that was prepared with `alembic upgrade head`.
os.environ["DATABASE_URL"] = (
    os.environ.get("HEXA_TEST_DATABASE_URL", "").strip()
    or "sqlite+aiosqlite:///file:hexa_pytest?mode=memory&cache=shared&uri=true"
)
if not os.environ["DATABASE_URL"].startswith("sqlite"):
    # TestClient runs each request on its own event loop; asyncpg connections cannot be reused across
    # loops, so PostgreSQL test runs must not pool connections (production keeps its QueuePool).
    import sqlalchemy.ext.asyncio as _sa_async
    from sqlalchemy.pool import NullPool

    _orig_create_async_engine = _sa_async.create_async_engine

    def _create_async_engine_nullpool(url, **kw):
        for _opt in ("pool_size", "max_overflow", "pool_timeout", "pool_recycle", "pool_pre_ping"):
            kw.pop(_opt, None)
        kw["poolclass"] = NullPool
        return _orig_create_async_engine(url, **kw)

    _sa_async.create_async_engine = _create_async_engine_nullpool
# `database.py` prefers DATABASE_POOLER_URL over DATABASE_URL when set — force single test DB.
os.environ["DATABASE_POOLER_URL"] = ""
# Disable dev shortcut so async engine uses DATABASE_URL (same file as bootstrap sync seed).
os.environ["HEXA_USE_SQLITE"] = "0"
# Aggregation read budgets use 0 under tests (no asyncio.wait_for cap).
os.environ["API_READ_BUDGET_SECONDS"] = "0"
# Isolate tests from developer .env LLM keys (avoids flaky / suspended API calls).
for _k in ("GOOGLE_AI_API_KEY", "GROQ_API_KEY", "OPENAI_API_KEY"):
    os.environ[_k] = ""


def _create_all_tables() -> None:
    """Run before test modules import TestClient — module-level clients may run before lifespan."""
    import app.models  # noqa: F401 — register ItemCategory, CatalogItem, etc.
    from app.database import engine
    from app.models import Base

    async def _go() -> None:
        async with engine.begin() as conn:
            await conn.run_sync(Base.metadata.create_all)

    asyncio.run(_go())


_create_all_tables()
