"""
One-shot operator flow for Supabase / Postgres: preflight, Alembic, optional list + seed.

Does not print connection secrets. Use the same DATABASE_URL the deployed API will use
(postgresql+asyncpg:// or postgresql://).

  cd backend
  $env:HEXA_USE_SQLITE = ""
  $env:DATABASE_URL = "postgresql+asyncpg://..."
  python -m scripts.op_supabase_stack
  python -m scripts.op_supabase_stack --seed --business-id <uuid>
"""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
from pathlib import Path

# Allow `python -m scripts.op_supabase_stack` from backend/
_BACKEND_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(_BACKEND_ROOT))


def _load_backend_dotenv() -> None:
    """If DATABASE_URL is unset, read KEY=VAL from backend/.env (no multiline; first = only)."""
    if os.environ.get("DATABASE_URL") or os.environ.get("SQLALCHEMY_DATABASE_URI"):
        return
    p = _BACKEND_ROOT / ".env"
    if not p.is_file():
        return
    for line in p.read_text(encoding="utf-8", errors="replace").splitlines():
        s = line.strip()
        if not s or s.startswith("#") or "=" not in s:
            continue
        k, _, v = s.partition("=")
        k, v = k.strip(), v.strip().strip("'").strip('"')
        if k and k not in os.environ:
            os.environ[k] = v


def _is_postgres_dsn(url: str) -> bool:
    u = url.strip().lower()
    return u.startswith("postgresql+asyncpg://") or u.startswith("postgres+asyncpg://") or u.startswith(
        "postgresql://"
    ) or u.startswith("postgres://")


def _to_sync_dsn(url: str) -> str:
    u = url.strip()
    if u.startswith("postgresql+asyncpg://"):
        return "postgresql://" + u.removeprefix("postgresql+asyncpg://")
    if u.startswith("postgres+asyncpg://"):
        return "postgresql://" + u.removeprefix("postgres+asyncpg://")
    if u.startswith("postgres://"):
        return "postgresql://" + u.removeprefix("postgres://")
    return u


def _connect_args_for_url(sync_url: str) -> dict:
    args = dict(CONNECT_ARGS)
    low = sync_url.lower()
    if "supabase.co" in low or "pooler.supabase.com" in low:
        args.setdefault("sslmode", "require")
    return args


def _require_postgres() -> str:
    raw = (os.environ.get("DATABASE_URL") or os.environ.get("SQLALCHEMY_DATABASE_URI") or "").strip()
    if not raw or raw.startswith("sqlite"):
        print(
            "Set DATABASE_URL to a PostgreSQL DSN (not SQLite). "
            "For local Supabase, paste postgresql+asyncpg:// from the dashboard; "
            "clear HEXA_USE_SQLITE in this shell.",
            file=sys.stderr,
        )
        sys.exit(1)
    if not _is_postgres_dsn(raw):
        print("DATABASE_URL does not look like PostgreSQL; aborting.", file=sys.stderr)
        sys.exit(1)
    hx = (os.environ.get("HEXA_USE_SQLITE") or "").strip().lower()
    if hx in ("1", "true", "yes"):
        print(
            "HEXA_USE_SQLITE is enabled — migrations would still run, but the API would use SQLite. "
            "Run:  $env:HEXA_USE_SQLITE = ''  (or remove from .env on the host).",
            file=sys.stderr,
        )
        sys.exit(1)
    return raw


def _alembic_upgrade() -> None:
    code = subprocess.run(
        [sys.executable, "-m", "alembic", "upgrade", "head"],
        cwd=str(_BACKEND_ROOT),
        env={**os.environ, "HEXA_USE_SQLITE": ""},
    ).returncode
    if code != 0:
        sys.exit(code)
    print("ok: alembic upgrade head\n")


def _verify() -> None:
    _require_postgres()
    dsn = _to_sync_dsn((os.environ.get("DATABASE_URL") or "").strip())
    os.environ["CHECK_DATABASE_URL"] = dsn
    if "supabase.co" in dsn.lower() or "pooler.supabase.com" in dsn.lower():
        os.environ["CHECK_DATABASE_SSL"] = "1"
    from scripts.verify_db_connection import main as verify_main

    verify_main()


