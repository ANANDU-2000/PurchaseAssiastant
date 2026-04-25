"""Compact month-to-date aggregates for LLM context (no PII beyond business totals)."""

from __future__ import annotations

import uuid
from datetime import date

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Entry, EntryLineItem, Supplier, TradePurchase, TradePurchaseLine
from app.services.entry_intent_resolution import ist_today
from app.services import trade_query as tq


async def build_compact_business_snapshot(
    db: AsyncSession,
    business_id: uuid.UUID,
) -> str:
    """
    Trade (wholesale) first — same line rules as /reports/trade-*.
    Legacy Entry block only if that flow has MTD activity (avoids misleading empty lines).
    """
    today = ist_today()
    fd = date(today.year, today.month, 1)
    td = today

    parts: list[str] = [
        "=== TRADE PURCHASES (authoritative for PUR-*, wholesale, app trade reports) ===",
    ]
    trade_block = await _build_compact_trade_mtd(db, business_id, fd, td)
    if trade_block:
        parts.append(trade_block)
    else:
        parts.append("No trade purchase activity month-to-date (report statuses).")

    legacy = await _build_legacy_entry_mtd_block(db, business_id, fd, td)
    if legacy:
        parts.append("")
        parts.append("=== LEGACY ENTRIES (older retail flow — not line-based trade) ===")
        parts.append(legacy)

    return "\n".join(parts)


async def _build_legacy_entry_mtd_block(
    db: AsyncSession, business_id: uuid.UUID, fd: date, td: date
) -> str:
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
    if (
        purchase_count == 0
        and total_purchase < 1e-6
        and total_profit < 1e-6
    ):
        return ""

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

    lines: list[str] = [
        f"Month to date ({fd.isoformat()} to {td.isoformat()}): "
        f"purchases Rs.{total_purchase:,.0f}, profit Rs.{total_profit:,.0f}, {purchase_count} entries."
    ]
    if top_rows:
        p = [f"{r[0]} (Rs.{float(r[1]):,.0f})" for r in top_rows if r[0]]
        lines.append("Top items by profit: " + ", ".join(p) + ".")
    if bs_row:
        lines.append(
            f"Best supplier by profit: {bs_row[0]} (Rs.{float(bs_row[1] or 0):,.0f})."
        )
    return "\n".join(lines)


async def _build_compact_trade_mtd(
    db: AsyncSession, business_id: uuid.UUID, fd: date, td: date
) -> str:
    amt = tq.trade_line_amount_expr()
    bf = tq.trade_purchase_date_filter(business_id, fd, td)
    row = (
        await db.execute(
            select(
                func.count(func.distinct(TradePurchase.id)).label("deals"),
                func.coalesce(func.sum(amt), 0.0).label("line_spend"),
                func.coalesce(func.sum(TradePurchaseLine.qty), 0.0).label("line_qty"),
            )
            .select_from(TradePurchaseLine)
            .join(TradePurchase, TradePurchase.id == TradePurchaseLine.trade_purchase_id)
            .where(bf)
        )
    ).mappings().one()
    deals = int(row["deals"] or 0)
    spend = float(row["line_spend"] or 0)
    tqty = float(row["line_qty"] or 0)
    if deals == 0 and spend < 1e-6:
        return ""
    top_q = (
        select(
            TradePurchaseLine.item_name,
            func.coalesce(func.sum(amt), 0.0).label("tp"),
        )
        .select_from(TradePurchaseLine)
        .join(TradePurchase, TradePurchase.id == TradePurchaseLine.trade_purchase_id)
        .where(bf)
        .group_by(TradePurchaseLine.item_name)
        .order_by(func.coalesce(func.sum(amt), 0.0).desc())
        .limit(3)
    )
    top_tr = (await db.execute(top_q)).all()
    parts: list[str] = [
        f"Trade purchases (line amounts): {deals} deals, Rs.{spend:,.0f} spend, {tqty:,.0f} qty total."
    ]
    if top_tr:
        top_parts = [f"{r[0] or '—'} (Rs.{float(r[1] or 0):,.0f})" for r in top_tr if r[0]]
        if top_parts:
            parts.append("Top items by line spend: " + ", ".join(top_parts) + ".")
    return " ".join(parts)
