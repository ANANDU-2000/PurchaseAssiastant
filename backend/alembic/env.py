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

    if os.environ.get("SKIP_BACKEND_DOTENV", "").strip().lower() not in ("1", "true", "yes"):
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
    """Derive sync URL from DATABASE_URL (async driver → sync driver)."""
    if os.environ.get("HEXA_USE_SQLITE", "").strip().lower() in ("1", "true", "yes"):
        raw = (os.environ.get("DATABASE_URL") or "").strip()
        if raw.startswith("sqlite"):
            if "sqlite+aiosqlite" in raw:
                return raw.replace("sqlite+aiosqlite", "sqlite", 1)
            return raw
        return "sqlite:///./hexa_dev.db"

    url = (os.environ.get("DATABASE_URL") or "postgresql://user:password@localhost:5432/hexa").strip()
    if url.startswith("postgresql+asyncpg://"):
        url = "postgresql://" + url.removeprefix("postgresql+asyncpg://")
    elif url.startswith("postgres+asyncpg://"):
        url = "postgresql://" + url.removeprefix("postgres+asyncpg://")
    elif "sqlite+aiosqlite" in url:
        url = url.replace("sqlite+aiosqlite", "sqlite", 1)
    return url


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
