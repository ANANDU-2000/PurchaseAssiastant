from __future__ import annotations

import os
import sys

from sqlalchemy import create_engine, text


def main() -> int:
    dsn = (os.environ.get("DATABASE_URL") or "").strip()
    if not dsn:
        print("Set DATABASE_URL to your Postgres DSN", file=sys.stderr)
        return 2
    if "+asyncpg" in dsn:
        dsn = dsn.replace("postgresql+asyncpg://", "postgresql://").replace(
            "postgres+asyncpg://", "postgres://"
        )
    if dsn.startswith("postgres://"):
        dsn = "postgresql://" + dsn.removeprefix("postgres://")

    eng = create_engine(dsn, future=True, pool_pre_ping=True)
    with eng.begin() as c:
        cols = c.execute(
            text(
                """
                select column_name
                from information_schema.columns
                where table_name = 'trade_purchases'
                  and column_name in (
                    'total_landing_subtotal',
                    'total_selling_subtotal',
                    'total_line_profit'
                  )
                """
            )
        ).fetchall()
        print("existing:", [r[0] for r in cols])

        c.execute(
            text(
                "alter table trade_purchases add column if not exists total_landing_subtotal numeric(18,4) null"
            )
        )
        c.execute(
            text(
                "alter table trade_purchases add column if not exists total_selling_subtotal numeric(18,4) null"
            )
        )
        c.execute(
            text("alter table trade_purchases add column if not exists total_line_profit numeric(18,4) null")
        )

        cols2 = c.execute(
            text(
                """
                select column_name
                from information_schema.columns
                where table_name = 'trade_purchases'
                  and column_name in (
                    'total_landing_subtotal',
                    'total_selling_subtotal',
                    'total_line_profit'
                  )
                order by column_name
                """
            )
        ).fetchall()
        print("after:", [r[0] for r in cols2])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

