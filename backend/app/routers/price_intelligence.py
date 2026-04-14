import math
import uuid
from collections import defaultdict
from datetime import date, datetime, timedelta
from typing import Annotated

from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel
from sqlalchemy import and_, func, select
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
    # Daily avg price for charts (oldest → newest); thinned for large windows
    price_history: list[dict] = []


@router.get("", response_model=PriceIntelligence)
async def price_intelligence(
    business_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
    item: str = Query(..., min_length=1),
    current_price: float | None = None,
    window_days: int = Query(90, ge=1, le=365),
    price_field: str = Query("landing", pattern="^(landing|selling)$"),
):
    del _m
    needle = item.strip().lower()
    start = date.today() - timedelta(days=window_days)

    price_col = EntryLineItem.landing_cost if price_field == "landing" else EntryLineItem.selling_price

    line_filters = [
        Entry.business_id == business_id,
        Entry.entry_date >= start,
        func.lower(EntryLineItem.item_name).contains(needle),
    ]
    if price_field == "selling":
        line_filters.append(EntryLineItem.selling_price.isnot(None))

    hist = await db.execute(
        select(price_col)
        .select_from(EntryLineItem)
        .join(Entry, Entry.id == EntryLineItem.entry_id)
        .where(and_(*line_filters))
    )
    landings = [float(x[0]) for x in hist.all() if x[0] is not None]
    if not landings:
        return PriceIntelligence(
            item=item,
            confidence=0.0,
            decision_hints=[
                f"No {'selling' if price_field == 'selling' else 'landing'} history for this item in the selected window."
            ],
            price_history=[],
        )

    avg = sum(landings) / len(landings)
    high = max(landings)
    low = min(landings)
    frequency = len(landings)

    dated_rows = await db.execute(
        select(Entry.entry_date, price_col)
        .select_from(Entry)
        .join(EntryLineItem, EntryLineItem.entry_id == Entry.id)
        .where(and_(*line_filters))
        .order_by(Entry.entry_date.asc())
    )
    ordered = [(r[0], float(r[1])) for r in dated_rows.all()]
    last_price = ordered[-1][1] if ordered else None

    by_day: dict[date, list[float]] = defaultdict(list)
    for ed, price in ordered:
        d: date = ed.date() if isinstance(ed, datetime) else ed
        by_day[d].append(price)
    daily_series: list[dict] = []
    for d in sorted(by_day.keys()):
        vals = by_day[d]
        daily_series.append({"d": d.isoformat(), "p": round(sum(vals) / len(vals), 4)})
    max_pts = 42
    if len(daily_series) > max_pts:
        step = max(1, math.ceil(len(daily_series) / max_pts))
        daily_series = daily_series[::step]
    price_history = daily_series

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
            func.avg(price_col).label("avg_l"),
            func.count(EntryLineItem.id).label("deals"),
            func.coalesce(func.sum(EntryLineItem.profit), 0).label("profit_sum"),
        )
        .select_from(EntryLineItem)
        .join(Entry, Entry.id == EntryLineItem.entry_id)
        .join(Supplier, Supplier.id == Entry.supplier_id)
        .where(and_(*line_filters))
        .group_by(Supplier.id, Supplier.name)
    )
    sr = await db.execute(sq)
    raw_rows = sr.all()
    total_profit_all = sum(float(row[4] or 0) for row in raw_rows)
    supplier_compare: list[dict] = []
    for row in raw_rows:
        pid, name, avg_l, deals, psum = row[0], row[1], row[2], row[3], row[4]
        fp = float(psum or 0)
        share = (fp / total_profit_all * 100.0) if total_profit_all > 0 else None
        supplier_compare.append(
            {
                "supplier_id": str(pid),
                "name": name,
                "avg_landing": float(avg_l or 0),
                "deals": int(deals or 0),
                "total_profit": round(fp, 2),
                "profit_share_pct": round(share, 1) if share is not None else None,
            }
        )
    supplier_compare.sort(key=lambda x: x["avg_landing"])

    hints: list[str] = []
    label = "landing" if price_field == "landing" else "selling"
    if current_price is not None:
        if current_price > avg * 1.05:
            hints.append(f"Current {label} is above your recent average.")
        elif current_price < avg * 0.95:
            hints.append(f"Current {label} is below your recent average.")
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
        price_history=price_history,
    )
