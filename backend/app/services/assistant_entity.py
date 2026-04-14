"""Chat-first entity creation: supplier, category, catalog item, variant — preview token + confirm."""

from __future__ import annotations

import re
import time
import uuid
from typing import Any, Literal

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Broker, CatalogItem, CatalogVariant, CategoryType, ItemCategory, Supplier
from app.services.fuzzy_catalog import (
    best_token_sort_match,
    fuzzy_find_similar_catalog_item_name_in_category,
    fuzzy_find_similar_category_name,
    fuzzy_find_similar_supplier_name,
    fuzzy_find_similar_variant_name_for_item,
)

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
        payload = _parse_supplier_phrase(m.group(1).strip())
        if payload.get("name"):
            return ("supplier", payload)

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


def _parse_supplier_phrase(rest: str) -> dict[str, Any]:
    """
    Parse supplier free-text into fields.
    Examples:
      "name aju from delhi number 9876543210"
      "aju phone 9876543210 broker ramesh"
    """
    raw = " ".join(rest.strip().split())
    low = raw.lower()

    # Phone: prefer longest contiguous digits (ignore country code separators/spaces).
    digits = re.findall(r"\d{7,15}", re.sub(r"[^\d]", " ", raw))
    phone = max(digits, key=len) if digits else None

    # Location hints.
    loc = None
    m_loc = re.search(r"(?i)\b(?:from|at|in|location)\s+([a-zA-Z][a-zA-Z .-]{1,60})", raw)
    if m_loc:
        loc = " ".join(m_loc.group(1).split()).strip(" .,")

    # Broker hint.
    broker_name = None
    m_broker = re.search(r"(?i)\bbroker\s+([a-zA-Z][a-zA-Z .-]{1,60})", raw)
    if m_broker:
        broker_name = " ".join(m_broker.group(1).split()).strip(" .,")

    # Name candidates.
    name = None
    m_name = re.search(r"(?i)\bname\s+([a-zA-Z][a-zA-Z .-]{1,80})", raw)
    if m_name:
        name = " ".join(m_name.group(1).split()).strip(" .,")

    # If "name ..." was noisy, trim known trailing markers.
    if name:
        name = re.split(r"(?i)\b(?:from|at|in|location|number|phone|mobile|broker)\b", name)[0].strip(" .,")

    # Fallback: first 1-3 words after command, before markers.
    if not name:
        s = raw
        if phone:
            s = s.replace(phone, " ")
        s = re.split(r"(?i)\b(?:from|at|in|location|number|phone|mobile|broker)\b", s)[0]
        toks = [t for t in re.findall(r"[A-Za-z][A-Za-z'-]*", s) if t.lower() not in {"and", "his", "her"}]
        if toks:
            name = " ".join(toks[:3]).strip()

    # Final cleanup: block obviously invalid names.
    if name:
        nlow = name.lower()
        if nlow in {"name", "supplier", "create", "add"} or len(name) < 2:
            name = None

    payload: dict[str, Any] = {"name": name}
    if phone:
        payload["phone"] = phone
    if loc:
        payload["location"] = loc
    if broker_name:
        payload["broker_name"] = broker_name
    return payload


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


def _force_create(payload: dict[str, Any]) -> bool:
    return payload.get("force_create") is True


def _parse_uuid_val(val: object) -> uuid.UUID | None:
    if val is None:
        return None
    try:
        return uuid.UUID(str(val).strip())
    except (ValueError, TypeError, AttributeError):
        return None


def resolve_catalog_type_id_for_payload(
    cts: list[CategoryType],
    payload: dict[str, Any],
) -> uuid.UUID | None:
    """
    Pick CategoryType id from payload when category has multiple types.
    Returns None if the user must still choose (no usable hint).
    """
    if not cts:
        return None
    if len(cts) == 1:
        return cts[0].id
    tid = _parse_uuid_val(payload.get("type_id"))
    if tid is not None:
        for t in cts:
            if t.id == tid:
                return t.id
        return None
    hint = (payload.get("type_name") or payload.get("type") or "").strip()
    if not hint:
        return None
    for t in cts:
        if t.name.strip().lower() == hint.lower():
            return t.id
    names = [t.name for t in cts]
    matched, _sc = best_token_sort_match(hint, names)
    if matched:
        for t in cts:
            if t.name == matched:
                return t.id
    return None


async def catalog_types_for_category(
    db: AsyncSession, category_id: uuid.UUID
) -> list[CategoryType]:
    r = await db.execute(
        select(CategoryType)
        .where(CategoryType.category_id == category_id)
        .order_by(CategoryType.name)
    )
    return list(r.scalars().all())


