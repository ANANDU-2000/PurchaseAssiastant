"""Fix Harisree Vercel domains — canonical web URL only.

Reads VERCEL_TOKEN from .cursor/mcp.json (gitignored). Mirrors apply_render_env_cleanup.py.

Goals:
- purchase-assiastant.vercel.app → Production (no redirect)
- purchase-assistant.vercel.app (+ typos) → DELETE or 308 redirect to canonical
- Trigger production redeploy on Harisree Flutter project
"""
from __future__ import annotations

import json
import os
import urllib.error
import urllib.request
from pathlib import Path

_REPO = Path(__file__).resolve().parents[2]

CANONICAL_DOMAIN = "purchase-assiastant.vercel.app"
WRONG_DOMAINS = (
    "purchase-assistant.vercel.app",
    "purchase-assastant.vercel.app",
    "purchase-assiantant.vercel.app",
)
HARISREE_REPO_HINTS = ("purchaseassiastant", "purchase-assistant", "purchase_assistant")
KNOWN_HARISREE_PROJECT_ID = "prj_ubxhMkOxAG2tM7o88u7ZBEjZ0VMM"


def _token() -> str:
    env = os.environ.get("VERCEL_TOKEN", "").strip()
    if env:
        return env
    mcp_path = _REPO / ".cursor" / "mcp.json"
    if mcp_path.is_file():
        mcp = json.loads(mcp_path.read_text(encoding="utf-8"))
        vercel = mcp.get("mcpServers", {}).get("vercel", {})
        t = (vercel.get("env", {}).get("VERCEL_TOKEN") or vercel.get("headers", {}).get("Authorization") or "").strip()
        if t.lower().startswith("bearer "):
            t = t[7:].strip()
        if t:
            return t
    raise SystemExit("Set VERCEL_TOKEN in env or .cursor/mcp.json mcpServers.vercel.env")


def _request(method: str, url: str, payload: object | None = None) -> tuple[int, str]:
    headers = {"Authorization": f"Bearer {_token()}", "Accept": "application/json"}
    data = None
    if payload is not None:
        headers["Content-Type"] = "application/json"
        data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            return resp.status, resp.read().decode("utf-8", errors="replace")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8", errors="replace")


def _get_json(url: str) -> dict | list:
    status, body = _request("GET", url)
    if status >= 400:
        raise SystemExit(f"GET {url} -> HTTP {status}: {body[:800]}")
    return json.loads(body)


def _list_projects() -> list[dict]:
    out: list[dict] = []
    url = "https://api.vercel.com/v9/projects?limit=100"
    while url:
        payload = _get_json(url)
        if isinstance(payload, dict) and "projects" in payload:
            out.extend(payload["projects"])
            nxt = (payload.get("pagination") or {}).get("next")
            url = f"https://api.vercel.com{nxt}" if nxt else ""
        elif isinstance(payload, list):
            out.extend(payload)
            url = ""
        else:
            break
    return out


def _list_domains(project_id: str) -> list[dict]:
    payload = _get_json(f"https://api.vercel.com/v9/projects/{project_id}/domains?limit=100")
    if isinstance(payload, dict):
        return list(payload.get("domains") or [])
    if isinstance(payload, list):
        return payload
    return []


def _project_domain_map(projects: list[dict]) -> dict[str, tuple[str, dict]]:
    """domain -> (project_id, domain_record)"""
    mapping: dict[str, tuple[str, dict]] = {}
    for p in projects:
        pid = p.get("id") or ""
        if not pid:
            continue
        for d in _list_domains(pid):
            name = (d.get("name") or "").strip().lower()
            if name:
                mapping[name] = (pid, d)
    return mapping


def _find_harisree_project(projects: list[dict]) -> dict | None:
    for p in projects:
        if p.get("id") == KNOWN_HARISREE_PROJECT_ID:
            return p
    for p in projects:
        link = (p.get("link") or {}) if isinstance(p.get("link"), dict) else {}
        repo = (link.get("repo") or link.get("slug") or "").lower()
        name = (p.get("name") or "").lower()
        if any(h in repo or h in name for h in HARISREE_REPO_HINTS):
            return p
    for p in projects:
        if (p.get("name") or "").lower() == "purchase-assistant":
            return p
    return None


