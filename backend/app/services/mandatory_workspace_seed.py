"""Idempotent minimum reference data: categories, items, named suppliers, one broker (SSOT for new workspaces)."""

from __future__ import annotations

import uuid

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.models.catalog import CatalogItem, CategoryType, ItemCategory
from app.models.contacts import Broker, Supplier

# Valid-format placeholder GSTs (15 chars) for named demo suppliers; user can edit later.
_DEMO_GST = {
    "surag": "24AAAAA1111A1Z5",
    "default test supplier": "24BBBBB2222B1Z5",
}


def run_mandatory_workspace_seed(db: Session, business_id: uuid.UUID) -> dict[str, int]:
    """
    After JSON catalog seed, ensure named demo entities exist.
    Commits nothing; caller must commit.
    """
    stats = {"brokers": 0, "suppliers": 0, "categories": 0, "types": 0, "items": 0}

    # --- Broker: kim ---
    bq = select(Broker).where(
        Broker.business_id == business_id,
        func.lower(Broker.name) == "kim",
    )
    if db.execute(bq).scalar_one_or_none() is None:
        db.add(
            Broker(
                business_id=business_id,
                name="kim",
                commission_type="percent",
                commission_value=0,
            )
        )
        stats["brokers"] = 1

    # --- Rice / Oil + subcategories ---
    def _cat(name: str) -> ItemCategory:
        q = select(ItemCategory).where(
            ItemCategory.business_id == business_id,
            func.lower(ItemCategory.name) == func.lower(name),
        )
        r = db.execute(q).scalar_one_or_none()
        if r is not None:
            return r
        c = ItemCategory(business_id=business_id, name=name)
        db.add(c)
        db.flush()
        stats["categories"] += 1
        return c

    def _type_for(cat: ItemCategory, tname: str) -> CategoryType:
        tq = select(CategoryType).where(
            CategoryType.category_id == cat.id,
            func.lower(CategoryType.name) == func.lower(tname),
        )
        t = db.execute(tq).scalar_one_or_none()
        if t is not None:
            return t
        t2 = CategoryType(category_id=cat.id, name=tname)
        db.add(t2)
        db.flush()
        stats["types"] += 1
        return t2

    rice = _cat("Rice")
    oil = _cat("Oil")
    basmati = _type_for(rice, "Basmati")
    sunflower = _type_for(oil, "Sunflower")

    def _item(cat_id, type_id, name: str, unit: str) -> None:
        iq = select(CatalogItem).where(
            CatalogItem.business_id == business_id,
            func.lower(CatalogItem.name) == func.lower(name),
        )
        if db.execute(iq).scalar_one_or_none() is not None:
            return
        kpb = 50.0 if unit == "bag" else None
        db.add(
            CatalogItem(
                business_id=business_id,
                category_id=cat_id,
                type_id=type_id,
                name=name,
                default_unit=unit,
                default_purchase_unit=unit,
                hsn_code="10063090",
                tax_percent=0,
                default_kg_per_bag=kpb,
            )
        )
        stats["items"] += 1

    _item(rice.id, basmati.id, "Basmati rice (bag)", "bag")
    _item(oil.id, sunflower.id, "Sunrich oil (box)", "box")

    # --- Named suppliers (GST required by model; demo placeholders) ---
    for sname, gst in _DEMO_GST.items():
        sq = select(Supplier).where(
            Supplier.business_id == business_id,
            func.lower(Supplier.name) == func.lower(sname),
        )
        if db.execute(sq).scalar_one_or_none() is not None:
            continue
        gq = select(Supplier).where(Supplier.business_id == business_id, Supplier.gst_number == gst)
        if db.execute(gq).scalar_one_or_none() is not None:
            continue
        db.add(
            Supplier(
                business_id=business_id,
                name=sname,
                gst_number=gst,
                phone=None,
            )
        )
        stats["suppliers"] += 1

    return stats
