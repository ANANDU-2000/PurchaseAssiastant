"""Deterministic SQL report snippets for WhatsApp (no LLM for numbers)."""

from __future__ import annotations

import uuid
from datetime import date, datetime, timedelta, timezone

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Broker, Entry, EntryLineItem, Supplier


def ist_today_date() -> date:
    ist = datetime.now(timezone.utc) + timedelta(hours=5, minutes=30)
    return ist.date()


def date_range_to_bounds(dr: str | None) -> tuple[date, date]:
    """today | week | month → inclusive from,to in IST calendar."""
    today = ist_today_date()
    d = (dr or "month").lower().strip()
    if d in ("today", "day"):
        return today, today
    if d == "week":
        wd = today.weekday()
        start = today - timedelta(days=wd)
        return start, today
    if d in ("month", "mtd"):
        return date(today.year, today.month, 1), today
    return date(today.year, today.month, 1), today


async def format_item_profit(
    db: AsyncSession,
    business_id: uuid.UUID,
    item_fragment: str,
    from_date: date,
    to_date: date,
) -> str:
    frag = item_fragment.strip()
    like = f"%{frag}%"
    bf = (
        Entry.business_id == business_id,
        Entry.entry_date >= from_date,
        Entry.entry_date <= to_date,
    )
    r = await db.execute(
        select(
            func.count(EntryLineItem.id),
            func.coalesce(func.sum(EntryLineItem.profit), 0),
            func.coalesce(func.avg(EntryLineItem.landing_cost), 0),
            func.coalesce(func.avg(EntryLineItem.selling_price), 0),
        )
        .select_from(EntryLineItem)
        .join(Entry, Entry.id == EntryLineItem.entry_id)
        .where(*bf, EntryLineItem.item_name.ilike(like))
    )
    row = r.one()
    n, tprofit, avgl, avgs = int(row[0] or 0), float(row[1] or 0), float(row[2] or 0), float(row[3] or 0)
    if n == 0:
        return f'No lines for “{frag}” in this period. Check spelling or add purchases.'
    return (
        f"*{frag}* ({from_date} → {to_date})\n"
        f"Lines: {n}\n"
        f"Avg landing: ₹{avgl:,.2f}\n"
        f"Avg selling: ₹{avgs:,.2f}\n"
        f"Total profit: ₹{tprofit:,.2f}"
    )


async def format_best_supplier_mtd(
    db: AsyncSession,
    business_id: uuid.UUID,
) -> str:
    today = ist_today_date()
    start = date(today.year, today.month, 1)
    bf = (
        Entry.business_id == business_id,
        Entry.entry_date >= start,
        Entry.entry_date <= today,
        Entry.supplier_id.isnot(None),
    )
    r = await db.execute(
        select(Supplier.name, func.coalesce(func.sum(EntryLineItem.profit), 0).label("tp"))
        .select_from(Supplier)
        .join(Entry, Entry.supplier_id == Supplier.id)
        .join(EntryLineItem, EntryLineItem.entry_id == Entry.id)
        .where(*bf)
        .group_by(Supplier.id, Supplier.name)
        .order_by(func.coalesce(func.sum(EntryLineItem.profit), 0).desc())
        .limit(1)
    )
    row = r.first()
    if not row or float(row[1] or 0) == 0:
        return "*Best supplier (MTD)*\n_No purchases with a supplier this month yet._"
    name, tp = row[0], float(row[1] or 0)
    return f"*Top supplier (this month)*\n*{name}* — profit ₹{tp:,.0f}"


async def format_broker_commission_mtd(
    db: AsyncSession,
    business_id: uuid.UUID,
    from_date: date,
    to_date: date,
) -> str:
    bf = (
        Entry.business_id == business_id,
        Entry.entry_date >= from_date,
        Entry.entry_date <= to_date,
        Entry.broker_id.isnot(None),
    )
    r = await db.execute(
        select(Broker.name, func.coalesce(func.sum(Entry.commission_amount), 0))
        .select_from(Entry)
        .join(Broker, Broker.id == Entry.broker_id)
        .where(*bf)
        .group_by(Broker.id, Broker.name)
        .order_by(func.coalesce(func.sum(Entry.commission_amount), 0).desc())
        .limit(5)
    )
    rows = r.all()
    if not rows:
        return "No broker-linked entries in this period."
    lines = [f"• *{name}* — commission total ₹{float(amt or 0):,.2f}" for name, amt in rows]
    return "*Brokers (commission on entries)*\n" + "\n".join(lines)


