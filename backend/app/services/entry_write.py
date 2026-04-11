"""Shared persistence for confirmed purchase entries (app + WhatsApp)."""

from __future__ import annotations

import uuid
from decimal import Decimal

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.models import Entry, EntryLineItem
from app.schemas.entries import EntryCreateRequest, EntryLineOut, EntryOut
from app.services.entry_logic import line_profit


def _line_to_out(line: EntryLineItem) -> EntryLineOut:
    return EntryLineOut(
        id=line.id,
        catalog_item_id=line.catalog_item_id,
        item_name=line.item_name,
        category=line.category,
        qty=float(line.qty),
        unit=line.unit,
        buy_price=float(line.buy_price),
        landing_cost=float(line.landing_cost),
        selling_price=float(line.selling_price) if line.selling_price is not None else None,
        profit=float(line.profit) if line.profit is not None else None,
    )


def _entry_to_out(entry: Entry) -> EntryOut:
    tc = float(entry.transport_cost) if entry.transport_cost is not None else None
    ca = float(entry.commission_amount) if entry.commission_amount is not None else None
    return EntryOut(
        id=entry.id,
        business_id=entry.business_id,
        entry_date=entry.entry_date,
        supplier_id=entry.supplier_id,
        broker_id=entry.broker_id,
        invoice_no=entry.invoice_no,
        transport_cost=tc,
        commission_amount=ca,
        lines=[_line_to_out(li) for li in entry.lines],
    )


async def persist_confirmed_entry(
    db: AsyncSession,
    *,
    business_id: uuid.UUID,
    user_id: uuid.UUID,
    body: EntryCreateRequest,
    source: str = "app",
) -> EntryOut:
    """Insert a confirmed entry and line items. Caller must validate membership and duplicates."""
    entry = Entry(
        business_id=business_id,
        user_id=user_id,
        supplier_id=body.supplier_id,
        broker_id=body.broker_id,
        entry_date=body.entry_date,
        invoice_no=body.invoice_no,
        transport_cost=Decimal(str(body.transport_cost)) if body.transport_cost is not None else None,
        commission_amount=Decimal(str(body.commission_amount)) if body.commission_amount is not None else None,
        source=source,
        status="confirmed",
    )
    db.add(entry)
    await db.flush()

    for li in body.lines:
        qty = Decimal(str(li.qty))
        landing = Decimal(str(li.landing_cost))
        selling = Decimal(str(li.selling_price)) if li.selling_price is not None else None
        prof = line_profit(qty, landing, selling)
        base_unit = "kg" if li.unit == "kg" else "piece"
        qty_base = qty if li.unit in ("kg", "piece") else qty
        db.add(
            EntryLineItem(
                entry_id=entry.id,
                catalog_item_id=li.catalog_item_id,
                item_name=li.item_name,
                category=li.category,
                qty=qty,
                unit=li.unit,
                qty_base=qty_base,
                base_unit=base_unit,
                buy_price=Decimal(str(li.buy_price)),
                landing_cost=landing,
                selling_price=selling,
                profit=prof,
            )
        )
    await db.commit()
    result = await db.execute(select(Entry).where(Entry.id == entry.id).options(selectinload(Entry.lines)))
    entry = result.scalar_one()
    return _entry_to_out(entry)
