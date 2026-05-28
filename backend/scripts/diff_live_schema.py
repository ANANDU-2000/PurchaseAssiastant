#!/usr/bin/env python3
"""Diff SQLAlchemy models vs schema_live_rows.json or MCP export file."""
from __future__ import annotations

import json
import re
import sys
from collections import defaultdict
from pathlib import Path

BACKEND = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND))

import importlib
import pkgutil

import app.models  # noqa: F401

for _, name, _ in pkgutil.iter_modules(app.models.__path__):
    importlib.import_module(f"app.models.{name}")

from app.models.base import Base  # noqa: E402


def load_live(path: Path) -> dict[str, set[str]]:
    text = path.read_text(encoding="utf-8")
    if path.suffix == ".json" and text.strip().startswith("["):
        rows = json.loads(text)
    else:
        outer = json.loads(text)
        inner = outer["result"]
        idx = inner.find("[{")
        blob = inner[idx : inner.rfind("}]") + 2]
        blob = blob.replace('\\"', '"')
        rows = json.loads(blob)
    live: dict[str, set[str]] = defaultdict(set)
    for row in rows:
        live[row["table_name"]].add(row["column_name"])
    return live


def main() -> int:
    live_path = BACKEND / "schema_live_rows.json"
    if len(sys.argv) > 1:
        live_path = Path(sys.argv[1])
    if not live_path.is_file():
        print("Missing live schema file:", live_path)
        return 1
    live = load_live(live_path)
    missing: list[str] = []
    for name, table in sorted(Base.metadata.tables.items()):
        if name in ("broker_supplier_links",):
            continue
        for col in table.columns:
            if col.name not in live.get(name, set()):
                missing.append(f"{name}.{col.name}")
    extra = sorted(
        t for t in live if t not in Base.metadata.tables and t not in ("alembic_version",)
    )
    print(f"Live columns: {sum(len(v) for v in live.values())}")
    print(f"MISSING ({len(missing)}):")
    for m in missing:
        print(" ", m)
    print("EXTRA tables:", extra)
    return 1 if missing else 0


if __name__ == "__main__":
    raise SystemExit(main())
