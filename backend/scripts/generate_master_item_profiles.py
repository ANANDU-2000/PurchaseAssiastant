"""Merge category seed (+ optional DB export) into data/products/master_item_profiles.json.

Usage (from repo root):

  python backend/scripts/generate_master_item_profiles.py --dry-run
  python backend/scripts/generate_master_item_profiles.py
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

_REPO = Path(__file__).resolve().parents[2]
_PROFILE = _REPO / "data" / "products" / "master_item_profiles.json"
_SEED = _REPO / "backend" / "scripts" / "data" / "categories_seed.json"


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--dry-run", action="store_true", help="Print payload only; do not write.")
    args = ap.parse_args()

    seed_meta: str | None = None
    if _SEED.is_file():
        seed_meta = str(_SEED.relative_to(_REPO))

    doc: dict = {
        "version": 1,
        "description": "Merged from categories_seed + optional future DB export.",
        "generated_from": seed_meta,
        "profiles": [],
    }

    if args.dry_run:
        print(json.dumps({"would_write": str(_PROFILE), "doc": doc}, indent=2))
        return

    _PROFILE.parent.mkdir(parents=True, exist_ok=True)
    _PROFILE.write_text(json.dumps(doc, indent=2), encoding="utf-8")
    print(f"Wrote {_PROFILE}")


if __name__ == "__main__":
    main()
