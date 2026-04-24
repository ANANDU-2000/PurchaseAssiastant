"""Ensure products_by_category keys match subcategory names in categories_seed (same as seed service)."""

from __future__ import annotations

import json
from pathlib import Path

from app.services.catalog_suppliers_seed import resolve_seed_data_dir


def _load_seed_dir() -> Path:
    return resolve_seed_data_dir(None)


def _subcategory_names(categories: list) -> set[str]:
    out: set[str] = set()
    for blob in categories:
        for sub in blob.get("subcategories", []):
            name = (sub.get("name") or "").strip()
            if name:
                out.add(name)
    return out


def test_products_keys_match_category_subtypes():
    base = _load_seed_dir()
    categories = json.loads((base / "categories_seed.json").read_text(encoding="utf-8"))
    products = json.loads((base / "products_by_category_seed.json").read_text(encoding="utf-8"))

    types_set = _subcategory_names(categories)
    product_keys = set(products.keys())

    missing_in_categories = sorted(product_keys - types_set)
    assert not missing_in_categories, (
        "products_by_category_seed.json has keys not present as subcategory name in "
        f"categories_seed.json: {missing_in_categories[:50]}"
        + (f" ... and {len(missing_in_categories) - 50} more" if len(missing_in_categories) > 50 else "")
    )
