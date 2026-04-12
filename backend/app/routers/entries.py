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
from app.deps import get_current_user, require_ai_enabled, require_membership
from app.models import Entry, EntryLineItem, Membership, User
from app.services.entry_preview_token import consume_preview_token, issue_preview_token, verify_preview_token
from app.services.entry_write import persist_confirmed_entry
from app.schemas.entries import (
    DuplicateCheckRequest,
    DuplicateCheckResponse,
    EntryCreateRequest,
    EntryLineOut,
    EntryOut,
    ParseDraftResponse,
)
from app.services.catalog_resolution import resolve_catalog_items_on_entry
from app.services.entry_logic import apply_computed_landings, enrich_line_quantities, entry_line_profit, entry_price_warnings, find_duplicates

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
    )


@router.post("/parse", response_model=ParseDraftResponse)
async def parse_draft(
    business_id: uuid.UUID,
    body: ParseBody,
    _m: Annotated[Membership, Depends(require_membership)],
    _ai: Annotated[None, Depends(require_ai_enabled)],
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
    body: EntryCreateRequest,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
):
    del _m
    try:
        body = await resolve_catalog_items_on_entry(db, business_id, body)
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e)) from e
    body = apply_computed_landings(body)
    enriched = [enrich_line_quantities(li) for li in body.lines]
    body = body.model_copy(update={"lines": enriched})

    preview_lines: list[EntryLineOut] = []
    for li in body.lines:
        prof = entry_line_profit(li)
        preview_lines.append(
            EntryLineOut(
                id=None,
                catalog_item_id=li.catalog_item_id,
                catalog_variant_id=li.catalog_variant_id,
                item_name=li.item_name,
                category=li.category,
                qty=float(li.qty),
                unit=li.unit,
                bags=li.bags,
                kg_per_bag=li.kg_per_bag,
                qty_kg=li.qty_kg,
                buy_price=float(li.buy_price),
                landing_cost=float(li.landing_cost),
                selling_price=float(li.selling_price) if li.selling_price is not None else None,
                profit=float(prof) if prof is not None else None,
            )
        )

    if not body.confirm:
        token = issue_preview_token(body, user_id=user.id, business_id=business_id)
        warnings = await entry_price_warnings(db, business_id, body)
        return JSONResponse(
            status_code=status.HTTP_200_OK,
            content={
                "preview": True,
                "preview_token": token,
                "entry_date": body.entry_date.isoformat(),
                "lines": [p.model_dump(mode="json") for p in preview_lines],
                "warnings": warnings,
            },
        )

    ok, err = verify_preview_token(
        body.preview_token,
        body,
        user_id=user.id,
        business_id=business_id,
    )
    if not ok:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=err)

    dup_ids: list[uuid.UUID] = []
    for li in body.lines:
        dup_ids.extend(
            await find_duplicates(
                db,
                business_id,
                li.item_name,
                li.qty,
                body.entry_date,
                supplier_id=body.supplier_id,
                catalog_variant_id=li.catalog_variant_id,
            )
        )
    matching_entry_ids = list(dict.fromkeys(dup_ids))
    if matching_entry_ids and not body.force_duplicate:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail={
                "message": "Possible duplicate entries for this date.",
                "matching_entry_ids": [str(x) for x in matching_entry_ids],
            },
        )

    out = await persist_confirmed_entry(
        db,
        business_id=business_id,
        user_id=user.id,
        body=body,
        source="app",
    )
    consume_preview_token(body.preview_token)
    return JSONResponse(
        status_code=status.HTTP_201_CREATED,
        content=out.model_dump(mode="json"),
    )


@router.post("/check-duplicate", response_model=DuplicateCheckResponse)
async def check_duplicate(
    business_id: uuid.UUID,
    body: DuplicateCheckRequest,
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
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
