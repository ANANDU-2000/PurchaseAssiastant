#!/usr/bin/env python3
"""Compare schema_expected.json to schema_live_rows.json (from Supabase MCP execute_sql)."""
from __future__ import annotations

import json
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main() -> int:
    expected_path = ROOT / "schema_expected.json"
    live_path = ROOT / "schema_live_rows.json"
    if not expected_path.exists():
        print("Run export in backend/: python -c '...' -> schema_expected.json")
        return 1
    if not live_path.exists():
        print("Save MCP column rows to backend/schema_live_rows.json")
        return 1

    expected: dict[str, list[str]] = json.loads(
        expected_path.read_text(encoding="utf-8")
    )
    rows = json.loads(live_path.read_text(encoding="utf-8"))
    live: dict[str, set[str]] = defaultdict(set)
    for row in rows:
        live[row["table_name"]].add(row["column_name"])

    missing_tables = sorted(set(expected) - set(live))
    extra_tables = sorted(set(live) - set(expected) - {"alembic_version"})
    missing_cols: list[str] = []
    extra_cols: list[str] = []
    for table in sorted(set(expected) & set(live)):
        for col in sorted(set(expected[table]) - live[table]):
            missing_cols.append(f"{table}.{col}")
        for col in sorted(live[table] - set(expected[table])):
            extra_cols.append(f"{table}.{col}")

    print("=== Missing tables (model, not in DB) ===")
    for t in missing_tables:
        print(f"  - {t}")
    print("\n=== Missing columns ===")
    for line in missing_cols:
        print(f"  - {line}")
    print("\n=== Extra tables (DB only, not in model) ===")
    for t in extra_tables:
        print(f"  - {t}")
    if extra_cols:
        print("\n=== Extra columns (DB only, sample first 30) ===")
        for line in extra_cols[:30]:
            print(f"  - {line}")
        if len(extra_cols) > 30:
            print(f"  ... and {len(extra_cols) - 30} more")

    if not missing_tables and not missing_cols:
        print("\nOK: all model tables/columns present in live Supabase.")
        return 0
    print(
        f"\nFound {len(missing_tables)} missing table(s), "
        f"{len(missing_cols)} missing column(s)."
    )
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
