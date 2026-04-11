"""Resolve catalog_item_id on entry lines to canonical name/category/unit."""

from __future__ import annotations

import uuid

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import joinedload

from app.models import CatalogItem, ItemCategory
from app.schemas.entries import EntryCreateRequest, EntryLineInput


async def resolve_catalog_items_on_entry(
    db: AsyncSession,
    business_id: uuid.UUID,
    body: EntryCreateRequest,
) -> EntryCreateRequest:
    new_lines: list[EntryLineInput] = []
    for li in body.lines:
        if li.catalog_item_id is None:
            new_lines.append(li)
            continue
        r = await db.execute(
            select(CatalogItem)
            .options(joinedload(CatalogItem.category))
            .where(CatalogItem.id == li.catalog_item_id, CatalogItem.business_id == business_id)
        )
        cit = r.unique().scalar_one_or_none()
        if cit is None:
            raise ValueError(f"Invalid catalog_item_id: {li.catalog_item_id}")
        cat = cit.category
        unit = cit.default_unit if cit.default_unit in ("kg", "box", "piece") else li.unit
        new_lines.append(
            li.model_copy(
                update={
                    "item_name": cit.name.strip(),
                    "category": cat.name.strip() if cat else None,
                    "unit": unit,
                }
            )
        )
    return body.model_copy(update={"lines": new_lines})