def _list_businesses() -> None:
    from sqlalchemy import create_engine, text

    dsn = _to_sync_dsn((os.environ.get("DATABASE_URL") or "").strip())
    eng = create_engine(dsn, connect_args=_connect_args_for_url(dsn), pool_pre_ping=True, future=True)
    with eng.connect() as c:
        rows = c.execute(
            text("select id, name, created_at from businesses order by created_at asc limit 50")
        ).fetchall()
    print("businesses (up to 50):")
    if not rows:
        print("  (none — create an account on the API first)")
    for bid, name, created in rows:
        print(f"  {bid}  {name!r}  {created}")


def _seed(business_id: str) -> None:
    code = subprocess.run(
        [sys.executable, "-m", "scripts.seed_catalog_and_suppliers", "--business-id", business_id],
        cwd=str(_BACKEND_ROOT),
        env={**os.environ, "HEXA_USE_SQLITE": ""},
    ).returncode
    if code != 0:
        sys.exit(code)


def _seed_all_businesses(seed_dir: str | None = None, dry_run: bool = False) -> None:
    cmd = [sys.executable, "-m", "scripts.seed_all_businesses"]
    if seed_dir:
        cmd.extend(["--seed-dir", seed_dir])
    if dry_run:
        cmd.append("--dry-run")
    code = subprocess.run(
        cmd,
        cwd=str(_BACKEND_ROOT),
        env={**os.environ, "HEXA_USE_SQLITE": ""},
    ).returncode
    if code != 0:
        sys.exit(code)


def main() -> None:
    _load_backend_dotenv()
    ap = argparse.ArgumentParser(description="Supabase/Postgres: verify, migrate, list businesses, optional seed")
    ap.add_argument("--no-verify", action="store_true", help="Skip verify_db_connection")
    ap.add_argument("--no-alembic", action="store_true", help="Skip alembic upgrade head")
    ap.add_argument("--list-businesses", action="store_true", help="Print businesses id/name after other steps")
    ap.add_argument("--seed", action="store_true", help="Run seed_catalog_and_suppliers after other steps")
    ap.add_argument("--business-id", default="", help="With --seed: businesses.id UUID")
    ap.add_argument(
        "--seed-all-businesses",
        action="store_true",
        help="Run seed_all_businesses (JSON + mandatory defaults) for every business.",
    )
    ap.add_argument(
        "--seed-all-dry-run",
        action="store_true",
        help="With --seed-all-businesses: run rollback preview only.",
    )
    ap.add_argument(
        "--seed-dir",
        default="",
        help="Optional seed JSON directory override for --seed-all-businesses.",
    )
    args = ap.parse_args()

    _ = _require_postgres()

    if not args.no_verify:
        print("--- verify (tables, counts, alembic_version) ---\n")
        _verify()
        print()
    if not args.no_alembic:
        print("--- alembic upgrade head ---\n")
        _alembic_upgrade()
    if args.list_businesses or (args.seed and not args.business_id):
        print("--- list businesses ---\n")
        _list_businesses()
        print()
    if args.seed:
        if not args.business_id:
            print("error: --seed requires --business-id", file=sys.stderr)
            sys.exit(1)
        print("--- seed catalog + suppliers ---\n")
        _seed(args.business_id)
        print()
    if args.seed_all_businesses:
        print("--- seed all businesses (json + mandatory) ---\n")
        _seed_all_businesses(
            seed_dir=(args.seed_dir or "").strip() or None,
            dry_run=bool(args.seed_all_dry_run),
        )
        print()
    if not args.list_businesses and not args.seed and not args.seed_all_businesses:
        print("--- list businesses (hint: use --list-businesses to show UUIDs) ---\n")
        _list_businesses()
        print()

    print("done.")


if __name__ == "__main__":
    main()
