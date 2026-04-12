"""Profit and duplicate checks — server-side single source of truth."""

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


def enrich_line_quantities(li: EntryLineInput) -> EntryLineInput:
    """Derive qty_kg for bag lines; for kg lines mirror qty into qty_kg when unset."""
    if li.unit == "bag":
        kg_per = float(li.kg_per_bag or 0)
        bags = float(li.qty)
        qk = bags * kg_per if kg_per > 0 else None
        return li.model_copy(update={"qty_kg": qk, "bags": bags})
    if li.unit == "kg" and li.qty_kg is None:
        return li.model_copy(update={"qty_kg": float(li.qty)})
    return li


def entry_line_profit(li: EntryLineInput) -> Decimal | None:
    """Profit for one line. For bag: landing is per bag, selling_price is per kg."""
    sell = Decimal(str(li.selling_price)) if li.selling_price is not None else None
    if sell is None:
        return None
    q = Decimal(str(li.qty))
    land = Decimal(str(li.landing_cost))
    if li.unit == "bag":
        kg_per = Decimal(str(li.kg_per_bag or 0))
        if kg_per <= 0:
            return None
        qty_kg = q * kg_per
        total_cost = q * land
        revenue = sell * qty_kg
        return revenue - total_cost
    return (sell - land) * q


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


def _supplier_matches(a: UUID | None, b: UUID | None) -> bool:
    return (a is None and b is None) or (a is not None and b is not None and a == b)


async def entry_price_warnings(
    db: AsyncSession,
    business_id: UUID,
    body: EntryCreateRequest,
    *,
    deviation_ratio: float = 0.25,
) -> list[str]:
    """Warn when line landing deviates from historical average for the same item (normalized)."""
    r = await db.execute(
        select(EntryLineItem.landing_cost, EntryLineItem.item_name, EntryLineItem.catalog_variant_id).join(
            Entry, Entry.id == EntryLineItem.entry_id
        ).where(Entry.business_id == business_id)
    )
    by_key: dict[str, list[float]] = {}
    by_variant: dict[UUID, list[float]] = {}
    for lc, iname, vid in r.all():
        k = normalize_item(iname or "")
        by_key.setdefault(k, []).append(float(lc))
        if vid is not None:
            by_variant.setdefault(vid, []).append(float(lc))

    warnings: list[str] = []
    for li in body.lines:
        lands = None
        if li.catalog_variant_id is not None:
            lands = by_variant.get(li.catalog_variant_id)
        if not lands:
            lands = by_key.get(normalize_item(li.item_name))
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
                f"historical average ({avg:.2f}) for this line."
            )
    return warnings


async def find_duplicates(
    db: AsyncSession,
    business_id: UUID,
    item_name: str,
    qty: float,
    entry_date: date,
    *,
    supplier_id: UUID | None = None,
    catalog_variant_id: UUID | None = None,
) -> list[UUID]:
    """Same calendar day + supplier + (variant match or normalized item + qty)."""
    key = normalize_item(item_name)
    r = await db.execute(
        select(Entry.id, Entry.supplier_id, EntryLineItem.item_name, EntryLineItem.qty, EntryLineItem.catalog_variant_id)
        .join(EntryLineItem, EntryLineItem.entry_id == Entry.id)
        .where(
            and_(
                Entry.business_id == business_id,
                Entry.entry_date == entry_date,
            )
        )
    )
    out: list[UUID] = []
    for eid, sup, iname, qtyp, vid in r.all():
        if not _supplier_matches(supplier_id, sup):
            continue
        if catalog_variant_id is not None:
            if vid == catalog_variant_id and abs(float(qtyp) - float(qty)) < 1e-9:
                out.append(eid)
        else:
            if vid is None and normalize_item(iname or "") == key and abs(float(qtyp) - float(qty)) < 1e-9:
                out.append(eid)
    return out
