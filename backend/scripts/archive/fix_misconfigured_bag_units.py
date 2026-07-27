"""Fix catalog rows: default_unit=kg but package_type=SACK with kg_per_bag (bag items).

Uses Render Postgres external connection (run locally). Auth from .cursor/mcp.json render token.
"""
from __future__ import annotations

import json
import sys
import urllib.request
from pathlib import Path

POSTGRES_ID = "dpg-d8fu1p77f7vs73eooiu0-a"
_REPO = Path(__file__).resolve().parents[2]


def _auth() -> str:
    mcp_path = _REPO / ".cursor" / "mcp.json"
    if not mcp_path.is_file():
        raise SystemExit("Missing .cursor/mcp.json with render API token")
    mcp = json.loads(mcp_path.read_text(encoding="utf-8"))
    servers = mcp.get("mcpServers", {})
    token = ""
    for key in ("render", "project-0-Purchase Assistant-render"):
        hdr = (servers.get(key, {}).get("headers") or {}).get("Authorization") or ""
        if hdr.strip():
            token = hdr.strip()
            break
    if not token:
        raise SystemExit("No render Authorization in mcp.json")
    return token if token.lower().startswith("bearer ") else f"Bearer {token}"


def _get(url: str) -> dict:
    req = urllib.request.Request(url, headers={"Authorization": _auth(), "Accept": "application/json"})
    with urllib.request.urlopen(req, timeout=60) as resp:
        return json.load(resp)


def main() -> None:
    info = _get(f"https://api.render.com/v1/postgres/{POSTGRES_ID}/connection-info")
    url = (info.get("externalConnectionString") or info.get("external_connection_string") or "").strip()
    if not url:
        raise SystemExit("No external connection string from Render API")

    try:
        import psycopg2
    except ImportError:
        raise SystemExit("pip install psycopg2-binary") from None

    conn = psycopg2.connect(url)
    conn.autocommit = False
    cur = conn.cursor()
    cur.execute(
        """
        SELECT id::text, name, default_unit, default_kg_per_bag, package_type
        FROM catalog_items
        WHERE lower(default_unit) = 'kg'
          AND upper(coalesce(package_type, '')) = 'SACK'
          AND default_kg_per_bag IS NOT NULL
          AND default_kg_per_bag > 0
        ORDER BY name
        LIMIT 50
        """
    )
    rows = cur.fetchall()
    print(f"Found {len(rows)} misconfigured bag-as-kg item(s)")
    for r in rows[:10]:
        print(" ", r)

    cur.execute(
        """
        UPDATE catalog_items
        SET default_unit = 'bag'
        WHERE lower(default_unit) = 'kg'
          AND upper(coalesce(package_type, '')) = 'SACK'
          AND default_kg_per_bag IS NOT NULL
          AND default_kg_per_bag > 0
        """
    )
    updated = cur.rowcount
    conn.commit()
    print(f"Updated default_unit to bag: {updated} row(s)")

    cur.execute(
        """
        SELECT id::text, name, default_unit, default_kg_per_bag
        FROM catalog_items
        WHERE name ILIKE '%ULUVA 30 KG%'
        """
    )
    print("ULUVA 30 KG after fix:", cur.fetchone())
    cur.close()
    conn.close()


if __name__ == "__main__":
    main()
