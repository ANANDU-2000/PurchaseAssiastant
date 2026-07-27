#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
expected = json.loads((ROOT / "schema_expected.json").read_text(encoding="utf-8"))
pairs = [(t, c) for t, cols in sorted(expected.items()) for c in cols]
chunk_size = 110
for i in range(0, len(pairs), chunk_size):
    chunk = pairs[i : i + chunk_size]
    vals = ",\n".join(
        f"('{t.replace(chr(39), chr(39)*2)}','{c.replace(chr(39), chr(39)*2)}')"
        for t, c in chunk
    )
    sql = f"""WITH expected(table_name, column_name) AS (
  VALUES
{vals}
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
    (ROOT / f"schema_audit_chunk_{i // chunk_size + 1}.sql").write_text(
        sql, encoding="utf-8"
    )
print(f"chunks: {(len(pairs) + chunk_size - 1) // chunk_size}")
