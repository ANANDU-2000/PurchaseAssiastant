"""Backfill ``trade_purchase_lines.line_total`` and ``profit`` from SSOT helpers.

Prints drift counters (null ``line_total`` / ``profit``) before and after the run.

  python scripts/backfill_trade_line_totals.py --dry-run
  python scripts/backfill_trade_line_totals.py
  python scripts/backfill_trade_line_totals.py --json
"""

from __future__ import annotations

import argparse
import asyncio
import os
import sys
from decimal import Decimal
from typing import Any

from sqlalchemy import or_, select, func
from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine
from sqlalchemy.orm import sessionmaker

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))


def _get_database_url() -> str:
    from app.config import get_settings  # noqa: WPS433

    return get_settings().database_url


def _line_in_from_orm(ln: Any) -> dict[str, Any]:
    """Shape accepted by ``TradePurchaseLineIn`` from ORM row."""
    return {
        "catalog_item_id": str(ln.catalog_item_id),
        "item_name": ln.item_name,
        "qty": str(ln.qty),
        "unit": ln.unit,
        "landing_cost": str(ln.landing_cost),
        "purchase_rate": str(ln.purchase_rate) if ln.purchase_rate is not None else None,
        "kg_per_unit": str(ln.kg_per_unit) if ln.kg_per_unit is not None else None,
        "weight_per_unit": str(ln.weight_per_unit) if ln.weight_per_unit is not None else None,
        "landing_cost_per_kg": str(ln.landing_cost_per_kg) if ln.landing_cost_per_kg is not None else None,
        "selling_cost": str(ln.selling_cost) if ln.selling_cost is not None else None,
        "selling_rate": str(ln.selling_rate) if ln.selling_rate is not None else None,
        "freight_type": ln.freight_type,
        "freight_value": str(ln.freight_value) if ln.freight_value is not None else None,
        "delivered_rate": str(ln.delivered_rate) if ln.delivered_rate is not None else None,
        "billty_rate": str(ln.billty_rate) if ln.billty_rate is not None else None,
        "box_mode": ln.box_mode,
        "items_per_box": str(ln.items_per_box) if ln.items_per_box is not None else None,
        "weight_per_item": str(ln.weight_per_item) if ln.weight_per_item is not None else None,
        "kg_per_box": str(ln.kg_per_box) if ln.kg_per_box is not None else None,
        "weight_per_tin": str(ln.weight_per_tin) if ln.weight_per_tin is not None else None,
        "discount": str(ln.discount) if ln.discount is not None else None,
        "tax_percent": str(ln.tax_percent) if ln.tax_percent is not None else None,
    }


async def _null_line_counts(db: AsyncSession) -> dict[str, int]:
    """Rows still missing persisted fiscal columns (drift / backlog signal)."""
    from app.models.trade_purchase import TradePurchaseLine

    lt = await db.execute(
        select(func.count()).select_from(TradePurchaseLine).where(TradePurchaseLine.line_total.is_(None))
    )
    pf = await db.execute(
        select(func.count()).select_from(TradePurchaseLine).where(TradePurchaseLine.profit.is_(None))
    )
    return {
        "line_total_null": int(lt.scalar() or 0),
        "profit_null": int(pf.scalar() or 0),
    }


async def _run(db: AsyncSession, dry_run: bool) -> dict[str, Any]:
    from app.models.trade_purchase import TradePurchase, TradePurchaseLine
    from app.schemas.trade_purchases import TradePurchaseCreateRequest, TradePurchaseLineIn
    from app.services import trade_purchase_service as tps
    from app.services.line_totals_service import line_money, line_profit

    null_before = await _null_line_counts(db)
    q = (
        select(TradePurchaseLine, TradePurchase)
        .join(TradePurchase, TradePurchaseLine.trade_purchase_id == TradePurchase.id)
        .where(or_(TradePurchaseLine.line_total.is_(None), TradePurchaseLine.profit.is_(None)))
    )
    rows = (await db.execute(q)).all()
    updated = 0
    skipped = 0
    for ln, tp in rows:
        try:
            raw = _line_in_from_orm(ln)
            li = TradePurchaseLineIn.model_validate(raw)
        except Exception:  # noqa: BLE001
            skipped += 1
            continue
        li2 = tps.normalize_trade_line_for_preview(li)
        req = TradePurchaseCreateRequest(
            purchase_date=tp.purchase_date,
            supplier_id=tp.supplier_id,
            broker_id=tp.broker_id,
            status=(tp.status or "confirmed"),
            lines=[li2],
        )
        try:
            lt = line_money(li2)
            prof = line_profit(li2, req)
        except Exception:  # noqa: BLE001
            skipped += 1
            continue
        if not dry_run:
            ln.line_total = lt
            ln.profit = prof
        updated += 1
    if not dry_run:
        await db.commit()
    null_after = await _null_line_counts(db)
    return {
        "candidates": len(rows),
        "updated": updated,
        "skipped_parse": skipped,
        "null_line_total_before": null_before["line_total_null"],
        "null_profit_before": null_before["profit_null"],
        "null_line_total_after": null_after["line_total_null"],
        "null_profit_after": null_after["profit_null"],
    }


async def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--dry-run", action="store_true")
    p.add_argument("--json", action="store_true", help="Print stats as one JSON line")
    args = p.parse_args()
    url = _get_database_url()
    if "+asyncpg" not in url and "asyncpg" not in url and not url.startswith("sqlite+"):
        print("Use async database URL.", file=sys.stderr)
        raise SystemExit(1)
    engine = create_async_engine(url)
    session_factory = sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)
    async with session_factory() as db:
        stats = await _run(db, dry_run=args.dry_run)
    await engine.dispose()
    if args.json:
        import json

        print(json.dumps(stats, default=str))
    else:
        print(stats)


if __name__ == "__main__":
    asyncio.run(main())
