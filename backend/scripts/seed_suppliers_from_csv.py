"""
Import suppliers from `data/supplers/Customer List.csv` (Name, GSTIN, PhoneNumbers, Address).

Idempotent per business: skips when an existing row matches GST (15 chars) or same
normalized name + phone (last 10 digits).

Run from `backend/`:

  set DATABASE_URL=postgresql://...
  python -m scripts.seed_suppliers_from_csv --business-id=<uuid> [--csv path] [--dry-run]
"""

from __future__ import annotations

import argparse
import csv
import os
import re
import sys
import uuid
from pathlib import Path

from sqlalchemy import func, select
from sqlalchemy import create_engine
from sqlalchemy.orm import Session, sessionmaker

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app.models.contacts import Supplier  # noqa: E402


def _sync_database_url() -> str:
    raw = (os.getenv("DATABASE_URL") or os.getenv("SQLALCHEMY_DATABASE_URI") or "").strip()
    if not raw:
        print("Set DATABASE_URL or SQLALCHEMY_DATABASE_URI", file=sys.stderr)
        sys.exit(1)
    if raw.startswith("sqlite"):
        return raw
    if "+asyncpg" in raw:
        raw = raw.replace("postgresql+asyncpg://", "postgresql://").replace(
            "postgres+asyncpg://", "postgres://"
        )
    elif raw.startswith("postgres://"):
        raw = "postgresql://" + raw.removeprefix("postgres://")
    return raw


def _norm_name(s: str) -> str:
    return " ".join(s.strip().lower().split())


def _digits_tail10(s: str) -> str:
    d = re.sub(r"\D", "", s or "")
    if len(d) >= 10:
        return d[-10:]
    return d


def _first_phone(raw: str | None) -> str | None:
    if not raw:
        return None
    for part in re.split(r"[,;/\n]+", raw):
        t = " ".join(part.split()).strip()
        if not t:
            continue
        if len(_digits_tail10(t)) >= 10:
            return t
    t = " ".join(raw.replace("\n", " ").split()).strip()
    return t or None


def _default_csv_path() -> Path:
    here = Path(__file__).resolve()
    root = here.parents[2]
    return root / "data" / "supplers" / "Customer List.csv"


def _read_rows(path: Path) -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    with path.open(encoding="utf-8-sig", newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
            m: dict[str, str] = {}
            for k, v in row.items():
                key = (k or "").strip()
                m[key] = v if isinstance(v, str) else ("" if v is None else str(v))
            rows.append(m)
    return rows


def _exists_duplicate(
    db: Session, business_id: uuid.UUID, name: str, phone: str | None, gst: str | None
) -> bool:
    if gst and len(gst) == 15:
        q = select(Supplier).where(
            Supplier.business_id == business_id,
            Supplier.gst_number == gst,
        )
        if db.execute(q).scalar_one_or_none():
            return True

    nq = _norm_name(name)
    if not nq:
        return True
    qn = select(Supplier).where(
        Supplier.business_id == business_id,
        func.lower(Supplier.name) == nq,
    )
    cands = list(db.execute(qn).scalars().all())
    pnew = _digits_tail10(phone or "")
    for s in cands:
        sold = _digits_tail10(s.phone or "")
        if pnew and sold and pnew == sold:
            return True
    if not pnew:
        for s in cands:
            if not _digits_tail10(s.phone or ""):
                return True
    return False


def run_seed_csv(
    db: Session,
    business_id: uuid.UUID,
    csv_path: Path,
) -> dict[str, int]:
    stats = {"inserted": 0, "skipped": 0, "bad_rows": 0}
    file_seen: set[tuple[str, str]] = set()
    for rec in _read_rows(csv_path):
        name = (rec.get("Name") or "").strip()
        if not name:
            stats["bad_rows"] += 1
            continue
        gst_raw = (rec.get("GSTIN") or "").strip().upper()
        gst: str | None = gst_raw if len(gst_raw) == 15 else None
        phone = _first_phone(rec.get("PhoneNumbers"))
        addr = (rec.get("Address") or "").strip() or None

        pk = _digits_tail10(phone or "")
        fd = (name.lower(), pk)
        if fd in file_seen:
            stats["skipped"] += 1
            continue
        file_seen.add(fd)

        if _exists_duplicate(db, business_id, name, phone, gst):
            stats["skipped"] += 1
            continue

        sup = Supplier(
            business_id=business_id,
            name=name[:255],
            phone=(phone or "")[:32] if phone else None,
            gst_number=gst,
            address=addr,
            location=addr,
        )
        db.add(sup)
        stats["inserted"] += 1

    return stats


def main() -> None:
    ap = argparse.ArgumentParser(description="Seed suppliers from Customer List.csv")
    ap.add_argument("--business-id", required=True)
    ap.add_argument(
        "--csv",
        type=Path,
        default=None,
        help="Default: <repo>/data/supplers/Customer List.csv",
    )
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()
    try:
        bid = uuid.UUID(str(args.business_id))
    except ValueError:
        print("Invalid --business-id", file=sys.stderr)
        sys.exit(1)
    path = args.csv or _default_csv_path()
    if not path.is_file():
        print(f"CSV not found: {path}", file=sys.stderr)
        sys.exit(1)
    url = _sync_database_url()
    engine = create_engine(url, future=True)
    SessionLocal = sessionmaker(bind=engine, future=True)
    with SessionLocal() as db:
        try:
            stats = run_seed_csv(db, bid, path)
            if args.dry_run:
                db.rollback()
                print("(rolled back dry-run)")
            else:
                db.commit()
        except Exception:
            db.rollback()
            raise
    print(
        "seed_suppliers_from_csv:",
        f"inserted {stats['inserted']}, skipped {stats['skipped']}, bad_rows {stats['bad_rows']}",
    )


if __name__ == "__main__":
    main()