def _patch_domain(project_id: str, domain: str, body: dict) -> None:
    status, resp = _request(
        "PATCH",
        f"https://api.vercel.com/v9/projects/{project_id}/domains/{domain}",
        body,
    )
    print(f"PATCH {domain} on {project_id}: HTTP {status} {body}")
    if status >= 400:
        print(resp[:500])


def _delete_domain(project_id: str, domain: str) -> bool:
    status, resp = _request(
        "DELETE",
        f"https://api.vercel.com/v9/projects/{project_id}/domains/{domain}",
    )
    print(f"DELETE {domain} from {project_id}: HTTP {status}")
    if status >= 400:
        print(resp[:500])
    return status in (200, 204)


def _redirect_domain(project_id: str, domain: str) -> None:
    _patch_domain(
        project_id,
        domain,
        {"redirect": CANONICAL_DOMAIN, "redirectStatusCode": 308, "gitBranch": None},
    )


def _clear_canonical(project_id: str) -> None:
    _patch_domain(
        project_id,
        CANONICAL_DOMAIN,
        {"redirect": None, "redirectStatusCode": None, "gitBranch": None},
    )


def _trigger_production_deploy(project: dict) -> None:
    pid = project.get("id") or ""
    name = project.get("name") or "purchase-assistant"
    link = project.get("link") if isinstance(project.get("link"), dict) else {}
    body: dict = {"name": name, "project": pid, "target": "production"}
    if link.get("type") == "github":
        body["gitSource"] = {
            "type": "github",
            "ref": link.get("productionBranch") or "main",
            "repoId": link.get("repoId"),
        }
    status, resp = _request("POST", "https://api.vercel.com/v13/deployments", body)
    print(f"deploy production for {name} ({pid}): HTTP {status}")
    if status >= 400:
        print(resp[:800])
    else:
        try:
            dep = json.loads(resp)
            print(f"  deployment id: {dep.get('id')} url: {dep.get('url')}")
        except json.JSONDecodeError:
            pass


def main() -> None:
    print("=== Vercel domain fix (Harisree) ===")
    print(f"canonical: {CANONICAL_DOMAIN}")

    projects = _list_projects()
    print(f"projects: {len(projects)}")
    for p in projects:
        print(f"  - {p.get('name')} ({p.get('id')})")

    domain_map = _project_domain_map(projects)
    print("\nDomain ownership:")
    for dom, (pid, rec) in sorted(domain_map.items()):
        redirect = rec.get("redirect")
        mark = " [canonical]" if dom == CANONICAL_DOMAIN else (" [wrong]" if dom in WRONG_DOMAINS else "")
        print(f"  {dom} -> {pid} redirect={redirect!r}{mark}")

    harisree = _find_harisree_project(projects)
    if not harisree:
        raise SystemExit("Could not find Harisree Vercel project")
    hp_id = harisree["id"]
    print(f"\nHarisree project: {harisree.get('name')} ({hp_id})")

    # Ensure canonical domain is on Harisree project and not redirecting to itself.
    if CANONICAL_DOMAIN in domain_map:
        owner_id, rec = domain_map[CANONICAL_DOMAIN]
        if owner_id != hp_id:
            print(f"WARN: {CANONICAL_DOMAIN} owned by {owner_id}, expected {hp_id}")
        if rec.get("redirect"):
            print(f"Clearing mistaken redirect on {CANONICAL_DOMAIN}")
            _clear_canonical(owner_id)
        else:
            _clear_canonical(owner_id)
    else:
        status, resp = _request(
            "POST",
            f"https://api.vercel.com/v10/projects/{hp_id}/domains",
            {"name": CANONICAL_DOMAIN},
        )
        print(f"ADD {CANONICAL_DOMAIN} to {hp_id}: HTTP {status}")
        if status >= 400:
            print(resp[:500])

    # Remove or redirect wrong domains.
    for wrong in WRONG_DOMAINS:
        if wrong not in domain_map:
            print(f"skip {wrong} (not attached to any project)")
            continue
        owner_id, _ = domain_map[wrong]
        if _delete_domain(owner_id, wrong):
            continue
        print(f"DELETE failed for {wrong}; setting 308 redirect to {CANONICAL_DOMAIN}")
        _redirect_domain(owner_id, wrong)

    print("\nTriggering production redeploy...")
    _trigger_production_deploy(harisree)
    print("\nDone. Bookmark: https://purchase-assiastant.vercel.app/home")


if __name__ == "__main__":
    main()
