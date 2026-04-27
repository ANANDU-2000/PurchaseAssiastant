from __future__ import annotations

import os
import sys
from pathlib import Path

from sqlalchemy import create_engine, select, text
from sqlalchemy.orm import sessionmaker

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app.models import Business  # noqa: E402
from app.services.catalog_suppliers_seed import run_catalog_suppliers_seed  # noqa: E402
from app.services.mandatory_workspace_seed import run_mandatory_workspace_seed  # noqa: E402


def _sync_database_url() -> str:
    raw = (os.getenv("DATABASE_URL") or os.getenv("SQLALCHEMY_DATABASE_URI") or "").strip()
    if not raw:
        raise RuntimeError("DATABASE_URL not set")
    if raw.startswith("sqlite"):
        raise RuntimeError("DATABASE_URL is sqlite; need Postgres")
    if "+asyncpg" in raw:
        raw = raw.replace("postgresql+asyncpg://", "postgresql://").replace("postgres+asyncpg://", "postgres://")
    if raw.startswith("postgres://"):
        raw = "postgresql://" + raw.removeprefix("postgres://")
    return raw


def main() -> int:
    seed_dir = Path(__file__).resolve().parents[2] / "data" / "files"
    dsn = _sync_database_url()
    engine = create_engine(dsn, future=True, pool_pre_ping=True)
    SessionLocal = sessionmaker(bind=engine, future=True)
    ok = 0
    err = 0
    with SessionLocal() as db:
        db.execute(text("SET statement_timeout = 0"))
        bids = list(db.execute(select(Business.id)).scalars().all())
        print(f"business_count={len(bids)}", flush=True)
        for bid in bids:
            try:
                with db.no_autoflush:
                    stats = run_catalog_suppliers_seed(db, bid, seed_data_dir=seed_dir)
                    mandatory = run_mandatory_workspace_seed(db, bid)
                for k, v in mandatory.items():
                    stats[f"mandatory_{k}"] = v
                db.commit()
                ok += 1
                print(f"OK {bid} {stats}", flush=True)
            except Exception as e:  # noqa: BLE001
                db.rollback()
                err += 1
                print(f"ERR {bid} {e}", flush=True)
    print(f"done ok={ok} err={err}", flush=True)
    return 0 if err == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())

