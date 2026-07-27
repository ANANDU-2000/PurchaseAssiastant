"""Set Render API DATABASE_URL to internal Postgres; clear pooler vars; trigger deploy."""
from __future__ import annotations

import json
import urllib.error
import urllib.request
from pathlib import Path

SERVICE_ID = "srv-d7ea0il8nd3s73e4fvl0"
POSTGRES_ID = "dpg-d8fu1p77f7vs73eooiu0-a"
_REPO = Path(__file__).resolve().parents[2]


def _auth() -> str:
    mcp = json.loads((_REPO / ".cursor" / "mcp.json").read_text(encoding="utf-8"))
    token = (mcp.get("mcpServers", {}).get("render", {}).get("headers", {}).get("Authorization") or "").strip()
    return token if token.lower().startswith("bearer ") else f"Bearer {token}"


def _get(url: str) -> dict:
    req = urllib.request.Request(url, headers={"Authorization": _auth(), "Accept": "application/json"})
    with urllib.request.urlopen(req, timeout=60) as resp:
        return json.load(resp)


def _delete(url: str) -> int:
    req = urllib.request.Request(
        url,
        headers={"Authorization": _auth(), "Accept": "application/json"},
        method="DELETE",
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            return resp.status
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return 404
        print("HTTP", e.code, e.read().decode("utf-8", errors="replace")[:800])
        raise


def _post_json(url: str, payload: object | None = None) -> int:
    body = json.dumps(payload or {}).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=body,
        headers={"Authorization": _auth(), "Content-Type": "application/json", "Accept": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=120) as resp:
        return resp.status


def _put_json(url: str, payload: object) -> int:
    body = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=body,
        headers={"Authorization": _auth(), "Content-Type": "application/json", "Accept": "application/json"},
        method="PUT",
    )
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            return resp.status
    except urllib.error.HTTPError as e:
        print("HTTP", e.code, e.read().decode("utf-8", errors="replace")[:800])
        raise


def main() -> None:
    info = _get(f"https://api.render.com/v1/postgres/{POSTGRES_ID}/connection-info")
    internal = (info.get("internalConnectionString") or info.get("internal_connection_string") or "").strip()
    if not internal:
        raise SystemExit("missing internal connection string")
    db_url = internal.replace("postgresql://", "postgresql+asyncpg://", 1)
    if ".singapore-postgres.render.com" in db_url:
        raise SystemExit("expected internal host, got external")

    # Render API: PUT env-vars replaces one var per request in some versions; use bulk endpoint.
    status = _put_json(
        f"https://api.render.com/v1/services/{SERVICE_ID}/env-vars/DATABASE_URL",
        {"value": db_url},
    )
    print(f"set DATABASE_URL: HTTP {status}")

    for key in ("DATABASE_POOLER_URL", "DATABASE_POOLER_PASSWORD", "HEXA_USE_SQLITE"):
        del_status = _delete(f"https://api.render.com/v1/services/{SERVICE_ID}/env-vars/{key}")
        print(f"delete {key}: HTTP {del_status}")

    deploy_status = _post_json(f"https://api.render.com/v1/services/{SERVICE_ID}/deploys")
    print("deploy triggered: HTTP", deploy_status)


if __name__ == "__main__":
    main()
