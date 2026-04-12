"""Shared persistence for confirmed purchase entries (app + WhatsApp)."""

from __future__ import annotations

import uuid
from decimal import Decimal

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.models import Entry, EntryLineItem
from app.schemas.entries import EntryCreateRequest, EntryLineOut, EntryOut
from app.services.entry_logic import enrich_line_quantities, entry_line_profit


def _line_to_out(line: EntryLineItem) -> EntryLineOut:
    return EntryLineOut(
        id=line.id,
        catalog_item_id=line.catalog_item_id,
        catalog_variant_id=line.catalog_variant_id,
        item_name=line.item_name,
        category=line.category,
        qty=float(line.qty),
        unit=line.unit,
        bags=float(line.bags) if line.bags is not None else None,
        kg_per_bag=float(line.kg_per_bag) if line.kg_per_bag is not None else None,
        qty_kg=float(line.qty_kg) if line.qty_kg is not None else None,
        buy_price=float(line.buy_price),
        landing_cost=float(line.landing_cost),
        selling_price=float(line.selling_price) if line.selling_price is not None else None,
        profit=float(line.profit) if line.profit is not None else None,
        stock_note=line.stock_note.strip() if line.stock_note else None,
    )


def _entry_to_out(entry: Entry) -> EntryOut:
    tc = float(entry.transport_cost) if entry.transport_cost is not None else None
    ca = float(entry.commission_amount) if entry.commission_amount is not None else None
    pl = entry.place.strip() if entry.place else None
    return EntryOut(
        id=entry.id,
        business_id=entry.business_id,
        entry_date=entry.entry_date,
        supplier_id=entry.supplier_id,
        broker_id=entry.broker_id,
        invoice_no=entry.invoice_no,
        place=pl,
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
    pl = body.place.strip() if body.place and body.place.strip() else None
    entry = Entry(
        business_id=business_id,
        user_id=user_id,
        supplier_id=body.supplier_id,
        broker_id=body.broker_id,
        entry_date=body.entry_date,
        invoice_no=body.invoice_no,
        place=pl,
        transport_cost=Decimal(str(body.transport_cost)) if body.transport_cost is not None else None,
        commission_amount=Decimal(str(body.commission_amount)) if body.commission_amount is not None else None,
        source=source,
        status="confirmed",
    )
    db.add(entry)
    await db.flush()

    for raw in body.lines:
        li = enrich_line_quantities(raw)
        qty = Decimal(str(li.qty))
        landing = Decimal(str(li.landing_cost))
        selling = Decimal(str(li.selling_price)) if li.selling_price is not None else None
        prof = entry_line_profit(li)

        if li.unit == "bag":
            qty_base = Decimal(str(li.qty_kg)) if li.qty_kg is not None else qty * Decimal(str(li.kg_per_bag or 0))
            base_unit = "kg"
        elif li.unit == "kg":
            qty_base = qty
            base_unit = "kg"
        else:
            qty_base = qty
            base_unit = "piece"

        bags_v = float(li.bags) if li.bags is not None else (float(li.qty) if li.unit == "bag" else None)
        kg_pb = float(li.kg_per_bag) if li.kg_per_bag is not None else None
        qkg = float(li.qty_kg) if li.qty_kg is not None else None
        note = li.stock_note.strip() if li.stock_note and li.stock_note.strip() else None

        db.add(
            EntryLineItem(
                entry_id=entry.id,
                catalog_item_id=li.catalog_item_id,
                catalog_variant_id=li.catalog_variant_id,
                item_name=li.item_name,
                category=li.category,
                qty=qty,
                unit=li.unit,
                bags=Decimal(str(bags_v)) if bags_v is not None else None,
                kg_per_bag=Decimal(str(kg_pb)) if kg_pb is not None else None,
                qty_kg=Decimal(str(qkg)) if qkg is not None else None,
                qty_base=qty_base,
                base_unit=base_unit,
                buy_price=Decimal(str(li.buy_price)),
                landing_cost=landing,
                selling_price=selling,
                profit=prof,
                stock_note=note,
            )
        )
    await db.commit()
    result = await db.execute(select(Entry).where(Entry.id == entry.id).options(selectinload(Entry.lines)))
    entry = result.scalar_one()
    return _entry_to_out(entry)
