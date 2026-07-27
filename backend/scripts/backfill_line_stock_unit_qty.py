"""
Backfill trade_purchase_lines.qty_in_stock_unit from catalog + line fields.

Usage (from backend/):
  python -m scripts.backfill_line_stock_unit_qty
"""

from __future__ import annotations

import asyncio
import uuid

from sqlalchemy import select

from app.database import async_session_factory
from app.models import CatalogItem, TradePurchaseLine
from app.services.unit_normalization import line_qty_in_stock_unit


async def main() -> None:
    updated = 0
    async with async_session_factory() as db:
        r = await db.execute(select(TradePurchaseLine, CatalogItem).join(
            CatalogItem, TradePurchaseLine.catalog_item_id == CatalogItem.id
        ))
        for line, item in r.all():
            qty_su = line_qty_in_stock_unit(line, item)
            if line.qty_in_stock_unit != qty_su:
                line.qty_in_stock_unit = qty_su
                updated += 1
        await db.commit()
    print(f"Updated {updated} lines")


if __name__ == "__main__":
    asyncio.run(main())
