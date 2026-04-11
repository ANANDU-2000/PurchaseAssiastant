"""Profit and duplicate checks — server-side only."""

from datetime import date
from decimal import Decimal
from uuid import UUID

from sqlalchemy import and_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Entry, EntryLineItem


def normalize_item(name: str) -> str:
    return " ".join(name.lower().strip().split())


def line_profit(qty: Decimal, landing: Decimal, selling: Decimal | None) -> Decimal | None:
    if selling is None:
        return None
    return (selling - landing) * qty


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
