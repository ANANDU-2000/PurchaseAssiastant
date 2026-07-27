#!/usr/bin/env python3
"""Diff SQLAlchemy models vs schema_live_rows.json; emit ALTER for missing columns."""
from __future__ import annotations

import importlib
import json
import pkgutil
import sys
from collections import defaultdict
from pathlib import Path

from sqlalchemy import Boolean, Date, DateTime, Integer, Numeric, String, Text
from sqlalchemy.dialects.postgresql import JSONB, UUID

BACKEND = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND))

import app.models  # noqa: F401

for _, name, _ in pkgutil.iter_modules(app.models.__path__):
    importlib.import_module(f"app.models.{name}")

from app.models.base import Base  # noqa: E402

SKIP = {"broker_supplier_links", "alembic_version", "schema_migrations"}


def pg_type(col) -> str:
    t = col.type
    if isinstance(t, JSONB):
        return "JSONB"
    if isinstance(t, UUID):
        return "UUID"
    if isinstance(t, Boolean):
        return "BOOLEAN"
    if isinstance(t, Integer):
        return "INTEGER"
    if isinstance(t, DateTime):
        return "TIMESTAMPTZ" if getattr(t, "timezone", False) else "TIMESTAMP"
    if isinstance(t, Date):
        return "DATE"
    if isinstance(t, Numeric):
        p = getattr(t, "precision", None) or 12
        s = getattr(t, "scale", None) or 3
        return f"NUMERIC({p}, {s})"
    if isinstance(t, String):
        n = getattr(t, "length", None)
        return f"VARCHAR({n})" if n else "TEXT"
    if isinstance(t, Text):
        return "TEXT"
    return "TEXT"


def main() -> int:
    live_path = BACKEND / "schema_live_rows.json"
    if not live_path.is_file():
        print("Missing", live_path)
        return 1
    rows = json.loads(live_path.read_text(encoding="utf-8"))
    live: dict[str, set[str]] = defaultdict(set)
    for row in rows:
        live[row["table_name"]].add(row["column_name"])

    missing: list[str] = []
    alters: list[str] = []
    for name, table in sorted(Base.metadata.tables.items()):
        if name in SKIP:
            continue
        for col in table.columns:
            if col.name in live.get(name, set()):
                continue
            missing.append(f"{name}.{col.name}")
            nullable = "NULL" if col.nullable else "NOT NULL"
            default = ""
            if not col.nullable and isinstance(col.type, Boolean):
                default = " DEFAULT false"
            elif not col.nullable and isinstance(col.type, (Integer, Numeric)):
                default = " DEFAULT 0"
            alters.append(
                f"ALTER TABLE {name} ADD COLUMN IF NOT EXISTS "
                f"{col.name} {pg_type(col)}{default} {nullable};"
            )

    print(f"MISSING ({len(missing)}):")
    for m in missing:
        print(" ", m)
    out = BACKEND / "sql" / "035_model_parity_missing_cols.sql"
    if alters:
        out.write_text(
            "-- Idempotent: add any model columns missing on live Supabase.\n"
            + "\n".join(alters)
            + "\n",
            encoding="utf-8",
        )
        print(f"Wrote {out}")
    return 1 if missing else 0


if __name__ == "__main__":
    raise SystemExit(main())
