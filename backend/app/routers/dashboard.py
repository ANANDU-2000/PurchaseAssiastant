"""Composite month dashboard for trade purchases (GET /dashboard?month=YYYY-MM)."""

from __future__ import annotations

import calendar
import uuid
from datetime import date
from typing import Annotated

from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel, Field
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.deps import require_membership
from app.models import Membership, TradePurchase, TradePurchaseLine

router = APIRouter(prefix="/v1/businesses/{business_id}", tags=["dashboard"])


class DashboardCategorySlice(BaseModel):
    name: str = Field(default="Uncategorized")
    amount: float = 0.0
    profit: float = 0.0
    total_qty: float = 0.0


class DashboardItemSlice(BaseModel):
    name: str
    amount: float = 0.0
    profit: float = 0.0
    total_qty: float = 0.0


class DashboardOut(BaseModel):
    month: str
    total_purchase: float
    total_paid: float
    pending: float
    total_profit: float
    purchase_count: int
    categories: list[DashboardCategorySlice]
    items: list[DashboardItemSlice]


@router.get("/dashboard", response_model=DashboardOut)
async def business_dashboard(
    business_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
    month: str = Query(..., description="Calendar month YYYY-MM"),
):
    del _m
    parts = month.strip().split("-")
    if len(parts) != 2:
        from fastapi import HTTPException, status

        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, detail="month must be YYYY-MM")
    y, m = int(parts[0]), int(parts[1])
    start = date(y, m, 1)
    last = calendar.monthrange(y, m)[1]
    end = date(y, m, last)

    tp_f = (
        TradePurchase.business_id == business_id,
        TradePurchase.purchase_date >= start,
        TradePurchase.purchase_date <= end,
        TradePurchase.status != "cancelled",
    )

    r = await db.execute(
        select(
            func.coalesce(func.sum(TradePurchase.total_amount), 0.0),
            func.coalesce(func.sum(TradePurchase.paid_amount), 0.0),
            func.count(TradePurchase.id),
        ).where(*tp_f)
    )
    tot, paid, n = r.one()
    tot_f = float(tot or 0)
    paid_f = float(paid or 0)
    pending = max(0.0, tot_f - paid_f)

    # Line-level profit: (selling - landing) * qty when selling_cost set
    pr = await db.execute(
        select(
            func.coalesce(
                func.sum(
                    (func.coalesce(TradePurchaseLine.selling_cost, 0.0) - TradePurchaseLine.landing_cost)
                    * TradePurchaseLine.qty
                ),
                0.0,
            )
        )
        .select_from(TradePurchaseLine)
        .join(TradePurchase, TradePurchase.id == TradePurchaseLine.trade_purchase_id)
        .where(*tp_f)
    )
    line_profit = float(pr.scalar() or 0)

    # Per-item spend (qty * landing) for top list
    ir = await db.execute(
        select(
            TradePurchaseLine.item_name,
            func.coalesce(
                func.sum(TradePurchaseLine.qty * TradePurchaseLine.landing_cost), 0.0
            ).label("spend"),
            func.coalesce(
                func.sum(
                    (func.coalesce(TradePurchaseLine.selling_cost, 0.0) - TradePurchaseLine.landing_cost)
                    * TradePurchaseLine.qty
                ),
                0.0,
            ).label("pf"),
            func.coalesce(func.sum(TradePurchaseLine.qty), 0.0).label("tq"),
        )
        .select_from(TradePurchaseLine)
        .join(TradePurchase, TradePurchase.id == TradePurchaseLine.trade_purchase_id)
        .where(*tp_f)
        .group_by(TradePurchaseLine.item_name)
        .order_by(func.sum(TradePurchaseLine.qty * TradePurchaseLine.landing_cost).desc())
        .limit(20)
    )
    items: list[DashboardItemSlice] = []
    for row in ir.all():
        name, sp, pf, tq = str(row[0]), float(row[1] or 0), float(row[2] or 0), float(row[3] or 0)
        items.append(DashboardItemSlice(name=name, amount=sp, profit=pf, total_qty=tq))

    # Categories: we only have item_name on line — group by first word / heuristic "Uncategorized"
    cat_map: dict[str, list[float]] = {}
    for it in items:
        key = "General"
        for sep in (" ", "—", "-", "("):
            if sep in it.name:
                key = it.name.split(sep)[0].strip() or "General"
                break
        acc = cat_map.setdefault(key, [0.0, 0.0, 0.0])
        acc[0] += it.amount
        acc[1] += it.profit
        acc[2] += it.total_qty
    categories = [
        DashboardCategorySlice(
            name=k,
            amount=v[0],
            profit=v[1],
            total_qty=v[2],
        )
        for k, v in sorted(cat_map.items(), key=lambda x: -x[1][0])
 ][:12]

    return DashboardOut(
        month=f"{y:04d}-{m:02d}",
        total_purchase=tot_f,
        total_paid=paid_f,
        pending=pending,
        total_profit=line_profit,
        purchase_count=int(n or 0),
        categories=categories,
        items=items,
    )
