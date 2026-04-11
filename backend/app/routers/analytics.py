import uuid
from datetime import date
from typing import Annotated

from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.deps import require_membership
from app.models import Broker, Entry, EntryLineItem, Membership, Supplier

router = APIRouter(prefix="/v1/businesses/{business_id}/analytics", tags=["analytics"])


class AnalyticsSummary(BaseModel):
    total_purchase: float
    total_qty_base: float
    total_profit: float
    purchase_count: int
    base_unit_label: str = "kg"


@router.get("/summary", response_model=AnalyticsSummary)
async def analytics_summary(
    business_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
    from_date: date = Query(..., alias="from"),
    to_date: date = Query(..., alias="to"),
):
    del _m
    base_filter = (
        Entry.business_id == business_id,
        Entry.entry_date >= from_date,
        Entry.entry_date <= to_date,
    )
    purchase = await db.execute(
        select(func.coalesce(func.sum(EntryLineItem.qty * EntryLineItem.buy_price), 0))
        .select_from(EntryLineItem)
        .join(Entry, Entry.id == EntryLineItem.entry_id)
        .where(*base_filter)
    )
    profit = await db.execute(
        select(func.coalesce(func.sum(EntryLineItem.profit), 0))
        .select_from(EntryLineItem)
        .join(Entry, Entry.id == EntryLineItem.entry_id)
        .where(*base_filter)
    )
    qty = await db.execute(
        select(func.coalesce(func.sum(func.coalesce(EntryLineItem.qty_base, EntryLineItem.qty)), 0))
        .select_from(EntryLineItem)
        .join(Entry, Entry.id == EntryLineItem.entry_id)
        .where(*base_filter)
    )
    cnt = await db.execute(
        select(func.count(Entry.id.distinct())).where(*base_filter)
    )
    return AnalyticsSummary(
        total_purchase=float(purchase.scalar() or 0),
        total_qty_base=float(qty.scalar() or 0),
        total_profit=float(profit.scalar() or 0),
        purchase_count=int(cnt.scalar() or 0),
    )


def _date_filter(business_id: uuid.UUID, from_date: date, to_date: date):
    return (
        Entry.business_id == business_id,
        Entry.entry_date >= from_date,
        Entry.entry_date <= to_date,
    )


class HomeInsightAlert(BaseModel):
    code: str
    message: str
    severity: str = "info"


class HomeInsights(BaseModel):
    top_item: str | None = None
    top_item_profit: float | None = None
    alerts: list[HomeInsightAlert]


@router.get("/insights", response_model=HomeInsights)
async def home_insights(
    business_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
    from_date: date = Query(..., alias="from"),
    to_date: date = Query(..., alias="to"),
):
    del _m
    bf = _date_filter(business_id, from_date, to_date)
    # Top item by total profit
    q_top = (
        select(
            EntryLineItem.item_name,
            func.coalesce(func.sum(EntryLineItem.profit), 0).label("tp"),
        )
        .select_from(EntryLineItem)
        .join(Entry, Entry.id == EntryLineItem.entry_id)
        .where(*bf)
        .group_by(EntryLineItem.item_name)
        .order_by(func.coalesce(func.sum(EntryLineItem.profit), 0).desc())
        .limit(1)
    )
    top = await db.execute(q_top)
    row = top.first()
    top_name = row[0] if row else None
    top_profit = float(row[1]) if row else None

    alerts: list[HomeInsightAlert] = []
    neg = await db.execute(
        select(func.count(EntryLineItem.id))
        .select_from(EntryLineItem)
        .join(Entry, Entry.id == EntryLineItem.entry_id)
        .where(*bf, EntryLineItem.profit < 0)
    )
    if int(neg.scalar() or 0) > 0:
        alerts.append(
            HomeInsightAlert(
                code="negative_profit_lines",
                message="Some lines show negative profit in this period.",
                severity="warning",
            )
        )
    return HomeInsights(top_item=top_name, top_item_profit=top_profit, alerts=alerts)


class ItemAnalyticsRow(BaseModel):
    item_name: str
    total_qty: float
    avg_landing: float
    total_profit: float
    line_count: int


@router.get("/items", response_model=list[ItemAnalyticsRow])
async def analytics_items(
    business_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
    from_date: date = Query(..., alias="from"),
    to_date: date = Query(..., alias="to"),
):
    del _m
    bf = _date_filter(business_id, from_date, to_date)
    q = (
        select(
            EntryLineItem.item_name,
            func.coalesce(func.sum(EntryLineItem.qty), 0).label("tq"),
            func.coalesce(func.avg(EntryLineItem.landing_cost), 0).label("al"),
            func.coalesce(func.sum(EntryLineItem.profit), 0).label("tp"),
            func.count(EntryLineItem.id).label("lc"),
        )
        .select_from(EntryLineItem)
        .join(Entry, Entry.id == EntryLineItem.entry_id)
        .where(*bf)
        .group_by(EntryLineItem.item_name)
        .order_by(func.coalesce(func.sum(EntryLineItem.profit), 0).desc())
    )
    r = await db.execute(q)
    return [
        ItemAnalyticsRow(
            item_name=row[0],
            total_qty=float(row[1] or 0),
            avg_landing=float(row[2] or 0),
            total_profit=float(row[3] or 0),
            line_count=int(row[4] or 0),
        )
        for row in r.all()
    ]


