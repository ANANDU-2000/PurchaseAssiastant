"""
Admin: reset data. Keeps user accounts and businesses.

  python admin_reset.py --purchases-only
  python admin_reset.py --full-reset
"""

from __future__ import annotations

import argparse
import asyncio
import os
import sys
from typing import NoReturn

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine
from sqlalchemy.orm import sessionmaker

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))


def _get_database_url() -> str:
    from app.config import get_settings  # noqa: WPS433

    return get_settings().database_url


async def _reset_purchases_only(db: AsyncSession) -> None:
    # Trade + legacy entry tables (idempotent; skip if not exist in older DBs)
    for sql in (
        "DELETE FROM trade_purchase_lines",
        "DELETE FROM trade_purchases",
        "DELETE FROM entry_line_items",
        "DELETE FROM entries",
    ):
        try:
            await db.execute(text(sql))
        except Exception:  # noqa: BLE001
            pass
    await db.commit()
    print("Purchases and related lines cleared. Suppliers/items preserved.")


async def _full_reset(db: AsyncSession) -> None:
    await _reset_purchases_only(db)
    for sql in (
        "DELETE FROM catalog_variants",
        "DELETE FROM catalog_items",
        "DELETE FROM category_types",
        "DELETE FROM item_categories",
        "DELETE FROM suppliers",
        "DELETE FROM brokers",
    ):
        try:
            await db.execute(text(sql))
        except Exception:  # noqa: BLE001
            pass
    await db.commit()
    print("Full data reset. User accounts and businesses preserved (check FK errors if any).")


async def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument(
        "mode",
        nargs="?",
        default="--purchases-only",
        choices=("--purchases-only", "--full-reset"),
    )
    args = p.parse_args()

    url = _get_database_url()
    if "+asyncpg" not in url and "asyncpg" not in url:
        print("Use async database URL (postgresql+asyncpg://...) for this script.", file=sys.stderr)
        raise SystemExit(1)

    engine = create_async_engine(url)
    session_factory = sessionmaker(
        engine, class_=AsyncSession, expire_on_commit=False
    )
    async with session_factory() as db:
        if args.mode == "--full-reset":
            await _full_reset(db)
        else:
            await _reset_purchases_only(db)
    await engine.dispose()


if __name__ == "__main__":
    asyncio.run(main())
