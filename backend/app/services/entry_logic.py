"""Profit and duplicate checks — server-side only."""

from __future__ import annotations

from datetime import date
from decimal import Decimal
from uuid import UUID

from sqlalchemy import and_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Entry, EntryLineItem
from app.schemas.entries import EntryCreateRequest, EntryLineInput


def normalize_item(name: str) -> str:
    return " ".join(name.lower().strip().split())


def line_profit(qty: Decimal, landing: Decimal, selling: Decimal | None) -> Decimal | None:
    if selling is None:
        return None
    return (selling - landing) * qty


def apply_computed_landings(body: EntryCreateRequest) -> EntryCreateRequest:
    """When transport and commission are zero, keep client line landings. Otherwise split extras by line value (qty * buy_price)."""
    transport = float(body.transport_cost or 0)
    commission = float(body.commission_amount or 0)
    total_extras = transport + commission
    if total_extras <= 0:
        return body

    line_values: list[Decimal] = []
    for li in body.lines:
        q = Decimal(str(li.qty))
        b = Decimal(str(li.buy_price))
        line_values.append(q * b)

    total_val = sum(line_values)
    new_lines: list[EntryLineInput] = []

    if total_val <= 0:
        n = len(body.lines)
        share_each = Decimal(str(total_extras)) / Decimal(n) if n else Decimal(0)
        for li in body.lines:
            q = Decimal(str(li.qty))
            buy = Decimal(str(li.buy_price))
            extra_line = share_each
            landing = buy + (extra_line / q if q > 0 else extra_line)
            new_lines.append(li.model_copy(update={"landing_cost": float(landing)}))
        return body.model_copy(update={"lines": new_lines})

    te = Decimal(str(total_extras))
    for li, lv in zip(body.lines, line_values):
        q = Decimal(str(li.qty))
        buy = Decimal(str(li.buy_price))
        share = (lv / total_val) * te
        landing = buy + (share / q if q > 0 else share)
        new_lines.append(li.model_copy(update={"landing_cost": float(landing)}))
    return body.model_copy(update={"lines": new_lines})


async def entry_price_warnings(
    db: AsyncSession,
    business_id: UUID,
    body: EntryCreateRequest,
    *,
    deviation_ratio: float = 0.25,
) -> list[str]:
    """Warn when line landing deviates from historical average for the same item (normalized)."""
    r = await db.execute(
        select(EntryLineItem.landing_cost, EntryLineItem.item_name).join(
            Entry, Entry.id == EntryLineItem.entry_id
        ).where(Entry.business_id == business_id)
    )
    by_key: dict[str, list[float]] = {}
    for lc, iname in r.all():
        k = normalize_item(iname or "")
        by_key.setdefault(k, []).append(float(lc))

    warnings: list[str] = []
    for li in body.lines:
        key = normalize_item(li.item_name)
        lands = by_key.get(key)
        if not lands:
            continue
        avg = sum(lands) / len(lands)
        if avg <= 0:
            continue
        cur = float(li.landing_cost)
        dev = abs(cur - avg) / avg
        if dev >= deviation_ratio:
            warnings.append(
                f"{li.item_name}: landing {cur:.2f} is about {dev * 100:.0f}% off your "
                f"historical average ({avg:.2f}) for this item."
            )
    return warnings


async def find_duplicates(
    db: AsyncSession,
    business_id: UUID,
    item_name: str,
    qty: float,
    entry_date: date,
) -> list[UUID]:
    key = normalize_item(item_name)
    q = await db.execute(
        select(Entry.id, EntryLineItem.item_name, EntryLineItem.qty).join(
            EntryLineItem, EntryLineItem.entry_id == Entry.id
        ).where(
            and_(
                Entry.business_id == business_id,
                Entry.entry_date == entry_date,
            )
        )
    )
    out: list[UUID] = []
    for eid, iname, qtyp in q.all():
        if normalize_item(iname) == key and float(qtyp) == float(qty):
            out.append(eid)
    return out
