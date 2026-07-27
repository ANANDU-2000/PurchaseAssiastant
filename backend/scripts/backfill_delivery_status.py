"""Correct delivery_status when marked stock_committed but stock movements missing.

Usage (from backend/, with DATABASE_URL set):
  python -m scripts.backfill_delivery_status [--business-id UUID] [--dry-run]
"""

from __future__ import annotations

import argparse
import asyncio
import uuid

from sqlalchemy import select

from app.database import async_session_maker
from app.models import TradePurchase
from app.services.stock_inventory import purchase_delivery_stock_already_applied


async def run(*, business_id: uuid.UUID | None, dry_run: bool) -> None:
    async with async_session_maker() as db:
        q = select(TradePurchase).where(
            TradePurchase.status.notin_(("deleted", "cancelled")),
        )
        if business_id:
            q = q.where(TradePurchase.business_id == business_id)
        rows = (await db.execute(q)).scalars().all()
        fixed = 0
        skipped = 0
        for tp in rows:
            status = (getattr(tp, "delivery_status", None) or "pending").strip().lower()
            if status == "stock_committed":
                applied = await purchase_delivery_stock_already_applied(
                    db, tp.business_id, tp.id
                )
                if applied:
                    skipped += 1
                    continue
                print(
                    f"{'[dry-run] ' if dry_run else ''}"
                    f"{tp.human_id}: stock_committed -> arrived (no movement)"
                )
                if not dry_run:
                    tp.delivery_status = "arrived"
                    if tp.arrived_at is None and tp.delivered_at is not None:
                        tp.arrived_at = tp.delivered_at
                fixed += 1
                continue
            if tp.is_delivered and status in ("pending", "stock_committed"):
                applied = await purchase_delivery_stock_already_applied(
                    db, tp.business_id, tp.id
                )
                if applied:
                    if not dry_run and status != "stock_committed":
                        tp.delivery_status = "stock_committed"
                    skipped += 1
                    continue
                if status == "pending":
                    print(
                        f"{'[dry-run] ' if dry_run else ''}"
                        f"{tp.human_id}: pending + is_delivered -> arrived"
                    )
                    if not dry_run:
                        tp.delivery_status = "arrived"
                    fixed += 1
        if not dry_run:
            await db.commit()
        print(f"done: fixed={fixed} skipped={skipped} scanned={len(rows)}")


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--business-id", type=uuid.UUID, default=None)
    p.add_argument("--dry-run", action="store_true")
    args = p.parse_args()
    asyncio.run(run(business_id=args.business_id, dry_run=args.dry_run))


if __name__ == "__main__":
    main()
