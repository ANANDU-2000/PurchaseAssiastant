"""
One-time Supabase → Render Postgres migration (public schema dump/restore).

Requires: Docker, backend/.env (Supabase), Render API key in RENDER_API_KEY or .cursor/mcp.json.

Does not print passwords. Writes harisree_supabase_YYYYMMDD.pgdump and restore_log.txt at repo root.

  cd backend
  python -m scripts.migrate_supabase_to_render
  python -m scripts.migrate_supabase_to_render --skip-dump   # restore only
  python -m scripts.migrate_supabase_to_render --alembic-only
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import urllib.request
from datetime import date
from pathlib import Path

_BACKEND = Path(__file__).resolve().parent.parent
_REPO = _BACKEND.parent


def _load_dotenv() -> None:
    p = _BACKEND / ".env"
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


def _render_api_key() -> str:
    key = (os.environ.get("RENDER_API_KEY") or "").strip()
    if key:
        return key if key.lower().startswith("bearer ") else f"Bearer {key}"
    mcp = _REPO / ".cursor" / "mcp.json"
    if mcp.is_file():
        data = json.loads(mcp.read_text(encoding="utf-8"))
        auth = (data.get("mcpServers", {}).get("render", {}).get("headers", {}).get("Authorization") or "").strip()
        if auth:
            return auth if auth.lower().startswith("bearer ") else f"Bearer {auth}"
    print("Set RENDER_API_KEY or configure .cursor/mcp.json render Authorization.", file=sys.stderr)
    sys.exit(1)


def _fetch_render_connection(postgres_id: str) -> dict[str, str]:
    req = urllib.request.Request(
        f"https://api.render.com/v1/postgres/{postgres_id}/connection-info",
        headers={"Authorization": _render_api_key(), "Accept": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=60) as resp:
        raw = json.load(resp)
    if isinstance(raw, list) and raw:
        raw = raw[0]
    if isinstance(raw, dict) and "connectionInfo" in raw:
        raw = raw["connectionInfo"]
    ext = (raw.get("externalConnectionString") or raw.get("external_connection_string") or "").strip()
    internal = (raw.get("internalConnectionString") or raw.get("internal_connection_string") or "").strip()
    if not ext:
        print("Render API returned no external connection string.", file=sys.stderr)
        sys.exit(1)
    return {"external": ext, "internal": internal}


def _supabase_session_uri() -> str:
    pw = (os.environ.get("DATABASE_POOLER_PASSWORD") or "").strip()
    pooler = (os.environ.get("DATABASE_POOLER_URL") or os.environ.get("DATABASE_URL") or "").strip()
    if not pw:
        print("Set DATABASE_POOLER_PASSWORD in backend/.env (Supabase DB password).", file=sys.stderr)
        sys.exit(1)
    from urllib.parse import quote_plus, urlparse

    # Prefer session pooler (5432) from .env host; fall back to direct db.* host.
    if pooler:
        u = urlparse(pooler.replace("postgresql+asyncpg://", "postgresql://"))
        host = u.hostname or "aws-1-ap-southeast-1.pooler.supabase.com"
        user_raw = (u.username or "postgres.xrkwlixlntujkhsaepbh").split("@")[-1]
        port = 5432  # session mode for pg_dump (not 6543 transaction pooler)
    else:
        host = "db.xrkwlixlntujkhsaepbh.supabase.co"
        user_raw = "postgres"
        port = 5432
    user = quote_plus(user_raw)
    password = quote_plus(pw)
    return f"postgresql://{user}:{password}@{host}:{port}/postgres?sslmode=require"


def _to_asyncpg(uri: str) -> str:
    u = uri.strip()
    if u.startswith("postgresql://"):
        return "postgresql+asyncpg://" + u.removeprefix("postgresql://")
    return u


def _pg_bin(name: str) -> str:
    for base in (
        Path(r"C:\Program Files\PostgreSQL\17\bin"),
        Path(r"C:\Program Files\PostgreSQL\16\bin"),
        Path("/usr/bin"),
    ):
        candidate = base / f"{name}.exe" if os.name == "nt" else base / name
        if candidate.is_file():
            return str(candidate)
    return name


def _run(cmd: list[str], *, log_path: Path | None = None, env: dict | None = None) -> int:
    label = cmd[0] if cmd else "command"
    print(f"Running: {Path(label).name} …")
    merged = os.environ.copy()
    if env:
        merged.update(env)
    proc = subprocess.Popen(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        env=merged,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    assert proc.stdout is not None
    lines: list[str] = []
    for line in proc.stdout:
        # Redact connection strings if echoed
        safe = re.sub(r"://[^@\s]+@", "://***@", line)
        print(safe, end="")
        lines.append(line)
    code = proc.wait()
    if log_path:
        log_path.write_text("".join(lines), encoding="utf-8")
    return code


def main() -> None:
    parser = argparse.ArgumentParser(description="Migrate Supabase public schema to Render Postgres")
    parser.add_argument("--postgres-id", default="dpg-d8fu1p77f7vs73eooiu0-a")
    parser.add_argument("--skip-dump", action="store_true")
    parser.add_argument("--skip-restore", action="store_true")
    parser.add_argument("--skip-extensions", action="store_true")
    parser.add_argument("--alembic-only", action="store_true")
    parser.add_argument("--cutover-api", action="store_true", help="Set Render DATABASE_URL (internal) and deploy API")
    parser.add_argument("--dump-file", default="")
    args = parser.parse_args()

    _load_dotenv()
    render = _fetch_render_connection(args.postgres_id)
    render_ext = render["external"]
    render_async = _to_asyncpg(render_ext)

    stamp = date.today().strftime("%Y%m%d")
    dump_path = Path(args.dump_file) if args.dump_file else _REPO / f"harisree_supabase_{stamp}.pgdump"
    restore_log = _REPO / "restore_log.txt"

    if args.cutover_api:
        cutover = Path(__file__).resolve().parent / "_render_cutover_env.py"
        rc = subprocess.call([sys.executable, str(cutover)])
        sys.exit(rc)

    if args.alembic_only:
        alembic_env = {
            "DATABASE_URL": render_async,
            "HEXA_USE_SQLITE": "",
            "DATABASE_POOLER_URL": "",
            "DATABASE_POOLER_PASSWORD": "",
            "SKIP_BACKEND_DOTENV": "1",
        }
        rc = _run([sys.executable, "-m", "alembic", "upgrade", "head"], env=alembic_env)
        sys.exit(rc)

    supa_uri = _supabase_session_uri()

    pg_dump = _pg_bin("pg_dump")
    pg_restore = _pg_bin("pg_restore")
    psql = _pg_bin("psql")

    if not args.skip_dump:
        rc = _run(
            [
                pg_dump,
                supa_uri,
                "--no-owner",
                "--no-acl",
                "--schema=public",
                "--format=custom",
                f"--file={dump_path}",
            ],
        )
        if rc != 0 or not dump_path.is_file() or dump_path.stat().st_size < 100:
            print("pg_dump failed or dump file missing/empty.", file=sys.stderr)
            sys.exit(rc or 1)
        print(f"Dump OK: {dump_path.name} ({dump_path.stat().st_size} bytes)")

    if args.skip_restore:
        sys.exit(0)

    if not dump_path.is_file():
        print(f"Dump not found: {dump_path}", file=sys.stderr)
        sys.exit(1)

    if not args.skip_extensions:
        ext_sql = "CREATE EXTENSION IF NOT EXISTS \"uuid-ossp\"; CREATE EXTENSION IF NOT EXISTS pg_trgm; CREATE EXTENSION IF NOT EXISTS pgcrypto;"
        rc = _run([psql, render_ext, "-v", "ON_ERROR_STOP=1", "-c", ext_sql])
        if rc != 0:
            print("Extension create failed (may already exist).", file=sys.stderr)

    rc = _run(
        [
            pg_restore,
            f"--dbname={render_ext}",
            "--no-owner",
            "--no-acl",
            "--disable-triggers",
            "--verbose",
            str(dump_path),
        ],
        log_path=restore_log,
    )
    errors = restore_log.read_text(encoding="utf-8", errors="replace")
    fatal = [ln for ln in errors.splitlines() if "pg_restore: error:" in ln and "already exists" not in ln.lower()]
    if fatal:
        print(f"pg_restore reported {len(fatal)} error line(s); see restore_log.txt", file=sys.stderr)
    elif rc != 0:
        print("pg_restore exited non-zero; review restore_log.txt", file=sys.stderr)

    os.environ["DATABASE_URL"] = render_async
    os.environ["HEXA_USE_SQLITE"] = ""
    alembic_env = {
        "DATABASE_URL": render_async,
        "HEXA_USE_SQLITE": "",
        "DATABASE_POOLER_URL": "",
        "DATABASE_POOLER_PASSWORD": "",
        # Prevent alembic/env.py load_dotenv(override=True) from replacing target URL with backend/.env.
        "SKIP_BACKEND_DOTENV": "1",
    }
    rc2 = _run([sys.executable, "-m", "alembic", "current"], env=alembic_env)
    rc3 = _run([sys.executable, "-m", "alembic", "upgrade", "head"], env=alembic_env)
    sys.exit(max(rc, rc2, rc3))


if __name__ == "__main__":
    main()
