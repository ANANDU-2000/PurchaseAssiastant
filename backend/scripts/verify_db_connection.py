"""
Read-only: list tables, row counts (sample), and alembic_version for a Postgres URL.

Usage (PowerShell) — get URL from Supabase / Render; do not commit secrets:

  cd backend
  $env:CHECK_DATABASE_URL = "postgresql://USER:PASSWORD@HOST:6543/postgres"
  $env:CHECK_DATABASE_SSL = "1"   # optional: require SSL (psycopg2 sslmode)
  python -m scripts.verify_db_connection

If using pooler with password only in DATABASE_POOLER_PASSWORD, build the sync URL
the same way as app/database.py (asyncpg -> postgresql, password in URL or query).

Safe: prints table names and counts only; no connection string echo.
"""

from __future__ import annotations

import os
import re
import sys
from pathlib import Path

# Allow `python -m scripts.verify_db_connection` from backend/
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))


def _sync_url() -> str:
    raw = (os.environ.get("CHECK_DATABASE_URL") or "").strip()
    if not raw:
        print(
            "Set CHECK_DATABASE_URL to a sync postgresql://... DSN (not asyncpg).",
            file=sys.stderr,
        )
        sys.exit(1)
    if raw.startswith("postgresql+asyncpg://"):
        return "postgresql://" + raw.removeprefix("postgresql+asyncpg://")
    if raw.startswith("postgres+asyncpg://"):
        return "postgresql://" + raw.removeprefix("postgres+asyncpg://")
    if raw.startswith("postgres://"):
        return "postgresql://" + raw.removeprefix("postgres://")
    return raw


def main() -> None:
    from sqlalchemy import create_engine, inspect, text

    url = _sync_url()
    # Optional SSL (Supabase / Render often need TLS)
    connect_args: dict = {}
    if os.environ.get("CHECK_DATABASE_SSL", "").strip().lower() in ("1", "true", "yes"):
        connect_args["sslmode"] = "require"

    eng = create_engine(url, connect_args=connect_args, pool_pre_ping=True)
    insp = inspect(eng)
    names = insp.get_table_names()
    print(f"ok: {len(names)} tables\n")

    for t in sorted(names)[:50]:
        if not re.match(r"^[a-zA-Z0-9_]+$", t):
            print(f"  {t:40} (skip count: non-simple name)")
            continue
        try:
            with eng.connect() as c:
                n = c.execute(text(f"SELECT COUNT(*) FROM {t}")).scalar()
            print(f"  {t:40} {int(n) if n is not None else 0:>10}")
        except Exception as e:  # noqa: BLE001
            print(f"  {t:40} (count failed: {e!s})")
    if len(names) > 50:
        print(f"  ... and {len(names) - 50} more")

    with eng.connect() as c:
        try:
            r = c.execute(text("select version_num from alembic_version"))
            rows = r.fetchall()
            print("\nalembic_version:", [x[0] for x in rows] if rows else "missing")
        except Exception:  # noqa: BLE001
            print("\nalembic_version: table missing or not migrated")


if __name__ == "__main__":
    main()
