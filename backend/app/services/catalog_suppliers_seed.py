"""Idempotent catalog + GST suppliers seed for one business (sync SQLAlchemy Session)."""

from __future__ import annotations

import json
import os
import re
import uuid
from pathlib import Path

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.models.catalog import CatalogItem, CategoryType, ItemCategory
from app.models.contacts import Supplier

_REQUIRED_SEED_NAMES = (
    "categories_seed.json",
    "products_by_category_seed.json",
    "suppliers_gst_seed.json",
)


def _has_all_seed_files(directory: Path) -> bool:
    return all((directory / n).is_file() for n in _REQUIRED_SEED_NAMES)


def resolve_seed_data_dir(override: Path | str | None = None) -> Path:
    """
    Preferred layout: <repo root>/data/files/*.json (see /data/files/README.md).
    Falls back to backend/scripts/data when data/files is incomplete.
    """
    if override is not None:
        p = Path(override).expanduser().resolve()
        if not _has_all_seed_files(p):
            missing = [n for n in _REQUIRED_SEED_NAMES if not (p / n).is_file()]
            raise FileNotFoundError(
                f"SEED_DATA_DIR {p!s} is missing: {', '.join(missing)}"
            )
        return p
    env = (os.environ.get("SEED_DATA_DIR") or "").strip()
    if env:
        return resolve_seed_data_dir(Path(env))

    here = Path(__file__).resolve()
    # catalog_suppliers_seed.py → parents[3] = repo root (sibling to backend/)
    project_root = here.parents[3]
    data_files = project_root / "data" / "files"
    legacy = here.parents[2] / "scripts" / "data"
    if _has_all_seed_files(data_files):
        return data_files
    if _has_all_seed_files(legacy):
        return legacy
    return data_files


def _norm(s: str) -> str:
    return " ".join(s.strip().lower().split())


def _norm_unit(u: str) -> str:
    x = (u or "KG").strip().upper()
    if x in ("BAG", "KG-BAG"):
        return "bag"
    if x in ("KG", "KGS", "KG."):
        return "kg"
    if x in ("PCS", "PIECES", "PC", "PCS."):
        return "piece"
    if x == "BOX":
        return "box"
    if x == "TIN":
        return "tin"
    return "kg"


def _kg_per_bag_from_name(name: str) -> float | None:
    m = re.search(r"(\d+(?:\.\d+)?)\s*KG\b", name.upper())
    if not m:
        return None
    return float(m.group(1))


def _clean_phone(p: str | None) -> str | None:
    if not p:
        return None
    t = " ".join(p.replace("\n", " ").replace("\r", " ").split()).strip()
    return t or None


def run_catalog_suppliers_seed(
    db: Session,
    business_id: uuid.UUID,
    *,
    seed_data_dir: Path | str | None = None,
) -> dict[str, int]:
    """
    Insert default categories, types, items, and GST suppliers for [business_id] if missing.
    Commits nothing; caller must commit.
    """
    base = resolve_seed_data_dir(seed_data_dir)
    categories_path = base / "categories_seed.json"
    products_path = base / "products_by_category_seed.json"
    suppliers_path = base / "suppliers_gst_seed.json"

    for p in (categories_path, products_path, suppliers_path):
        if not p.is_file():
            raise FileNotFoundError(f"Seed data file missing: {p}")

    categories_data = json.loads(categories_path.read_text(encoding="utf-8"))
    products_data = json.loads(products_path.read_text(encoding="utf-8"))
    suppliers_data = json.loads(suppliers_path.read_text(encoding="utf-8"))

    stats = {
        "categories": 0,
        "types": 0,
        "items_inserted": 0,
        "items_skipped": 0,
        "suppliers_inserted": 0,
        "suppliers_skipped": 0,
    }

    type_key_to_ids: dict[str, tuple[uuid.UUID, uuid.UUID]] = {}

    for cat_blob in categories_data:
        parent_name = cat_blob["name"]
        q = select(ItemCategory).where(
            ItemCategory.business_id == business_id,
            func.lower(ItemCategory.name) == _norm(parent_name),
        )
        cat = db.execute(q).scalar_one_or_none()
        if cat is None:
            cat = ItemCategory(business_id=business_id, name=parent_name.strip())
            db.add(cat)
            db.flush()
            stats["categories"] += 1
        else:
            pass

        for sub in cat_blob.get("subcategories", []):
            tname = sub["name"]
            tq = select(CategoryType).where(
                CategoryType.category_id == cat.id,
                func.lower(CategoryType.name) == _norm(tname),
            )
            ct = db.execute(tq).scalar_one_or_none()
            if ct is None:
                ct = CategoryType(category_id=cat.id, name=tname.strip())
                db.add(ct)
                db.flush()
                stats["types"] += 1
            type_key_to_ids[tname] = (cat.id, ct.id)

    missing_keys = sorted(set(products_data.keys()) - set(type_key_to_ids.keys()))
    if missing_keys:
        raise ValueError(f"products JSON has types not in categories_seed: {missing_keys}")

    for type_key, rows in products_data.items():
        cat_id, type_id = type_key_to_ids[type_key]
        sub_meta = next(
            (
                s
                for blob in categories_data
                for s in blob.get("subcategories", [])
                if s["name"] == type_key
            ),
            {},
        )
        type_default_unit = _norm_unit(str(sub_meta.get("default_unit", "kg")))

        for row in rows:
            iname = (row.get("name") or "").strip()
            if not iname:
                continue
            hsn = (row.get("hsn") or sub_meta.get("hsn") or "")[:32].strip() or "00000000"
            tax = row.get("tax_rate")
            tax_percent = float(tax) if tax is not None else None
            pur = row.get("purchase_rate")
            default_landing = float(pur) if pur is not None else None
            du = _norm_unit(str(row.get("unit") or type_default_unit))
            kg_bag = _kg_per_bag_from_name(iname) if du == "bag" else None

            iq = select(CatalogItem).where(
                CatalogItem.business_id == business_id,
                CatalogItem.category_id == cat_id,
                CatalogItem.type_id == type_id,
                func.lower(CatalogItem.name) == _norm(iname),
            )
            if db.execute(iq).scalar_one_or_none():
                stats["items_skipped"] += 1
                continue
            item = CatalogItem(
                business_id=business_id,
                category_id=cat_id,
                type_id=type_id,
                name=iname,
                default_unit=du,
                default_purchase_unit=du,
                hsn_code=hsn,
                tax_percent=tax_percent,
                default_landing_cost=default_landing,
                default_kg_per_bag=kg_bag,
            )
            db.add(item)
            stats["items_inserted"] += 1

    for s in suppliers_data:
        name = (s.get("name") or "").strip()
        if not name:
            continue
        gst_raw = (s.get("gst") or "").strip().upper()
        gst = gst_raw or None
        if not gst or len(gst) != 15:
            continue
        sq = select(Supplier).where(
            Supplier.business_id == business_id,
            Supplier.gst_number == gst,
        )
        if db.execute(sq).scalar_one_or_none():
            stats["suppliers_skipped"] += 1
            continue
        sq2 = select(Supplier).where(
            Supplier.business_id == business_id,
            func.lower(Supplier.name) == _norm(name),
        )
        if db.execute(sq2).scalar_one_or_none():
            stats["suppliers_skipped"] += 1
            continue
        sup = Supplier(
            business_id=business_id,
            name=name,
            phone=_clean_phone(s.get("phone")),
            gst_number=gst,
            location=(s.get("address") or "").strip() or None,
            address=(s.get("address") or "").strip() or None,
        )
        db.add(sup)
        stats["suppliers_inserted"] += 1

    return stats