async def catalog_item_type_pick_clarify_if_needed(
    db: AsyncSession,
    business_id: uuid.UUID,
    payload: dict[str, Any],
) -> tuple[str | None, dict[str, Any] | None]:
    cat_hint = payload.get("category_name")
    if not cat_hint:
        return None, None
    r = await db.execute(
        select(ItemCategory).where(
            ItemCategory.business_id == business_id,
            func.lower(ItemCategory.name) == str(cat_hint).lower().strip(),
        )
    )
    cat = r.scalar_one_or_none()
    if cat is None:
        return None, None
    cts = await catalog_types_for_category(db, cat.id)
    if len(cts) <= 1:
        return None, None
    if resolve_catalog_type_id_for_payload(cts, payload) is not None:
        return None, None
    lines = [f"{i + 1}. {t.name}" for i, t in enumerate(cts)]
    msg = (
        "This category has more than one type — which one should the new item use?\n"
        + "\n".join(lines)
        + "\n\nReply with the number or the type name (e.g. 2 or the label above)."
    )
    pending = {
        "kind": "catalog_item",
        "payload": dict(payload),
        "type_ids": [str(t.id) for t in cts],
        "type_names": [t.name for t in cts],
    }
    return msg, pending


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
        if not _force_create(payload):
            sim = await fuzzy_find_similar_supplier_name(db, business_id, name)
            if sim and sim.strip().lower() != name.lower():
                raise ValueError(
                    f'Did you mean "{sim}"? A similar supplier already exists. '
                    f'Say CREATE NEW to add "{name}" anyway.'
                )
        broker_id = None
        broker_name = str(payload.get("broker_name") or "").strip()
        if broker_name:
            br = await db.execute(
                select(Broker).where(
                    Broker.business_id == business_id,
                    func.lower(Broker.name) == broker_name.lower(),
                )
            )
            b = br.scalar_one_or_none()
            if b is not None:
                broker_id = b.id
        s = Supplier(
            business_id=business_id,
            name=name,
            phone=(str(payload.get("phone") or "").strip() or None),
            location=(str(payload.get("location") or "").strip() or None),
            broker_id=broker_id,
        )
        db.add(s)
        await db.flush()
        return {
            "id": str(s.id),
            "name": s.name,
            "phone": s.phone,
            "location": s.location,
            "broker_id": str(s.broker_id) if s.broker_id else None,
            "entity": "supplier",
        }

    if kind == "category":
        name = str(payload["name"]).strip()
        if await _dup_category(db, business_id, name):
            raise ValueError("Category already exists")
        if not _force_create(payload):
            sim = await fuzzy_find_similar_category_name(db, business_id, name)
            if sim and sim.strip().lower() != name.lower():
                raise ValueError(
                    f'Did you mean "{sim}"? A similar category already exists. '
                    f'Say CREATE NEW to add "{name}" anyway.'
                )
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
        if not _force_create(payload):
            sim = await fuzzy_find_similar_catalog_item_name_in_category(
                db, business_id, cat.id, item_name
            )
            if sim and sim.strip().lower() != item_name.lower():
                raise ValueError(
                    f'Did you mean "{sim}"? A similar item exists in this category. '
                    f'Say CREATE NEW to add "{item_name}" anyway.'
                )
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
        if not _force_create(payload):
            sim = await fuzzy_find_similar_catalog_item_name_in_category(
                db, business_id, cat.id, item_name
            )
            if sim and sim.strip().lower() != item_name.lower():
                raise ValueError(
                    f'Did you mean "{sim}"? A similar item exists in this category. '
                    f'Say CREATE NEW to add "{item_name}" anyway.'
                )
        types_r = await db.execute(
            select(CategoryType)
            .where(CategoryType.category_id == cat.id)
            .order_by(CategoryType.name)
        )
        cts = list(types_r.scalars().all())
        type_id_resolved = resolve_catalog_type_id_for_payload(cts, payload)
        if len(cts) > 1 and type_id_resolved is None:
            raise ValueError(
                "This category has multiple types — pick one in chat (number or type name), "
                "or include type in the create request."
            )
        unit = payload.get("default_unit") or "kg"
        if unit not in ("kg", "box", "piece", "bag"):
            unit = "kg"
        kgpb = payload.get("default_kg_per_bag")
        it = CatalogItem(
            business_id=business_id,
            category_id=cat.id,
            type_id=type_id_resolved,
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
        if not _force_create(payload):
            sim = await fuzzy_find_similar_variant_name_for_item(
                db, business_id, it.id, vname
            )
            if sim and sim.strip().lower() != vname.lower():
                raise ValueError(
                    f'Did you mean "{sim}"? A similar variant exists for this item. '
                    f'Say CREATE NEW to add "{vname}" anyway.'
                )
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


async def preview_fuzzy_entity_block(
    db: AsyncSession,
    business_id: uuid.UUID,
    kind: EntityKind,
    payload: dict[str, Any],
) -> str | None:
    """
    If a very similar name already exists, return a short clarify message (before showing preview).
    Caller may set payload['force_create']=True after user says CREATE NEW.
    """
    if _force_create(payload):
        return None
    if kind == "supplier":
        name = str(payload.get("name") or "").strip()
        if not name:
            return None
        if await _dup_supplier(db, business_id, name):
            return "Supplier with this name already exists."
        sim = await fuzzy_find_similar_supplier_name(db, business_id, name)
        if sim and sim.strip().lower() != name.lower():
            return (
                f'Did you mean "{sim}"? A similar supplier exists. '
                f'Say CREATE NEW to add "{name}" anyway.'
            )
        return None
    if kind == "category":
        name = str(payload.get("name") or "").strip()
        if not name:
            return None
        if await _dup_category(db, business_id, name):
            return "Category with this name already exists."
        sim = await fuzzy_find_similar_category_name(db, business_id, name)
        if sim and sim.strip().lower() != name.lower():
            return (
                f'Did you mean "{sim}"? A similar category exists. '
                f'Say CREATE NEW to add "{name}" anyway.'
            )
        return None
    if kind == "category_item":
        cn = str(payload.get("category_name") or "").strip()
        item_name = str(payload.get("item_name") or "").strip()
        if not cn or not item_name:
            return None
        r = await db.execute(
            select(ItemCategory).where(
                ItemCategory.business_id == business_id,
                func.lower(ItemCategory.name) == cn.lower(),
            )
        )
        cat = r.scalar_one_or_none()
        if cat is None:
            return None
        dup = await db.execute(
            select(CatalogItem.id).where(
                CatalogItem.business_id == business_id,
                CatalogItem.category_id == cat.id,
                func.lower(CatalogItem.name) == item_name.lower(),
            )
        )
        if dup.first():
            return "Item already exists under this category."
        sim = await fuzzy_find_similar_catalog_item_name_in_category(
            db, business_id, cat.id, item_name
        )
        if sim and sim.strip().lower() != item_name.lower():
            return (
                f'Did you mean "{sim}"? A similar item exists. '
                f'Say CREATE NEW to add "{item_name}" anyway.'
            )
        return None
    if kind == "catalog_item":
        item_name = str(payload.get("name") or "").strip()
        cat_hint = payload.get("category_name")
        if not item_name or not cat_hint:
            return None
        r = await db.execute(
            select(ItemCategory).where(
                ItemCategory.business_id == business_id,
                func.lower(ItemCategory.name) == str(cat_hint).lower().strip(),
            )
        )
        cat = r.scalar_one_or_none()
        if cat is None:
            return None
        dup = await db.execute(
            select(CatalogItem.id).where(
                CatalogItem.business_id == business_id,
                CatalogItem.category_id == cat.id,
                func.lower(CatalogItem.name) == item_name.lower(),
            )
        )
        if dup.first():
            return "Item already exists."
        sim = await fuzzy_find_similar_catalog_item_name_in_category(
            db, business_id, cat.id, item_name
        )
        if sim and sim.strip().lower() != item_name.lower():
            return (
                f'Did you mean "{sim}"? A similar item exists. '
                f'Say CREATE NEW to add "{item_name}" anyway.'
            )
        return None
    if kind == "variant":
        vname = str(payload.get("variant_name") or "").strip()
        item_name = str(payload.get("item_name") or "").strip()
        if not vname or not item_name:
            return None
        r = await db.execute(
            select(CatalogItem).where(
                CatalogItem.business_id == business_id,
                func.lower(CatalogItem.name) == item_name.lower(),
            )
        )
        it = r.scalar_one_or_none()
        if it is None:
            return None
        dup = await db.execute(
            select(CatalogVariant.id).where(
                CatalogVariant.catalog_item_id == it.id,
                func.lower(CatalogVariant.name) == vname.lower(),
            )
        )
        if dup.first():
            return "Variant already exists for this item."
        sim = await fuzzy_find_similar_variant_name_for_item(db, business_id, it.id, vname)
        if sim and sim.strip().lower() != vname.lower():
            return (
                f'Did you mean "{sim}"? A similar variant exists. '
                f'Say CREATE NEW to add "{vname}" anyway.'
            )
        return None
    return None


def preview_lines_for(kind: EntityKind, payload: dict[str, Any]) -> str:
    if kind == "supplier":
        lines = [f"Supplier: {payload['name']}"]
        phone = str(payload.get("phone") or "").strip()
        location = str(payload.get("location") or "").strip()
        broker_name = str(payload.get("broker_name") or "").strip()
        if phone:
            lines.append(f"Phone: {phone}")
        if location:
            lines.append(f"Location: {location}")
        if broker_name:
            lines.append(f"Broker: {broker_name}")
        return "\n".join(lines)
    if kind == "category":
        return f"Category: {payload['name']}"
    if kind == "category_item":
        return f"Category: {payload['category_name']}\nItem: {payload['item_name']}"
    if kind == "catalog_item":
        lines = ""
        if payload.get("category_name"):
            lines = f"Category: {payload['category_name']}\n"
        if payload.get("type_name"):
            lines += f"Type: {payload['type_name']}\n"
        lines += f"Item: {payload['name']}"
        if payload.get("default_unit"):
            lines += f"\nUnit: {payload['default_unit']}"
        if payload.get("default_kg_per_bag"):
            lines += f"\nKg/bag: {payload['default_kg_per_bag']}"
        return lines
    if kind == "variant":
        return f"Variant: {payload['variant_name']}\nUnder item: {payload['item_name']}"
    return str(payload)

