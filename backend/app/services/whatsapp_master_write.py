"""Direct master-data inserts for WhatsApp confirmed actions (same rules as HTTP routers)."""

from __future__ import annotations

import uuid

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import CatalogItem, ItemCategory
from app.models.contacts import Broker, Supplier


def _norm(s: str) -> str:
    return " ".join(s.lower().strip().split())


async def insert_supplier_if_new(
    db: AsyncSession,
    business_id: uuid.UUID,
    name: str,
    phone: str | None = None,
) -> tuple[str, uuid.UUID]:
    name = name.strip()
    if not name:
        raise ValueError("Supplier name required")
    r = await db.execute(
        select(Supplier.id).where(
            Supplier.business_id == business_id,
            func.lower(Supplier.name) == name.lower(),
        )
    )
    row = r.first()
    if row:
        return "exists", row[0]
    s = Supplier(
        business_id=business_id,
        name=name,
        phone=phone,
        whatsapp_number=phone,
        location=None,
        broker_id=None,
    )
    db.add(s)
    await db.commit()
    await db.refresh(s)
    return "created", s.id


async def insert_broker_if_new(
    db: AsyncSession,
    business_id: uuid.UUID,
    name: str,
    commission_flat: float | None = None,
) -> tuple[str, uuid.UUID]:
    name = name.strip()
    if not name:
        raise ValueError("Broker name required")
    r = await db.execute(
        select(Broker.id).where(
            Broker.business_id == business_id,
            func.lower(Broker.name) == name.lower(),
        )
    )
    row = r.first()
    if row:
        return "exists", row[0]
    b = Broker(
        business_id=business_id,
        name=name,
        commission_type="flat",
        commission_value=commission_flat,
    )
    db.add(b)
    await db.commit()
    await db.refresh(b)
    return "created", b.id


async def insert_catalog_item_if_new(
    db: AsyncSession,
    business_id: uuid.UUID,
    category_name: str,
    item_name: str,
    default_unit: str | None = "kg",
) -> tuple[str, uuid.UUID]:
    cat_name = category_name.strip()
    item_name = item_name.strip()
    if not cat_name or not item_name:
        raise ValueError("Category and item name required")

    r = await db.execute(
        select(ItemCategory).where(
            ItemCategory.business_id == business_id,
            func.lower(ItemCategory.name) == _norm(cat_name),
        )
    )
    cat = r.scalar_one_or_none()
    if cat is None:
        c = ItemCategory(business_id=business_id, name=cat_name)
        db.add(c)
        await db.flush()
        cat = c

    r2 = await db.execute(
        select(CatalogItem.id).where(
            CatalogItem.business_id == business_id,
            CatalogItem.category_id == cat.id,
            func.lower(CatalogItem.name) == _norm(item_name),
        )
    )
    row = r2.first()
    if row:
        return "exists", row[0]

    unit = default_unit if default_unit in ("kg", "box", "piece", "bag") else "kg"
    it = CatalogItem(
        business_id=business_id,
        category_id=cat.id,
        name=item_name,
        default_unit=unit,
    )
    db.add(it)
    await db.commit()
    await db.refresh(it)
    return "created", it.id
