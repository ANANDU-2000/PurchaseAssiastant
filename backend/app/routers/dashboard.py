"""Composite month dashboard for trade purchases (GET /dashboard?month=YYYY-MM)."""

from __future__ import annotations

import calendar
import uuid
from collections import OrderedDict
from copy import deepcopy
from datetime import date
from time import monotonic
from typing import Annotated, Any

from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel, Field
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.async_budget import run_read_budget_bounded
from app.database import get_db
from app.db_resilience import execute_with_retry
from app.deps import require_membership
from app.models import Membership, TradePurchase, TradePurchaseLine
from app.read_cache_generation import trade_read_cache_generation
from app.services import trade_query as tq

router = APIRouter(prefix="/v1/businesses/{business_id}", tags=["dashboard"])

_DASH_MONTH_TTL_S = 22.0
_dashboard_month_cache: dict[tuple[str, str, int], tuple[float, Any]] = {}
_dashboard_month_cache_max = 128
_dashboard_month_last_good: OrderedDict[tuple[str, str, int], dict[str, Any]] = OrderedDict()
_dashboard_month_last_good_max = 128


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
    degraded: bool = False
    degraded_reason: str | None = None


def _put_dashboard_month_last_good(cache_key_d: tuple[str, str, int], data: dict[str, Any]) -> None:
    clean = dict(data)
    clean.pop("degraded", None)
    clean.pop("degraded_reason", None)
    if cache_key_d in _dashboard_month_last_good:
        del _dashboard_month_last_good[cache_key_d]
    _dashboard_month_last_good[cache_key_d] = deepcopy(clean)
    while len(_dashboard_month_last_good) > _dashboard_month_last_good_max:
        _dashboard_month_last_good.popitem(last=False)


def _degraded_month_response(cache_key_d: tuple[str, str, int], valid_month_label: str) -> DashboardOut:
    lg = _dashboard_month_last_good.get(cache_key_d)
    if lg:
        out = DashboardOut(**lg)
    else:
        out = DashboardOut(
            month=valid_month_label,
            total_purchase=0.0,
            total_paid=0.0,
            pending=0.0,
            total_profit=0.0,
            purchase_count=0,
            categories=[],
            items=[],
        )
    return out.model_copy(update={"degraded": True, "degraded_reason": "read_budget_exceeded"})


async def _compute_month_dashboard_payload(
    db: AsyncSession,
    business_id: uuid.UUID,
    y: int,
    m: int,
) -> DashboardOut:
    start = date(y, m, 1)
    last = calendar.monthrange(y, m)[1]
    end = date(y, m, last)

    tp_f = (
        TradePurchase.business_id == business_id,
        TradePurchase.purchase_date >= start,
        TradePurchase.purchase_date <= end,
        TradePurchase.status != "cancelled",
    )

    r = await execute_with_retry(
        lambda: db.execute(
            select(
                func.coalesce(func.sum(TradePurchase.total_amount), 0.0),
                func.coalesce(func.sum(TradePurchase.paid_amount), 0.0),
                func.count(TradePurchase.id),
            ).where(*tp_f)
        )
    )
    tot, paid, n = r.one()
    tot_f = float(tot or 0)
    paid_f = float(paid or 0)
    pending = max(0.0, tot_f - paid_f)

    pr = await execute_with_retry(
        lambda: db.execute(
            select(func.coalesce(func.sum(tq.trade_line_profit_expr()), 0.0))
            .select_from(TradePurchaseLine)
            .join(TradePurchase, TradePurchase.id == TradePurchaseLine.trade_purchase_id)
            .where(*tp_f)
        )
    )
    line_profit = float(pr.scalar() or 0)

    amt = tq.trade_line_amount_expr()
    prof = tq.trade_line_profit_expr()
    ir = await execute_with_retry(
        lambda: db.execute(
            select(
                TradePurchaseLine.item_name,
                func.coalesce(func.sum(amt), 0.0).label("spend"),
                func.coalesce(func.sum(prof), 0.0).label("pf"),
                func.coalesce(func.sum(TradePurchaseLine.qty), 0.0).label("tq"),
            )
            .select_from(TradePurchaseLine)
            .join(TradePurchase, TradePurchase.id == TradePurchaseLine.trade_purchase_id)
            .where(*tp_f)
            .group_by(TradePurchaseLine.item_name)
            .order_by(func.sum(amt).desc())
            .limit(20)
        )
    )
    items: list[DashboardItemSlice] = []
    for row in ir.all():
        name, sp, pf, tq_row = str(row[0]), float(row[1] or 0), float(row[2] or 0), float(row[3] or 0)
        items.append(DashboardItemSlice(name=name, amount=sp, profit=pf, total_qty=tq_row))

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
    month_key = month.strip()
    gen = trade_read_cache_generation(business_id)
    cache_key_d = (str(business_id), month_key, gen)
    mono0 = monotonic()
    dash_hit = _dashboard_month_cache.get(cache_key_d)
    if dash_hit is not None and mono0 - dash_hit[0] <= _DASH_MONTH_TTL_S:
        return dash_hit[1]

    y, m = int(parts[0]), int(parts[1])

    async def compute() -> DashboardOut:
        return await _compute_month_dashboard_payload(db, business_id, y, m)

    ok, maybe = await run_read_budget_bounded(compute)
    if not ok or maybe is None:
        out = _degraded_month_response(cache_key_d, month_key)
        _dashboard_month_cache[cache_key_d] = (monotonic(), out)
        if len(_dashboard_month_cache) > _dashboard_month_cache_max:
            _dashboard_month_cache.clear()
        return out
    sto = maybe.model_dump()
    sto["degraded"] = False
    sto["degraded_reason"] = None
    out = DashboardOut(**sto)
    _put_dashboard_month_last_good(cache_key_d, sto)
    _dashboard_month_cache[cache_key_d] = (monotonic(), out)
    if len(_dashboard_month_cache) > _dashboard_month_cache_max:
        _dashboard_month_cache.clear()
    return out
