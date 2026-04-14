"""Compact month-to-date aggregates for LLM context (no PII beyond business totals)."""

from __future__ import annotations

import uuid
from datetime import date

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Entry, EntryLineItem, Supplier
from app.services.entry_intent_resolution import ist_today


async def build_compact_business_snapshot(
    db: AsyncSession,
    business_id: uuid.UUID,
) -> str:
    """
    Short factual block: MTD purchases, profit, entry count, top items, best supplier.
    Used as database context for intent extraction and optional report synthesis.
    """
    today = ist_today()
    fd = date(today.year, today.month, 1)
    td = today
    bf = (
        Entry.business_id == business_id,
        Entry.entry_date >= fd,
        Entry.entry_date <= td,
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
    cnt = await db.execute(select(func.count(Entry.id.distinct())).where(*bf))
    total_purchase = float(purchase.scalar() or 0)
    total_profit = float(profit.scalar() or 0)
    purchase_count = int(cnt.scalar() or 0)

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
        .limit(3)
    )
    top_rows = (await db.execute(q_top)).all()

    q_best_sup = (
        select(
            Supplier.name,
            func.coalesce(func.sum(EntryLineItem.profit), 0).label("tp"),
        )
        .select_from(Entry)
        .join(EntryLineItem, EntryLineItem.entry_id == Entry.id)
        .join(Supplier, Supplier.id == Entry.supplier_id)
        .where(*bf, Entry.supplier_id.isnot(None))
        .group_by(Supplier.id, Supplier.name)
        .order_by(func.coalesce(func.sum(EntryLineItem.profit), 0).desc())
        .limit(1)
    )
    bs = await db.execute(q_best_sup)
    bs_row = bs.first()

    lines = [
        f"Month to date ({fd.isoformat()} to {td.isoformat()}): "
        f"purchases Rs.{total_purchase:,.0f}, profit Rs.{total_profit:,.0f}, {purchase_count} entries."
    ]
    if top_rows:
        parts = [f"{r[0]} (Rs.{float(r[1]):,.0f})" for r in top_rows if r[0]]
        lines.append("Top items by profit: " + ", ".join(parts) + ".")
    if bs_row:
        lines.append(
            f"Best supplier by profit: {bs_row[0]} (Rs.{float(bs_row[1] or 0):,.0f})."
        )
    return "\n".join(lines)