class CategoryAnalyticsRow(BaseModel):
    category: str
    total_profit: float
    total_qty: float
    line_count: int


@router.get("/categories", response_model=list[CategoryAnalyticsRow])
async def analytics_categories(
    business_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
    from_date: date = Query(..., alias="from"),
    to_date: date = Query(..., alias="to"),
):
    del _m
    bf = _date_filter(business_id, from_date, to_date)
    q = (
        select(
            func.coalesce(EntryLineItem.category, "Uncategorized").label("cat"),
            func.coalesce(func.sum(EntryLineItem.profit), 0).label("tp"),
            func.coalesce(func.sum(EntryLineItem.qty), 0).label("tq"),
            func.count(EntryLineItem.id).label("lc"),
        )
        .select_from(EntryLineItem)
        .join(Entry, Entry.id == EntryLineItem.entry_id)
        .where(*bf)
        .group_by(func.coalesce(EntryLineItem.category, "Uncategorized"))
        .order_by(func.coalesce(func.sum(EntryLineItem.profit), 0).desc())
    )
    r = await db.execute(q)
    return [
        CategoryAnalyticsRow(
            category=row[0],
            total_profit=float(row[1] or 0),
            total_qty=float(row[2] or 0),
            line_count=int(row[3] or 0),
        )
        for row in r.all()
    ]


class SupplierAnalyticsRow(BaseModel):
    supplier_id: uuid.UUID
    supplier_name: str
    deals: int
    avg_landing: float
    total_qty: float
    total_profit: float


@router.get("/suppliers", response_model=list[SupplierAnalyticsRow])
async def analytics_suppliers(
    business_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
    from_date: date = Query(..., alias="from"),
    to_date: date = Query(..., alias="to"),
):
    del _m
    bf = _date_filter(business_id, from_date, to_date)
    q = (
        select(
            Supplier.id,
            Supplier.name,
            func.count(Entry.id.distinct()).label("deals"),
            func.coalesce(func.avg(EntryLineItem.landing_cost), 0).label("al"),
            func.coalesce(func.sum(EntryLineItem.qty), 0).label("tq"),
            func.coalesce(func.sum(EntryLineItem.profit), 0).label("tp"),
        )
        .select_from(Entry)
        .join(EntryLineItem, EntryLineItem.entry_id == Entry.id)
        .join(Supplier, Supplier.id == Entry.supplier_id)
        .where(*bf, Entry.supplier_id.isnot(None))
        .group_by(Supplier.id, Supplier.name)
        .order_by(func.coalesce(func.sum(EntryLineItem.profit), 0).desc())
    )
    r = await db.execute(q)
    return [
        SupplierAnalyticsRow(
            supplier_id=row[0],
            supplier_name=row[1],
            deals=int(row[2] or 0),
            avg_landing=float(row[3] or 0),
            total_qty=float(row[4] or 0),
            total_profit=float(row[5] or 0),
        )
        for row in r.all()
    ]


class BrokerAnalyticsRow(BaseModel):
    broker_id: uuid.UUID
    broker_name: str
    deals: int
    total_commission: float
    total_profit: float


@router.get("/brokers", response_model=list[BrokerAnalyticsRow])
async def analytics_brokers(
    business_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
    from_date: date = Query(..., alias="from"),
    to_date: date = Query(..., alias="to"),
):
    del _m
    bf = _date_filter(business_id, from_date, to_date)
    q = (
        select(
            Broker.id,
            Broker.name,
            func.count(Entry.id.distinct()).label("deals"),
            func.coalesce(func.sum(Entry.commission_amount), 0).label("tc"),
            func.coalesce(func.sum(EntryLineItem.profit), 0).label("tp"),
        )
        .select_from(Entry)
        .join(EntryLineItem, EntryLineItem.entry_id == Entry.id)
        .join(Broker, Broker.id == Entry.broker_id)
        .where(*bf, Entry.broker_id.isnot(None))
        .group_by(Broker.id, Broker.name)
        .order_by(func.coalesce(func.sum(EntryLineItem.profit), 0).desc())
    )
    r = await db.execute(q)
    return [
        BrokerAnalyticsRow(
            broker_id=row[0],
            broker_name=row[1],
            deals=int(row[2] or 0),
            total_commission=float(row[3] or 0),
            total_profit=float(row[4] or 0),
        )
        for row in r.all()
    ]
