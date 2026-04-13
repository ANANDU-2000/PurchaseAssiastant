"""Shared preview + confirm path for purchase entries (HTTP API and WhatsApp)."""

from __future__ import annotations

import uuid
from typing import Any

from fastapi import HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.schemas.entries import EntryCreateRequest, EntryLineOut, EntryOut
from app.services.catalog_resolution import resolve_catalog_items_on_entry
from app.services.entry_logic import (
    apply_computed_landings,
    enrich_line_quantities,
    entry_line_profit,
    entry_price_warnings,
    find_duplicates,
)
from app.services.entry_preview_token import consume_preview_token, issue_preview_token, verify_preview_token
from app.services.entry_write import persist_confirmed_entry


async def prepare_create_entry_preview(
    db: AsyncSession,
    business_id: uuid.UUID,
    user_id: uuid.UUID,
    body: EntryCreateRequest,
) -> tuple[dict[str, Any], EntryCreateRequest]:
    body = await _normalize_entry_like_preview(db, business_id, body)

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
                stock_note=li.stock_note.strip() if li.stock_note else None,
            )
        )

    token = issue_preview_token(body, user_id=user_id, business_id=business_id)
    warnings = await entry_price_warnings(db, business_id, body)
    content = {
        "preview": True,
        "preview_token": token,
        "entry_date": body.entry_date.isoformat(),
        "lines": [p.model_dump(mode="json") for p in preview_lines],
        "warnings": warnings,
    }
    return content, body


async def _normalize_entry_like_preview(
    db: AsyncSession,
    business_id: uuid.UUID,
    body: EntryCreateRequest,
) -> EntryCreateRequest:
    """Same transforms as `prepare_create_entry_preview` so preview_token hash matches on confirm."""
    try:
        body = await resolve_catalog_items_on_entry(db, business_id, body)
    except ValueError as e:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail=str(e)) from e
    body = apply_computed_landings(body)
    enriched = [enrich_line_quantities(li) for li in body.lines]
    return body.model_copy(update={"lines": enriched})


async def commit_create_entry_confirmed(
    db: AsyncSession,
    business_id: uuid.UUID,
    user_id: uuid.UUID,
    body: EntryCreateRequest,
    *,
    source: str = "app",
) -> EntryOut:
    normalized = await _normalize_entry_like_preview(db, business_id, body)
    normalized = normalized.model_copy(
        update={
            "preview_token": body.preview_token,
            "confirm": body.confirm,
            "force_duplicate": body.force_duplicate,
        }
    )
    ok, err = verify_preview_token(
        body.preview_token,
        normalized,
        user_id=user_id,
        business_id=business_id,
    )
    if not ok:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=err)

    dup_ids: list[uuid.UUID] = []
    for li in normalized.lines:
        dup_ids.extend(
            await find_duplicates(
                db,
                business_id,
                li.item_name,
                li.qty,
                normalized.entry_date,
                supplier_id=normalized.supplier_id,
                catalog_variant_id=li.catalog_variant_id,
            )
        )
    matching_entry_ids = list(dict.fromkeys(dup_ids))
    if matching_entry_ids and not normalized.force_duplicate:
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
        user_id=user_id,
        body=normalized,
        source=source,
    )
    consume_preview_token(normalized.preview_token)
    return out
