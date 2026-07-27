#!/usr/bin/env python3
"""Compare SQLAlchemy models to live Postgres (run from backend/ with DATABASE_URL set).

Usage:
  cd backend && python scripts/schema_audit.py
"""
from __future__ import annotations

import importlib
import os
import pkgutil
import sys
from pathlib import Path

from sqlalchemy import create_engine, inspect

BACKEND = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND))

import app.models  # noqa: F401, E402

for _, name, _ in pkgutil.iter_modules(app.models.__path__):
    importlib.import_module(f"app.models.{name}")

from app.models.base import Base  # noqa: E402


def main() -> int:
    url = os.environ.get("DATABASE_URL", "").strip()
    if not url:
        print("Set DATABASE_URL (Postgres) to audit production.")
        return 1
    if url.startswith("postgresql://"):
        url = url.replace("postgresql://", "postgresql+psycopg2://", 1)
    engine = create_engine(url)
    insp = inspect(engine)
    db_tables = set(insp.get_table_names(schema="public"))
    model_tables = set(Base.metadata.tables.keys())
    missing_tables = sorted(model_tables - db_tables)
    extra_tables = sorted(db_tables - model_tables - {"alembic_version"})
    missing_cols: list[str] = []
    for name in sorted(model_tables & db_tables):
        db_cols = {c["name"] for c in insp.get_columns(name, schema="public")}
        model_cols = {c.name for c in Base.metadata.tables[name].columns}
        for col in sorted(model_cols - db_cols):
            missing_cols.append(f"{name}.{col}")
    print("=== Missing tables (in models, not in DB) ===")
    for t in missing_tables:
        print(f"  - {t}")
    print("\n=== Missing columns ===")
    for line in missing_cols:
        print(f"  - {line}")
    if not missing_tables and not missing_cols:
        print("OK: all model tables/columns present in public schema.")
        return 0
    print(f"\nFound {len(missing_tables)} missing table(s), {len(missing_cols)} missing column(s).")
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
