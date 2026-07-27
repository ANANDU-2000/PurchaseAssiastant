"""
Idempotent seed: categories (ItemCategory + CategoryType), catalog items, GST suppliers,
optional brokers from data/brokers_seed.json.

Run from backend/:

  cd backend
  set DATABASE_URL=postgresql://...
  python -m scripts.seed_catalog_and_suppliers --business-id=<uuid> [--dry-run]

Production (Supabase): use the same DATABASE_URL as the API (e.g. postgresql+asyncpg://…),
do not set HEXA_USE_SQLITE in that shell, then pass the live workspace UUID from
`select id, name from businesses;` in the Supabase SQL editor.

--dry-run performs inserts then ROLLBACK (safe preview against a real DB).

Requires: DATABASE_URL or SQLALCHEMY_DATABASE_URI (postgresql+asyncpg is converted for sync drivers).
"""

from __future__ import annotations

import argparse
import os
import sys
import uuid
from pathlib import Path

from sqlalchemy import create_engine
from sqlalchemy.orm import Session, sessionmaker

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app.services.catalog_suppliers_seed import run_catalog_suppliers_seed  # noqa: E402


def _sync_database_url() -> str:
    raw = (os.getenv("DATABASE_URL") or os.getenv("SQLALCHEMY_DATABASE_URI") or "").strip()
    if not raw:
        print("Set DATABASE_URL or SQLALCHEMY_DATABASE_URI", file=sys.stderr)
        sys.exit(1)
    if "sqlite+aiosqlite" in raw:
        return raw.replace("sqlite+aiosqlite", "sqlite", 1)
    if raw.startswith("sqlite"):
        return raw
    if "+asyncpg" in raw:
        raw = raw.replace("postgresql+asyncpg://", "postgresql://").replace("postgres+asyncpg://", "postgres://")
    elif raw.startswith("postgres://"):
        raw = "postgresql://" + raw.removeprefix("postgres://")
    return raw


def run_seed(
    business_id: uuid.UUID,
    dry_run: bool,
    seed_dir: Path | None = None,
) -> None:
    url = _sync_database_url()
    engine = create_engine(url, future=True)
    SessionLocal = sessionmaker(bind=engine, future=True)

    with SessionLocal() as db:
        try:
            stats = run_catalog_suppliers_seed(
                db,
                business_id,
                seed_data_dir=seed_dir,
            )
            if dry_run:
                db.rollback()
                print("(rolled back dry-run)")
            else:
                db.commit()
        except Exception:
            db.rollback()
            raise

    print(
        "Summary:",
        f"categories +{stats['categories']}",
        f"types +{stats['types']}",
        f"items +{stats['items_inserted']} skipped {stats['items_skipped']}",
        f"suppliers +{stats['suppliers_inserted']} skipped {stats['suppliers_skipped']}",
        f"brokers +{stats['brokers_inserted']} skipped {stats['brokers_skipped']}",
    )


def main() -> None:
    ap = argparse.ArgumentParser(description="Seed catalog + GST suppliers for one business.")
    ap.add_argument("--business-id", required=True, help="UUID of the business (owner tenant).")
    ap.add_argument(
        "--dry-run",
        action="store_true",
        help="Run all INSERTs in a transaction then ROLLBACK (no persistent changes).",
    )
    ap.add_argument(
        "--seed-dir",
        type=Path,
        default=None,
        help="Directory with categories_seed.json, products_by_category_seed.json, suppliers_gst_seed.json "
        "(default: <repo>/data/files or backend/scripts/data).",
    )
    args = ap.parse_args()
    try:
        bid = uuid.UUID(str(args.business_id))
    except ValueError:
        print("Invalid --business-id", file=sys.stderr)
        sys.exit(1)
    run_seed(bid, args.dry_run, seed_dir=args.seed_dir)


if __name__ == "__main__":
    main()
