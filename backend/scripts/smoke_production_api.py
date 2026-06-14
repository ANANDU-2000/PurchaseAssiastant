"""Production API smoke checks (no secrets in output).

Usage:
  python -m scripts.smoke_production_api
  API_BASE=https://my-purchases-api.onrender.com python -m scripts.smoke_production_api
  CORS_ORIGIN=https://purchase-assiastant.vercel.app python -m scripts.smoke_production_api
"""
from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

API_BASE = os.environ.get("API_BASE", "https://my-purchases-api.onrender.com").rstrip("/")
CORS_ORIGIN = os.environ.get(
    "CORS_ORIGIN", "https://purchase-assiastant.vercel.app"
).strip()


def _get(path: str, *, origin: str | None = None) -> tuple[int, dict[str, str], str]:
    headers = {"Accept": "application/json"}
    if origin:
        headers["Origin"] = origin
    req = urllib.request.Request(f"{API_BASE}{path}", headers=headers, method="GET")
    try:
        with urllib.request.urlopen(req, timeout=45) as resp:
            body = resp.read().decode("utf-8", errors="replace")
            hdrs = {k.lower(): v for k, v in resp.headers.items()}
            return resp.status, hdrs, body
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="replace")
        hdrs = {k.lower(): v for k, v in e.headers.items()}
        return e.code, hdrs, body


def _options(
    path: str,
    *,
    origin: str,
    request_method: str = "GET",
    request_headers: str = "authorization,content-type",
) -> tuple[int, dict[str, str], str]:
    headers = {
        "Origin": origin,
        "Access-Control-Request-Method": request_method,
        "Access-Control-Request-Headers": request_headers,
    }
    req = urllib.request.Request(f"{API_BASE}{path}", headers=headers, method="OPTIONS")
    try:
        with urllib.request.urlopen(req, timeout=45) as resp:
            body = resp.read().decode("utf-8", errors="replace")
            hdrs = {k.lower(): v for k, v in resp.headers.items()}
            return resp.status, hdrs, body
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="replace")
        hdrs = {k.lower(): v for k, v in e.headers.items()}
        return e.code, hdrs, body


def _ok(name: str, cond: bool, detail: str = "") -> bool:
    mark = "PASS" if cond else "FAIL"
    print(f"[{mark}] {name}" + (f" — {detail}" if detail else ""))
    return cond


def main() -> int:
    print(f"API_BASE={API_BASE}")
    all_ok = True

    code, _, body = _get("/health/live")
    all_ok &= _ok("health/live", code == 200 and '"alive"' in body, f"HTTP {code}")

    code, _, body = _get("/health/ready")
    ready_ok = code == 200
    if ready_ok:
        try:
            data = json.loads(body)
            db_ok = data.get("db") == "ok"
            schema_ok = data.get("schema_ok") is True
            all_ok &= _ok("health/ready db", db_ok, str(data.get("db")))
            all_ok &= _ok("health/ready schema", schema_ok, str(data.get("alembic_version")))
        except json.JSONDecodeError:
            all_ok &= _ok("health/ready json", False, "invalid JSON")
    else:
        all_ok &= _ok("health/ready", False, f"HTTP {code}")

    if CORS_ORIGIN:
        code, hdrs, _ = _get("/health/live", origin=CORS_ORIGIN)
        cors = hdrs.get("access-control-allow-origin", "")
        all_ok &= _ok(
            "cors",
            cors == CORS_ORIGIN,
            f"allow-origin={cors!r}",
        )

        preflight_path = (
            "/v1/businesses/00000000-0000-0000-0000-000000000001"
            "/reports/home-overview"
            "?from=2026-05-16&to=2026-06-14&tz_offset_minutes=330"
            "&compact=true&shell_bundle=true"
        )
        code, hdrs, _ = _options(preflight_path, origin=CORS_ORIGIN)
        cors = hdrs.get("access-control-allow-origin", "")
        methods = hdrs.get("access-control-allow-methods", "")
        all_ok &= _ok(
            "cors preflight home-overview",
            code in (200, 204) and cors == CORS_ORIGIN and "GET" in methods.upper(),
            f"HTTP {code} allow-origin={cors!r} methods={methods!r}",
        )

    print("done:", "OK" if all_ok else "ISSUES")
    return 0 if all_ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
