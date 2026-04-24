"""
Validate categories_seed.json vs products_by_category_seed.json (same rules as seed service).

  cd backend
  python -m scripts.validate_seed_data
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app.services.catalog_suppliers_seed import resolve_seed_data_dir  # noqa: E402


def main() -> int:
    base = resolve_seed_data_dir(None)
    categories = json.loads((base / "categories_seed.json").read_text(encoding="utf-8"))
    products = json.loads((base / "products_by_category_seed.json").read_text(encoding="utf-8"))

    types_set: set[str] = set()
    for blob in categories:
        for sub in blob.get("subcategories", []):
            name = (sub.get("name") or "").strip()
            if name:
                types_set.add(name)

    missing = sorted(set(products.keys()) - types_set)
    if missing:
        print("ERROR: product keys not in categories subcategory names:", file=sys.stderr)
        for m in missing[:80]:
            print(f"  {m!r}", file=sys.stderr)
        if len(missing) > 80:
            print(f"  ... and {len(missing) - 80} more", file=sys.stderr)
        return 1

    empty = sorted(types_set - set(products.keys()))
    if empty:
        print(f"Note: {len(empty)} subcategories have no product rows (OK if intentional).")
    print("OK:", base)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
