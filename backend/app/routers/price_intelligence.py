import uuid
from datetime import date, timedelta
from typing import Annotated

from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.deps import require_membership
from app.models import Entry, EntryLineItem, Membership, Supplier

router = APIRouter(prefix="/v1/businesses/{business_id}/price-intelligence", tags=["price-intelligence"])


class PriceIntelligence(BaseModel):
    item: str
    avg: float | None = None
    high: float | None = None
    low: float | None = None
    trend: str = "flat"
    position_pct: float | None = None
    last_price: float | None = None
    frequency: int = 0
    confidence: float = 0.0
    supplier_compare: list[dict] = []
    decision_hints: list[str] = []


@router.get("", response_model=PriceIntelligence)
async def price_intelligence(
    business_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
    item: str = Query(..., min_length=1),
    current_price: float | None = None,
    window_days: int = Query(90, ge=1, le=365),
):
    del _m
    needle = item.strip().lower()
    start = date.today() - timedelta(days=window_days)

    hist = await db.execute(
        select(EntryLineItem.landing_cost)
        .join(Entry, Entry.id == EntryLineItem.entry_id)
        .where(
            Entry.business_id == business_id,
            Entry.entry_date >= start,
            func.lower(EntryLineItem.item_name).contains(needle),
        )
    )
    landings = [float(x[0]) for x in hist.all()]
    if not landings:
        return PriceIntelligence(item=item, confidence=0.0, decision_hints=["No history for this item in the selected window."])

    avg = sum(landings) / len(landings)
    high = max(landings)
    low = min(landings)
    frequency = len(landings)

    dated_rows = await db.execute(
        select(Entry.entry_date, EntryLineItem.landing_cost)
        .join(EntryLineItem, EntryLineItem.entry_id == Entry.id)
        .where(
            Entry.business_id == business_id,
            Entry.entry_date >= start,
            func.lower(EntryLineItem.item_name).contains(needle),
        )
        .order_by(Entry.entry_date.asc())
    )
    ordered = [(r[0], float(r[1])) for r in dated_rows.all()]
    last_price = ordered[-1][1] if ordered else None

    if len(ordered) >= 3:
        n = len(ordered)
        third = max(1, n // 3)
        old_avg = sum(x[1] for x in ordered[:third]) / third
        new_avg = sum(x[1] for x in ordered[-third:]) / third
        if new_avg > old_avg * 1.02:
            trend = "up"
        elif new_avg < old_avg * 0.98:
            trend = "down"
        else:
            trend = "flat"
    else:
        trend = "flat"

    position_pct = None
    if current_price is not None and high > low:
        position_pct = round((current_price - low) / (high - low) * 100.0, 1)

    confidence = min(1.0, frequency / 20.0)

    sq = (
        select(
            Supplier.id,
            Supplier.name,
            func.avg(EntryLineItem.landing_cost).label("avg_l"),
        )
        .select_from(EntryLineItem)
        .join(Entry, Entry.id == EntryLineItem.entry_id)
        .join(Supplier, Supplier.id == Entry.supplier_id)
        .where(
            Entry.business_id == business_id,
            Entry.entry_date >= start,
            func.lower(EntryLineItem.item_name).contains(needle),
        )
        .group_by(Supplier.id, Supplier.name)
    )
    sr = await db.execute(sq)
    supplier_compare = [
        {"supplier_id": str(row[0]), "name": row[1], "avg_landing": float(row[2] or 0)} for row in sr.all()
    ]
    supplier_compare.sort(key=lambda x: x["avg_landing"])

    hints: list[str] = []
    if current_price is not None:
        if current_price > avg * 1.05:
            hints.append("Current price is above your recent average landing.")
        elif current_price < avg * 0.95:
            hints.append("Current price is below your recent average landing.")
    if trend == "up":
        hints.append("Trend is increasing in this window.")
    elif trend == "down":
        hints.append("Trend is decreasing in this window.")

    return PriceIntelligence(
        item=item,
        avg=round(avg, 4),
        high=round(high, 4),
        low=round(low, 4),
        trend=trend,
        position_pct=position_pct,
        last_price=last_price,
        frequency=frequency,
        confidence=round(confidence, 2),
        supplier_compare=supplier_compare,
        decision_hints=hints,
    )
