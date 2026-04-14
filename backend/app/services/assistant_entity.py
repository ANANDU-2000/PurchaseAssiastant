"""Chat-first entity creation: supplier, category, catalog item, variant — preview token + confirm."""

from __future__ import annotations

import re
import time
import uuid
from typing import Any, Literal

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import CatalogItem, CatalogVariant, ItemCategory, Supplier

EntityKind = Literal["supplier", "category", "category_item", "catalog_item", "variant"]

_PREVIEW: dict[str, dict[str, Any]] = {}
_TTL = 600.0


def _expired(exp: float) -> bool:
    return time.monotonic() > exp


def issue_entity_preview(
    *,
    user_id: uuid.UUID,
    business_id: uuid.UUID,
    kind: EntityKind,
    payload: dict[str, Any],
) -> str:
    tok = str(uuid.uuid4())
    _PREVIEW[tok] = {
        "user_id": str(user_id),
        "business_id": str(business_id),
        "kind": kind,
        "payload": dict(payload),
        "exp": time.monotonic() + _TTL,
    }
    return tok


def get_entity_preview(
    token: str | None,
    *,
    user_id: uuid.UUID,
    business_id: uuid.UUID,
) -> tuple[EntityKind, dict[str, Any]] | None:
    if not token or not token.strip():
        return None
    row = _PREVIEW.get(token.strip())
    if row is None:
        return None
    if _expired(float(row["exp"])):
        _PREVIEW.pop(token.strip(), None)
        return None
    if row["user_id"] != str(user_id) or row["business_id"] != str(business_id):
        return None
    return row["kind"], dict(row["payload"])


def consume_entity_preview(token: str | None) -> None:
    if token and token.strip() in _PREVIEW:
        _PREVIEW.pop(token.strip(), None)


def parse_entity_message(text: str) -> tuple[EntityKind, dict[str, Any]] | None:
    """Rule-based parse for create/add supplier|category|item — no LLM required."""
    t = text.strip()
    if len(t) > 800:
        return None

    m = re.match(r"(?i)^(?:create|add)\s+supplier\s+(.+)$", t)
    if m:
        name = m.group(1).strip().strip("'\"")  # noqa: B005
        if name:
            return ("supplier", {"name": name})

    m = re.match(r"(?i)^(?:create|add)\s+category\s+(.+?)\s*>\s*(.+)$", t)
    if m:
        cat = m.group(1).strip().strip("'\"")
        item = m.group(2).strip().strip("'\"")
        if cat and item:
            return ("category_item", {"category_name": cat, "item_name": item})

    m = re.match(r"(?i)^(?:create|add)\s+category\s+(.+)$", t)
    if m:
        name = m.group(1).strip().strip("'\"")
        if name:
            return ("category", {"name": name})

    m = re.match(r"(?i)^(?:create|add)\s+item\s+(.+?)\s+under\s+(.+)$", t)
    if m:
        rest = m.group(1).strip()
        cat = m.group(2).strip().strip("'\"")
        parsed = _parse_item_phrase(rest)
        if parsed.get("name") and cat:
            parsed["category_name"] = cat
            return ("catalog_item", parsed)

    m = re.match(r"(?i)^(?:create|add)\s+item\s+(.+)$", t)
    if m:
        rest = m.group(1).strip()
        parsed = _parse_item_phrase(rest)
        if parsed.get("name"):
            return ("catalog_item", parsed)

    m = re.match(r"(?i)^(?:create|add)\s+variant\s+(.+?)\s+(?:under|for)\s+(.+)$", t)
    if m:
        vname = m.group(1).strip().strip("'\"")
        item_name = m.group(2).strip().strip("'\"")
        if vname and item_name:
            return ("variant", {"variant_name": vname, "item_name": item_name})

    return None


def _parse_item_phrase(rest: str) -> dict[str, Any]:
    """Parse 'basmati 50kg bag' style — name + optional unit hints."""
    name = rest
    default_unit: str | None = None
    kg_per_bag: float | None = None
    m = re.search(r"(?i)(\d+(?:\.\d+)?)\s*kg\s*bag\s*$", rest)
    if not m:
        m = re.search(r"(?i)(\d+(?:\.\d+)?)\s*kg\s*(?:per\s*)?(?:bag)?\s*$", rest)
    if m:
        kg_per_bag = float(m.group(1))
        default_unit = "bag"
        name = rest[: m.start()].strip()
    elif re.search(r"(?i)\bbag\s*$", rest):
        default_unit = "bag"
        name = re.sub(r"(?i)\s*bag\s*$", "", rest).strip()
    elif re.search(r"(?i)\bbox\s*$", rest):
        default_unit = "box"
        name = re.sub(r"(?i)\s*box\s*$", "", rest).strip()
    elif re.search(r"(?i)\bkg\s*$", rest):
        default_unit = "kg"
        name = re.sub(r"(?i)\s*kg\s*$", "", rest).strip()
    return {
        "name": name,
        "default_unit": default_unit,
        "default_kg_per_bag": kg_per_bag,
        "category_name": None,
    }


async def _dup_category(db: AsyncSession, business_id: uuid.UUID, name: str) -> bool:
    r = await db.execute(
        select(ItemCategory.id).where(
            ItemCategory.business_id == business_id,
            func.lower(ItemCategory.name) == name.lower().strip(),
        )
    )
    return r.first() is not None


