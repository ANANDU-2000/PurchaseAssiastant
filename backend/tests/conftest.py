import asyncio
import os
import sys
import tempfile
from pathlib import Path

# Ensure `app` package resolves when running pytest from repo root or backend/
_root = Path(__file__).resolve().parents[1]
if str(_root) not in sys.path:
    sys.path.insert(0, str(_root))

# Use a fresh SQLite file per pytest process so metadata.create_all matches models
# (avoids "no such table/column" when dev hexa_dev.db predates catalog / catalog_item_id).
_tmp_db_dir = Path(tempfile.mkdtemp(prefix="hexa_pytest_"))
_test_db_path = _tmp_db_dir / "test.db"
# Force test mode so Settings prefers env over .env (see app/config.py settings_customise_sources).
os.environ["APP_ENV"] = "test"
os.environ["DATABASE_URL"] = f"sqlite+aiosqlite:///{_test_db_path.as_posix()}"
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
