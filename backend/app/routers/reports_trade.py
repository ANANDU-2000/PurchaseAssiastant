"""Reports sourced from trade_purchases (new wholesale flow)."""

from __future__ import annotations

import uuid
from datetime import date
from typing import Annotated

from fastapi import APIRouter, Depends, Query
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.deps import get_current_user, require_membership
from app.models import Membership, TradePurchase, User

router = APIRouter(prefix="/v1/businesses/{business_id}/reports", tags=["reports-trade"])


@router.get("/trade-summary")
async def trade_purchase_summary(
    business_id: uuid.UUID,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
    date_from: date | None = Query(None, alias="from"),
    date_to: date | None = Query(None, alias="to"),
    supplier_id: uuid.UUID | None = Query(None),
):
    del user
    q = select(
        func.count(TradePurchase.id).label("deals"),
        func.coalesce(func.sum(TradePurchase.total_amount), 0).label("total_purchase"),
        func.coalesce(func.sum(TradePurchase.total_qty), 0).label("total_qty"),
    ).where(TradePurchase.business_id == business_id)
    if date_from:
        q = q.where(TradePurchase.purchase_date >= date_from)
    if date_to:
        q = q.where(TradePurchase.purchase_date <= date_to)
    if supplier_id:
        q = q.where(TradePurchase.supplier_id == supplier_id)
    m = (await db.execute(q)).mappings().one()
    deals = int(m["deals"] or 0)
    total_purchase = float(m["total_purchase"] or 0)
    total_qty = float(m["total_qty"] or 0)
    avg_cost = (total_purchase / total_qty) if total_qty > 0 else 0.0
    return {
        "deals": deals,
        "total_purchase": total_purchase,
        "total_qty": total_qty,
        "avg_cost": avg_cost,
    }
