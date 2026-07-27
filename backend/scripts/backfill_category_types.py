"""
One-off: ensure each item_categories row has a "General" category_types row and
set catalog_items.type_id where NULL.

Run from backend directory:

  python -m scripts.backfill_category_types

Requires DATABASE_URL (same as the API).
"""

from __future__ import annotations

import os
import sys

from sqlalchemy import create_engine, func, select
from sqlalchemy.orm import Session

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from app.models.catalog import CatalogItem, CategoryType, ItemCategory  # noqa: E402

GENERAL = "General"


def _norm(s: str) -> str:
    return " ".join(s.lower().strip().split())


def run() -> None:
    url = os.getenv("DATABASE_URL") or os.getenv("SQLALCHEMY_DATABASE_URI")
    if not url:
        print("Set DATABASE_URL", file=sys.stderr)
        sys.exit(1)
    engine = create_engine(url, future=True)
    created_types = 0
    with Session(engine) as db:
        cats = db.execute(select(ItemCategory)).scalars().all()
        general_by_cat: dict = {}
        for c in cats:
            r = db.execute(
                select(CategoryType.id).where(
                    CategoryType.category_id == c.id,
                    func.lower(CategoryType.name) == _norm(GENERAL),
                )
            ).scalar_one_or_none()
            if r is None:
                ct = CategoryType(category_id=c.id, name=GENERAL)
                db.add(ct)
                db.flush()
                general_by_cat[c.id] = ct.id
                created_types += 1
            else:
                general_by_cat[c.id] = r

        items = db.execute(select(CatalogItem).where(CatalogItem.type_id.is_(None))).scalars().all()
        updated = 0
        for it in items:
            gid = general_by_cat.get(it.category_id)
            if gid is None:
                continue
            it.type_id = gid
            updated += 1
        db.commit()
        print(f"category_types created: {created_types}; catalog_items.type_id set: {updated}")


if __name__ == "__main__":
    run()
