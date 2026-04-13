"""Safe partial updates to an existing purchase entry (used by WhatsApp confirm flow)."""

from __future__ import annotations

import uuid
from decimal import Decimal

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.models import Entry, EntryLineItem
from app.schemas.entries import EntryLineInput
from app.services.entry_logic import enrich_line_quantities, entry_line_profit


def _line_orm_to_input(li: EntryLineItem) -> EntryLineInput:
    return EntryLineInput(
        catalog_item_id=li.catalog_item_id,
        catalog_variant_id=li.catalog_variant_id,
        item_name=li.item_name or "",
        category=li.category,
        qty=float(li.qty),
        unit=str(li.unit),
        buy_price=float(li.buy_price),
        landing_cost=float(li.landing_cost),
        selling_price=float(li.selling_price) if li.selling_price is not None else None,
        bags=float(li.bags) if li.bags is not None else None,
        kg_per_bag=float(li.kg_per_bag) if li.kg_per_bag is not None else None,
        qty_kg=float(li.qty_kg) if li.qty_kg is not None else None,
        stock_note=li.stock_note,
    )


async def patch_first_line_prices(
    db: AsyncSession,
    business_id: uuid.UUID,
    entry_id: uuid.UUID,
    *,
    buy_price: float | None = None,
    landing_cost: float | None = None,
    selling_price: float | None = None,
    supplier_id: uuid.UUID | None = None,
    broker_id: uuid.UUID | None = None,
    entry_date: object | None = None,
) -> Entry | None:
    r = await db.execute(
        select(Entry)
        .where(Entry.id == entry_id, Entry.business_id == business_id)
        .options(selectinload(Entry.lines))
    )
    entry = r.scalar_one_or_none()
    if entry is None or not entry.lines:
        return None

    li = sorted(entry.lines, key=lambda x: x.id)[0]
    inp = _line_orm_to_input(li)
    upd: dict[str, object] = {}
    if buy_price is not None:
        upd["buy_price"] = buy_price
    if landing_cost is not None:
        upd["landing_cost"] = landing_cost
    if selling_price is not None:
        upd["selling_price"] = selling_price
    if not upd and supplier_id is None and broker_id is None and entry_date is None:
        return entry

    if not upd:
        if supplier_id is not None:
            entry.supplier_id = supplier_id
        if broker_id is not None:
            entry.broker_id = broker_id
        if entry_date is not None:
            from datetime import date as date_cls

            if isinstance(entry_date, date_cls):
                entry.entry_date = entry_date
        await db.commit()
        await db.refresh(entry)
        return entry

    new_inp = inp.model_copy(update=upd)
    new_inp = enrich_line_quantities(new_inp)
    prof = entry_line_profit(new_inp)

    if buy_price is not None:
        li.buy_price = Decimal(str(buy_price))
    if landing_cost is not None:
        li.landing_cost = Decimal(str(landing_cost))
    if selling_price is not None:
        li.selling_price = Decimal(str(selling_price)) if selling_price is not None else None
    elif "selling_price" in upd and upd["selling_price"] is None:
        li.selling_price = None

    li.qty = Decimal(str(new_inp.qty))
    li.qty_kg = Decimal(str(new_inp.qty_kg)) if new_inp.qty_kg is not None else None
    li.bags = Decimal(str(new_inp.bags)) if new_inp.bags is not None else None
    li.kg_per_bag = Decimal(str(new_inp.kg_per_bag)) if new_inp.kg_per_bag is not None else None
    li.profit = prof

    if supplier_id is not None:
        entry.supplier_id = supplier_id
    if broker_id is not None:
        entry.broker_id = broker_id
    if entry_date is not None:
        from datetime import date as date_cls

        if isinstance(entry_date, date_cls):
            entry.entry_date = entry_date

    await db.commit()
    await db.refresh(entry)
    return entry


async def fetch_last_entry_for_business(
    db: AsyncSession,
    business_id: uuid.UUID,
) -> Entry | None:
    r = await db.execute(
        select(Entry)
        .where(Entry.business_id == business_id)
        .options(selectinload(Entry.lines))
        .order_by(Entry.created_at.desc())
        .limit(1)
    )
    return r.scalar_one_or_none()