async def format_today_summary(db: AsyncSession, business_id: uuid.UUID) -> str:
    today = ist_today_date()
    bf = (Entry.business_id == business_id, Entry.entry_date == today)
    purchase = await db.execute(
        select(func.coalesce(func.sum(EntryLineItem.qty * EntryLineItem.buy_price), 0))
        .select_from(EntryLineItem)
        .join(Entry, Entry.id == EntryLineItem.entry_id)
        .where(*bf)
    )
    profit = await db.execute(
        select(func.coalesce(func.sum(EntryLineItem.profit), 0))
        .select_from(EntryLineItem)
        .join(Entry, Entry.id == EntryLineItem.entry_id)
        .where(*bf)
    )
    p = float(purchase.scalar() or 0)
    pr = float(profit.scalar() or 0)
    margin = (pr / p * 100) if p > 0 else 0.0
    return (
        f"📅 *Today*\n_{today.strftime('%b %d, %Y')}_\n\n"
        f"🛒 Purchase: ₹{p:,.0f}\n"
        f"📈 Profit: ₹{pr:,.0f} ({margin:.1f}%)\n\n"
        f"{'✅ Good margin!' if margin > 10 else '⚠️ Low margin — check your costs'}"
    )


async def format_month_summary(db: AsyncSession, business_id: uuid.UUID) -> str:
    today = ist_today_date()
    start = date(today.year, today.month, 1)
    bf = (
        Entry.business_id == business_id,
        Entry.entry_date >= start,
        Entry.entry_date <= today,
    )
    purchase = await db.execute(
        select(func.coalesce(func.sum(EntryLineItem.qty * EntryLineItem.buy_price), 0))
        .select_from(EntryLineItem)
        .join(Entry, Entry.id == EntryLineItem.entry_id)
        .where(*bf)
    )
    profit = await db.execute(
        select(func.coalesce(func.sum(EntryLineItem.profit), 0))
        .select_from(EntryLineItem)
        .join(Entry, Entry.id == EntryLineItem.entry_id)
        .where(*bf)
    )
    p = float(purchase.scalar() or 0)
    pr = float(profit.scalar() or 0)
    margin = (pr / p * 100) if p > 0 else 0.0
    return (
        f"📊 *This Month Overview*\n"
        f"_{start.strftime('%b %d')} → {today.strftime('%b %d, %Y')}_\n\n"
        f"🛒 Purchase: ₹{p:,.0f}\n"
        f"📈 Profit: ₹{pr:,.0f} ({margin:.1f}%)\n\n"
        f"{'✅ Good margin!' if margin > 10 else '⚠️ Low margin — check your costs'}"
    )


async def format_best_supplier_for_item_mtd(
    db: AsyncSession,
    business_id: uuid.UUID,
    item_fragment: str,
) -> str:
    frag = item_fragment.strip()
    if len(frag) < 2:
        return "Send: *best rice* (item name) to see which supplier did best on that item."
    today = ist_today_date()
    start = date(today.year, today.month, 1)
    bf = (
        Entry.business_id == business_id,
        Entry.entry_date >= start,
        Entry.entry_date <= today,
        Entry.supplier_id.isnot(None),
    )
    like = f"%{frag}%"
    q = await db.execute(
        select(Supplier.name, func.coalesce(func.sum(EntryLineItem.profit), 0).label("tp"))
        .select_from(Supplier)
        .join(Entry, Entry.supplier_id == Supplier.id)
        .join(EntryLineItem, EntryLineItem.entry_id == Entry.id)
        .where(*bf, EntryLineItem.item_name.ilike(like))
        .group_by(Supplier.id, Supplier.name)
        .order_by(func.coalesce(func.sum(EntryLineItem.profit), 0).desc())
        .limit(1)
    )
    row = q.first()
    if not row or float(row[1] or 0) == 0:
        return (
            f"🔍 *Best supplier for “{frag}”*\n"
            f"_No matching lines this month — check spelling or add purchases._"
        )
    name, tp = row[0], float(row[1] or 0)
    return f"🔍 *Best for “{frag}”*\n*{name}* — profit ₹{tp:,.0f} (this month)"


async def format_supplier_compare_top2(
    db: AsyncSession,
    business_id: uuid.UUID,
    item_fragment: str,
    from_date: date,
    to_date: date,
) -> str:
    frag = item_fragment.strip()
    like = f"%{frag}%"
    bf = (
        Entry.business_id == business_id,
        Entry.entry_date >= from_date,
        Entry.entry_date <= to_date,
        Entry.supplier_id.isnot(None),
    )
    r = await db.execute(
        select(Supplier.name, func.coalesce(func.sum(EntryLineItem.profit), 0).label("tp"))
        .select_from(Supplier)
        .join(Entry, Entry.supplier_id == Supplier.id)
        .join(EntryLineItem, EntryLineItem.entry_id == Entry.id)
        .where(*bf, EntryLineItem.item_name.ilike(like))
        .group_by(Supplier.id, Supplier.name)
        .order_by(func.coalesce(func.sum(EntryLineItem.profit), 0).desc())
        .limit(2)
    )
    rows = r.all()
    if len(rows) < 1:
        return f'No supplier data for “{frag}” in this range.'
    a, b = rows[0], (rows[1] if len(rows) > 1 else None)
    out = f"*Suppliers for {frag}* ({from_date} → {to_date})\n"
    out += f"1) *{a[0]}* — profit ₹{float(a[1] or 0):,.0f}\n"
    if b:
        out += f"2) *{b[0]}* — profit ₹{float(b[1] or 0):,.0f}\n"
    return out