async def _dup_supplier(db: AsyncSession, business_id: uuid.UUID, name: str) -> bool:
    r = await db.execute(
        select(Supplier.id).where(
            Supplier.business_id == business_id,
            func.lower(Supplier.name) == name.lower().strip(),
        )
    )
    return r.first() is not None


async def commit_entity(
    db: AsyncSession,
    business_id: uuid.UUID,
    kind: EntityKind,
    payload: dict[str, Any],
) -> dict[str, Any]:
    """Persist entity; caller commits transaction."""
    if kind == "supplier":
        name = str(payload["name"]).strip()
        if await _dup_supplier(db, business_id, name):
            raise ValueError("Supplier already exists")
        s = Supplier(business_id=business_id, name=name)
        db.add(s)
        await db.flush()
        return {"id": str(s.id), "name": s.name, "entity": "supplier"}

    if kind == "category":
        name = str(payload["name"]).strip()
        if await _dup_category(db, business_id, name):
            raise ValueError("Category already exists")
        c = ItemCategory(business_id=business_id, name=name)
        db.add(c)
        await db.flush()
        return {"id": str(c.id), "name": c.name, "entity": "category"}

    if kind == "category_item":
        cn = str(payload["category_name"]).strip()
        item_name = str(payload["item_name"]).strip()
        r = await db.execute(
            select(ItemCategory).where(
                ItemCategory.business_id == business_id,
                func.lower(ItemCategory.name) == cn.lower(),
            )
        )
        cat = r.scalar_one_or_none()
        if cat is None:
            cat = ItemCategory(business_id=business_id, name=cn)
            db.add(cat)
            await db.flush()
        dup = await db.execute(
            select(CatalogItem.id).where(
                CatalogItem.business_id == business_id,
                CatalogItem.category_id == cat.id,
                func.lower(CatalogItem.name) == item_name.lower(),
            )
        )
        if dup.first():
            raise ValueError("Item already exists under this category")
        it = CatalogItem(
            business_id=business_id,
            category_id=cat.id,
            name=item_name,
            default_unit="kg",
        )
        db.add(it)
        await db.flush()
        return {
            "category_id": str(cat.id),
            "item_id": str(it.id),
            "entity": "category_item",
        }

    if kind == "catalog_item":
        item_name = str(payload["name"]).strip()
        cat_hint = payload.get("category_name")
        if not cat_hint:
            raise ValueError("Say: create item NAME under CATEGORY — or create category X > Y first")
        r = await db.execute(
            select(ItemCategory).where(
                ItemCategory.business_id == business_id,
                func.lower(ItemCategory.name) == str(cat_hint).lower().strip(),
            )
        )
        cat = r.scalar_one_or_none()
        if cat is None:
            raise ValueError(f"Unknown category “{cat_hint}”. Create the category first.")
        dup = await db.execute(
            select(CatalogItem.id).where(
                CatalogItem.business_id == business_id,
                CatalogItem.category_id == cat.id,
                func.lower(CatalogItem.name) == item_name.lower(),
            )
        )
        if dup.first():
            raise ValueError("Item already exists")
        unit = payload.get("default_unit") or "kg"
        if unit not in ("kg", "box", "piece", "bag"):
            unit = "kg"
        kgpb = payload.get("default_kg_per_bag")
        it = CatalogItem(
            business_id=business_id,
            category_id=cat.id,
            name=item_name,
            default_unit=unit,
            default_kg_per_bag=kgpb,
        )
        db.add(it)
        await db.flush()
        return {"id": str(it.id), "entity": "catalog_item"}

    if kind == "variant":
        vname = str(payload["variant_name"]).strip()
        item_name = str(payload["item_name"]).strip()
        r = await db.execute(
            select(CatalogItem).where(
                CatalogItem.business_id == business_id,
                func.lower(CatalogItem.name) == item_name.lower(),
            )
        )
        it = r.scalar_one_or_none()
        if it is None:
            raise ValueError(f"Item “{item_name}” not found — create it first")
        dup = await db.execute(
            select(CatalogVariant.id).where(
                CatalogVariant.catalog_item_id == it.id,
                func.lower(CatalogVariant.name) == vname.lower(),
            )
        )
        if dup.first():
            raise ValueError("Variant already exists for this item")
        v = CatalogVariant(
            business_id=business_id,
            catalog_item_id=it.id,
            name=vname,
            default_kg_per_bag=payload.get("default_kg_per_bag"),
        )
        db.add(v)
        await db.flush()
        return {"id": str(v.id), "entity": "variant"}

    raise ValueError("Unknown entity kind")


def preview_lines_for(kind: EntityKind, payload: dict[str, Any]) -> str:
    if kind == "supplier":
        return f"Supplier: {payload['name']}"
    if kind == "category":
        return f"Category: {payload['name']}"
    if kind == "category_item":
        return f"Category: {payload['category_name']}\nItem: {payload['item_name']}"
    if kind == "catalog_item":
        lines = ""
        if payload.get("category_name"):
            lines = f"Category: {payload['category_name']}\n"
        lines += f"Item: {payload['name']}"
        if payload.get("default_unit"):
            lines += f"\nUnit: {payload['default_unit']}"
        if payload.get("default_kg_per_bag"):
            lines += f"\nKg/bag: {payload['default_kg_per_bag']}"
        return lines
    if kind == "variant":
        return f"Variant: {payload['variant_name']}\nUnder item: {payload['item_name']}"
    return str(payload)

