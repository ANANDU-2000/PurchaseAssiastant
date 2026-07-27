"""
Recompute catalog_items.current_stock from normalized purchases − usage ± adjustments.

Dry-run by default; pass --apply to write.

Usage (from backend/):
  python -m scripts.repair_stock_from_ledger --business-id <uuid> [--apply]
"""

from __future__ import annotations

import argparse
import asyncio
import uuid
from collections import defaultdict
from datetime import date
from decimal import Decimal

from sqlalchemy import func, select

from app.database import async_session_maker
from app.models import CatalogItem, DailyUsageLog, TradePurchase, TradePurchaseLine
from app.models.stock_adjustment import StockAdjustmentLog
from app.services.unit_normalization import line_qty_in_stock_unit

_PURCHASE_ADJ = frozenset({"purchase", "purchase_reversal", "purchase_adjustment"})


async def expected_stock(db, business_id: uuid.UUID, item_id: uuid.UUID, item: CatalogItem) -> Decimal:
    pr = await db.execute(
        select(TradePurchaseLine)
        .join(TradePurchase, TradePurchaseLine.trade_purchase_id == TradePurchase.id)
        .where(
            TradePurchase.business_id == business_id,
            TradePurchase.status != "cancelled",
            TradePurchaseLine.catalog_item_id == item_id,
        )
    )
    purchased = sum(line_qty_in_stock_unit(li, item) for li in pr.scalars().all())
    ur = await db.execute(
        select(func.coalesce(func.sum(DailyUsageLog.used_qty), 0)).where(
            DailyUsageLog.business_id == business_id,
            DailyUsageLog.item_id == item_id,
        )
    )
    usage = Decimal(ur.scalar_one() or 0)
    ar = await db.execute(
        select(func.coalesce(func.sum(StockAdjustmentLog.new_qty - StockAdjustmentLog.old_qty), 0)).where(
            StockAdjustmentLog.business_id == business_id,
            StockAdjustmentLog.item_id == item_id,
            StockAdjustmentLog.adjustment_type.notin_(_PURCHASE_ADJ),
        )
    )
    adj = Decimal(ar.scalar_one() or 0)
    return purchased - usage + adj


async def run(business_id: uuid.UUID, apply: bool) -> None:
    async with async_session_maker() as db:
        r = await db.execute(
            select(CatalogItem).where(
                CatalogItem.business_id == business_id,
                CatalogItem.deleted_at.is_(None),
                CatalogItem.default_kg_per_bag.isnot(None),
            )
        )
        items = list(r.scalars().all())
        fixes: list[tuple[str, Decimal, Decimal]] = []
        for item in items:
            exp = await expected_stock(db, business_id, item.id, item)
            cur = Decimal(item.current_stock or 0)
            if abs(cur - exp) > Decimal("0.01"):
                fixes.append((item.name or str(item.id), cur, exp))
                if apply:
                    item.current_stock = exp
        if apply:
            await db.commit()
        print(f"Items checked: {len(items)}, mismatches: {len(fixes)}")
        for name, cur, exp in fixes[:50]:
            print(f"  {name}: was {cur} -> {exp}")
        if len(fixes) > 50:
            print(f"  ... and {len(fixes) - 50} more")


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--business-id", required=True)
    p.add_argument("--apply", action="store_true")
    args = p.parse_args()
    asyncio.run(run(uuid.UUID(args.business_id), args.apply))


if __name__ == "__main__":
    main()
