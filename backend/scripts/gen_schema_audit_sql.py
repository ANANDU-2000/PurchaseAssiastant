#!/usr/bin/env python3
"""Emit SQL that lists model columns missing from public schema."""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
expected = json.loads((ROOT / "schema_expected.json").read_text(encoding="utf-8"))
vals: list[str] = []
for table, cols in sorted(expected.items()):
    for col in cols:
        esc_t = table.replace("'", "''")
        esc_c = col.replace("'", "''")
        vals.append(f"('{esc_t}','{esc_c}')")
sql = (
    "WITH expected(table_name, column_name) AS (\n  VALUES\n"
    + ",\n".join(vals)
    + """
)
SELECT e.table_name, e.column_name
FROM expected e
WHERE NOT EXISTS (
  SELECT 1 FROM information_schema.columns col
  WHERE col.table_schema = 'public'
    AND col.table_name = e.table_name
    AND col.column_name = e.column_name
)
ORDER BY 1, 2;"""
)
out = ROOT / "schema_audit_missing.sql"
out.write_text(sql, encoding="utf-8")
print(f"Wrote {out} ({len(vals)} pairs, {len(sql)} chars)")
