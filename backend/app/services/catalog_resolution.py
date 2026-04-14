"""Resolve catalog_item_id / catalog_variant_id on entry lines to canonical name/category/unit."""

from __future__ import annotations

import uuid
from typing import Any

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import joinedload

from app.models import CatalogItem, CatalogVariant, ItemCategory
from app.schemas.entries import EntryCreateRequest, EntryLineInput
from app.services.fuzzy_catalog import fuzzy_find_catalog_item_for_entry_line


async def resolve_catalog_items_on_entry(
    db: AsyncSession,
    business_id: uuid.UUID,
    body: EntryCreateRequest,
) -> EntryCreateRequest:
    new_lines: list[EntryLineInput] = []
    for li in body.lines:
        if li.catalog_item_id is None and li.catalog_variant_id is None:
            # Auto-link to catalog when item text closely matches an existing row (no duplicate free-text lines).
            name = (li.item_name or "").strip()
            if name:
                cit = await fuzzy_find_catalog_item_for_entry_line(db, business_id, name)
                if cit is not None:
                    cat = cit.category
                    unit = (
                        cit.default_unit
                        if cit.default_unit in ("kg", "box", "piece", "bag")
                        else li.unit
                    )
                    upd: dict[str, Any] = {
                        "catalog_item_id": cit.id,
                        "item_name": cit.name.strip(),
                        "category": cat.name.strip() if cat else None,
                        "unit": unit,
                    }
                    if unit == "bag":
                        kg_pb = li.kg_per_bag
                        if kg_pb is None and cit.default_kg_per_bag is not None:
                            kg_pb = float(cit.default_kg_per_bag)
                        upd["kg_per_bag"] = kg_pb
                    new_lines.append(li.model_copy(update=upd))
                    continue
            new_lines.append(li)
            continue

        if li.catalog_variant_id is not None:
            r = await db.execute(
                select(CatalogVariant)
                .options(joinedload(CatalogVariant.item).joinedload(CatalogItem.category))
                .where(
                    CatalogVariant.id == li.catalog_variant_id,
                    CatalogVariant.business_id == business_id,
                )
            )
            var = r.unique().scalar_one_or_none()
            if var is None:
                raise ValueError(f"Invalid catalog_variant_id: {li.catalog_variant_id}")
            cit = var.item
            cat = cit.category if cit else None
            display_name = f"{cit.name.strip()} {var.name.strip()}".strip()
            kg_pb = li.kg_per_bag if li.kg_per_bag is not None else (
                float(var.default_kg_per_bag) if var.default_kg_per_bag is not None else None
            )
            unit = li.unit
            upd = {
                "catalog_item_id": cit.id,
                "item_name": display_name,
                "category": cat.name.strip() if cat else None,
                "kg_per_bag": kg_pb,
            }
            if unit == "bag" and kg_pb:
                upd["unit"] = "bag"
            new_lines.append(li.model_copy(update=upd))
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
        unit = cit.default_unit if cit.default_unit in ("kg", "box", "piece", "bag") else li.unit
        upd: dict[str, Any] = {
            "item_name": cit.name.strip(),
            "category": cat.name.strip() if cat else None,
            "unit": unit,
        }
        if unit == "bag":
            kg_pb = li.kg_per_bag
            if kg_pb is None and cit.default_kg_per_bag is not None:
                kg_pb = float(cit.default_kg_per_bag)
            upd["kg_per_bag"] = kg_pb
        new_lines.append(li.model_copy(update=upd))
    return body.model_copy(update={"lines": new_lines})
