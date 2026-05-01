"""Alembic environment — sync URL derived from DATABASE_URL (async URL supported)."""

from __future__ import annotations

import os
import sys
from logging.config import fileConfig
from pathlib import Path

from alembic import context
from sqlalchemy import engine_from_config, pool

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

_backend_root = Path(__file__).resolve().parent.parent
try:
    from dotenv import load_dotenv

    # Prefer values in backend/.env over inherited shell env (avoids stale DATABASE_* on dev machines).
    load_dotenv(_backend_root / ".env", override=True)
except ImportError:
    pass

from app.models.base import Base  # noqa: E402
from app.models import *  # noqa: F401,F403,E402 — register metadata

config = context.config
if config.config_file_name is not None:
    fileConfig(config.config_file_name)

target_metadata = Base.metadata


def _sync_url() -> str:
    """Match runtime DB selection in app.database: pooler URL, password-only env, HEXA_USE_SQLITE."""
    from sqlalchemy.engine.url import make_url

    if os.environ.get("HEXA_USE_SQLITE", "").strip().lower() in ("1", "true", "yes"):
        raw = (os.environ.get("DATABASE_URL") or "").strip()
        if raw.startswith("sqlite"):
            if "sqlite+aiosqlite" in raw:
                return raw.replace("sqlite+aiosqlite", "sqlite", 1)
            return raw
        return "sqlite:///./hexa_dev.db"

    pooler = (os.environ.get("DATABASE_POOLER_URL") or "").strip()
    database_url = (os.environ.get("DATABASE_URL") or "postgresql://user:password@localhost:5432/hexa").strip()
    effective = pooler if pooler else database_url

    if effective.startswith("postgresql+asyncpg://"):
        effective = "postgresql://" + effective.removeprefix("postgresql+asyncpg://")
    elif effective.startswith("postgres+asyncpg://"):
        effective = "postgresql://" + effective.removeprefix("postgres+asyncpg://")

    pwd = (os.environ.get("DATABASE_POOLER_PASSWORD") or "").strip()
    if pooler and pwd:
        try:
            u = make_url(effective)
            effective = u.set(password=pwd).render_as_string(hide_password=False)
        except Exception:
            pass

    if "sqlite+aiosqlite" in effective:
        effective = effective.replace("sqlite+aiosqlite", "sqlite", 1)

    return effective


def run_migrations_offline() -> None:
    context.configure(
        url=_sync_url(),
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
    )
    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online() -> None:
    configuration = config.get_section(config.config_ini_section) or {}
    configuration["sqlalchemy.url"] = _sync_url()
    connectable = engine_from_config(configuration, prefix="sqlalchemy.", poolclass=pool.NullPool)
    with connectable.connect() as connection:
        context.configure(connection=connection, target_metadata=target_metadata)
        with context.begin_transaction():
            context.run_migrations()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
