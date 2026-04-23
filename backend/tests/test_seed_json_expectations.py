"""Static checks: seed JSON row counts match Harisree catalog expectations.

Run without DATABASE_URL. For live DB verification, use:
  python -m scripts.seed_catalog_and_suppliers --business-id=<uuid> [--dry-run]
and compare tenant-scoped SQL counts to these baselines.
"""

import json
from pathlib import Path

DATA_DIR = Path(__file__).resolve().parent.parent / "scripts" / "data"


def test_seed_json_category_and_product_counts():
    categories = json.loads((DATA_DIR / "categories_seed.json").read_text(encoding="utf-8"))
    products = json.loads((DATA_DIR / "products_by_category_seed.json").read_text(encoding="utf-8"))
    suppliers = json.loads((DATA_DIR / "suppliers_gst_seed.json").read_text(encoding="utf-8"))

    n_cat = len(categories)
    n_types = sum(len(b.get("subcategories", [])) for b in categories)
    n_items = sum(len(rows) for rows in products.values())
    n_sup = len(suppliers)

    assert n_cat == 9
    assert n_types == 62
    assert n_items >= 500
    assert n_sup >= 800
