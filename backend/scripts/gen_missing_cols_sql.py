#!/usr/bin/env python3
"""Emit SQL to list model columns missing on live DB (paste result into Supabase MCP)."""
from __future__ import annotations

import importlib
import pkgutil
import sys
from pathlib import Path

BACKEND = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND))

import app.models  # noqa: F401

for _, name, _ in pkgutil.iter_modules(app.models.__path__):
    importlib.import_module(f"app.models.{name}")

from app.models.base import Base  # noqa: E402

SKIP = {"broker_supplier_links", "alembic_version", "schema_migrations"}
rows: list[tuple[str, str]] = []
for name, table in sorted(Base.metadata.tables.items()):
    if name in SKIP:
        continue
    for col in table.columns:
        rows.append((name, col.name))

vals = ",\n    ".join(f"('{t}', '{c}')" for t, c in rows)
print(
    f"""WITH expected(t, c) AS (
  VALUES
    {vals}
)
SELECT e.t AS table_name, e.c AS column_name
FROM expected e
WHERE NOT EXISTS (
  SELECT 1 FROM information_schema.columns ic
  WHERE ic.table_schema = 'public' AND ic.table_name = e.t AND ic.column_name = e.c
)
ORDER BY e.t, e.c;"""
)
