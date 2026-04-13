import uuid
from datetime import date
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query, status
from fastapi.responses import JSONResponse
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.database import get_db
from app.deps import get_current_user, require_ai_parse_enabled, require_membership
from app.models import Entry, EntryLineItem, Membership, User
from app.schemas.entries import (
    DuplicateCheckRequest,
    DuplicateCheckResponse,
    EntryCreateRequest,
    EntryLineOut,
    EntryOut,
    ParseDraftResponse,
)
from app.services.entry_create_pipeline import commit_create_entry_confirmed, prepare_create_entry_preview
from app.services.entry_logic import find_duplicates

router = APIRouter(prefix="/v1/businesses/{business_id}/entries", tags=["entries"])


class ParseBody(BaseModel):
    text: str


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


@router.post("/parse", response_model=ParseDraftResponse)
async def parse_draft(
    business_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    _ai: Annotated[None, Depends(require_ai_parse_enabled)],
    body: ParseBody,
):
    del business_id, _m, body, _ai
    return ParseDraftResponse(
        draft=None,
        missing_fields=["item_name", "qty", "unit", "buy_price", "landing_cost"],
        confidence=0.0,
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


@router.get("")
async def list_entries(
    business_id: uuid.UUID,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
    from_date: date | None = Query(None, alias="from"),
    to_date: date | None = Query(None, alias="to"),
    item: str | None = None,
    supplier_id: uuid.UUID | None = None,
    broker_id: uuid.UUID | None = None,
):
    del user, _m
    q = select(Entry).where(Entry.business_id == business_id)
    if from_date:
        q = q.where(Entry.entry_date >= from_date)
    if to_date:
        q = q.where(Entry.entry_date <= to_date)
    if supplier_id:
        q = q.where(Entry.supplier_id == supplier_id)
    if broker_id:
        q = q.where(Entry.broker_id == broker_id)
    q = q.options(selectinload(Entry.lines)).order_by(
        Entry.entry_date.desc(), Entry.created_at.desc()
    )
    result = await db.execute(q)
    entries = result.scalars().unique().all()
    if item:
        needle = item.lower().strip()
        filtered = []
        for e in entries:
            if any(needle in (li.item_name or "").lower() for li in e.lines):
                filtered.append(e)
        entries = filtered
    return {"items": [_entry_to_out(e).model_dump(mode="json") for e in entries], "next_cursor": None}


@router.get("/{entry_id}")
async def get_entry(
    business_id: uuid.UUID,
    entry_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
):
    del _m
    result = await db.execute(
        select(Entry)
        .where(Entry.id == entry_id, Entry.business_id == business_id)
        .options(selectinload(Entry.lines))
    )
    entry = result.scalar_one_or_none()
    if entry is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Entry not found")
    return _entry_to_out(entry).model_dump(mode="json")


@router.post("", status_code=status.HTTP_201_CREATED)
async def create_entry(
    business_id: uuid.UUID,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
    body: EntryCreateRequest,
):
    del _m
    if not body.confirm:
        content, _ = await prepare_create_entry_preview(db, business_id, user.id, body)
        return JSONResponse(status_code=status.HTTP_200_OK, content=content)

    out = await commit_create_entry_confirmed(
        db, business_id, user.id, body, source="app"
    )
    return JSONResponse(
        status_code=status.HTTP_201_CREATED,
        content=out.model_dump(mode="json"),
    )


@router.post("/check-duplicate", response_model=DuplicateCheckResponse)
async def check_duplicate(
    business_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
    body: DuplicateCheckRequest,
):
    del _m
    ids = await find_duplicates(
        db,
        business_id,
        body.item_name,
        body.qty,
        body.entry_date,
        supplier_id=body.supplier_id,
        catalog_variant_id=body.catalog_variant_id,
    )
    return DuplicateCheckResponse(duplicate=len(ids) > 0, matching_entry_ids=ids)
