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
os.environ["DATABASE_URL"] = "sqlite+aiosqlite:///file:hexa_pytest?mode=memory&cache=shared&uri=true"
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
