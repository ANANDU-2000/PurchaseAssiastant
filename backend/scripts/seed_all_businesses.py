"""
Idempotent Harisree catalog + suppliers seed for every business row.

  cd backend
  set DATABASE_URL=...   (or use pooler vars like the API)
  python -m scripts.seed_all_businesses [--dry-run]

Requires the same JSON seed files as seed_catalog_and_suppliers.py.
"""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

from sqlalchemy import create_engine, select
from sqlalchemy.orm import Session, sessionmaker

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app.models import Business  # noqa: E402
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
        raw = raw.replace("postgresql+asyncpg://", "postgresql://").replace(
            "postgres+asyncpg://", "postgres://"
        )
    if raw.startswith("postgres://"):
        raw = "postgresql://" + raw.removeprefix("postgres://")
    return raw


def main() -> None:
    ap = argparse.ArgumentParser(
        description="Run catalog+supplier seed for all businesses (idempotent per business).",
    )
    ap.add_argument(
        "--dry-run",
        action="store_true",
        help="Run then ROLLBACK all changes (nothing persisted).",
    )
    ap.add_argument(
        "--seed-dir",
        type=Path,
        default=None,
        help="Override seed JSON directory (default: data/files or backend/scripts/data).",
    )
    args = ap.parse_args()
    url = _sync_database_url()
    engine = create_engine(url, future=True)
    SessionLocal = sessionmaker(bind=engine, future=True)
    seed_dir: Path | None = args.seed_dir

    with SessionLocal() as db:
        bids = list(db.execute(select(Business.id)).scalars().all())
        if not bids:
            print("No businesses found.")
            return
        all_ok = True
        for bid in bids:
            try:
                stats = run_catalog_suppliers_seed(db, bid, seed_data_dir=seed_dir)
                print(f"business {bid}: {stats}")
                if not args.dry_run:
                    db.commit()
            except Exception as e:  # noqa: BLE001
                all_ok = False
                db.rollback()
                print(f"business {bid}: ERROR {e}", file=sys.stderr)
        if args.dry_run:
            db.rollback()
            print("(dry-run: rolled back)")
    if not all_ok:
        sys.exit(1)


if __name__ == "__main__":
    main()
