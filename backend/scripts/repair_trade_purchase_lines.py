"""
Data repair: set missing trade_purchase_lines.catalog_item_id by name match (same business).

Optional: normalize unit string to BAG / BOX / TIN / KG when the label is an obvious variant.

  python repair_trade_purchase_lines.py --dry-run
  python repair_trade_purchase_lines.py
"""

from __future__ import annotations

import argparse
import asyncio
import os
import re
import sys
from typing import Any
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine
from sqlalchemy.orm import sessionmaker

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))


def _get_database_url() -> str:
    from app.config import get_settings  # noqa: WPS433

    return get_settings().database_url


def _norm_name(s: str) -> str:
    t = (s or "").strip()
    t = re.sub(r"\s+", " ", t)
    return t.casefold()


def _canon_unit(u: str) -> str | None:
    t = re.sub(r"[^A-Za-z0-9]", "", (u or "").upper())
    if not t:
        return None
    m = {
        "BAG": "BAG",
        "BAGS": "BAG",
        "BOX": "BOX",
        "BOXES": "BOX",
        "TIN": "TIN",
        "TINS": "TIN",
        "KG": "KG",
        "KGS": "KG",
    }
    return m.get(t)


async def _run(db: AsyncSession, dry_run: bool) -> dict[str, Any]:
    from app.models.catalog import CatalogItem
    from app.models.trade_purchase import TradePurchase, TradePurchaseLine

    res = await db.execute(select(CatalogItem))
    by_biz: dict[UUID, dict[str, list[UUID]]] = {}
    for row in res.scalars().all():
        nk = _norm_name(row.name)
        if not nk:
            continue
        by_biz.setdefault(row.business_id, {}).setdefault(nk, []).append(row.id)

    q = (
        select(TradePurchaseLine, TradePurchase.business_id)
        .join(TradePurchase, TradePurchaseLine.trade_purchase_id == TradePurchase.id)
    )
    all_rows = (await db.execute(q)).all()

    link_updates = 0
    unit_updates = 0
    for ln, business_id in all_rows:
        if ln.catalog_item_id is None:
            nk = _norm_name(ln.item_name)
            cands = (by_biz.get(business_id) or {}).get(nk) or []
            if len(cands) == 1:
                if not dry_run:
                    ln.catalog_item_id = cands[0]
                link_updates += 1
        cu = _canon_unit(ln.unit)
        if cu:
            cur = (ln.unit or "").strip()
            if cur.upper() != cu:
                if not dry_run:
                    ln.unit = cu
                unit_updates += 1

    if not dry_run:
        await db.commit()
    return {
        "lines_total": len(all_rows),
        "catalog_id_links": link_updates,
        "unit_label_fixes": unit_updates,
    }


async def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--dry-run", action="store_true")
    args = p.parse_args()
    url = _get_database_url()
    if "+asyncpg" not in url and "asyncpg" not in url and not url.startswith("sqlite+"):
        print(
            "Use async database URL (postgresql+asyncpg:// or sqlite+aiosqlite/...).",
            file=sys.stderr,
        )
        raise SystemExit(1)
    engine = create_async_engine(url)
    session_factory = sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)
    async with session_factory() as db:
        stats = await _run(db, dry_run=args.dry_run)
    await engine.dispose()
    print(stats)


if __name__ == "__main__":
    asyncio.run(main())
