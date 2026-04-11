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
os.environ["DATABASE_URL"] = f"sqlite+aiosqlite:///{_test_db_path.as_posix()}"
os.environ.setdefault("APP_ENV", "test")


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
