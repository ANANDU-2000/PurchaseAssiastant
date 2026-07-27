from __future__ import annotations

import os
import sys

from sqlalchemy import create_engine, text


def main() -> int:
    dsn = (os.environ.get("DATABASE_URL") or "").strip()
    if not dsn:
        print("Set DATABASE_URL", file=sys.stderr)
        return 2
    if "+asyncpg" in dsn:
        dsn = dsn.replace("postgresql+asyncpg://", "postgresql://").replace(
            "postgres+asyncpg://", "postgres://"
        )
    if dsn.startswith("postgres://"):
        dsn = "postgresql://" + dsn.removeprefix("postgres://")
    eng = create_engine(dsn, future=True, pool_pre_ping=True)
    with eng.connect() as c:
        cols = c.execute(
            text(
                """
                select column_name
                from information_schema.columns
                where table_name = 'trade_purchases'
                  and column_name like 'total_%'
                order by column_name
                """
            )
        ).fetchall()
        print([r[0] for r in cols])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

