"""Generate PROJECT_API_AUDIT.md from FastAPI route table."""
from __future__ import annotations

from collections import defaultdict
from pathlib import Path

from app.main import app

rows: list[tuple[str, str, str, str]] = []
for r in app.routes:
    methods = getattr(r, "methods", None)
    path = getattr(r, "path", None)
    if not path or not methods:
        continue
    for m in sorted(methods):
        if m in ("HEAD", "OPTIONS"):
            continue
        ep = getattr(r, "endpoint", None)
        mod = getattr(ep, "__module__", "") if ep else ""
        name = getattr(r, "name", "") or (ep.__name__ if ep else "")
        rows.append((m, path, mod, name))
rows = sorted(set(rows), key=lambda x: (x[1], x[0]))


def domain(path: str, mod: str) -> str:
    p = path.lower()
    if p.startswith("/health") or p in (
        "/",
        "/docs",
        "/redoc",
        "/openapi.json",
        "/docs/oauth2-redirect",
    ):
        return "Health APIs"
    if "/auth/" in p or p.startswith("/v1/me"):
        return "Authentication"
    if "/reports/" in p or "report-views" in p:
        return "Reports"
    if "/stock" in p:
        return "Stock"
    if "/trade-purchases" in p or "/damage" in p:
        return "Purchase"
    if "/suppliers" in p or "/brokers" in p or "/contacts" in p:
        return "Supplier"
    if "/notifications" in p:
        return "Notifications"
    if "/users" in p or "/activity-log" in p:
        return "Users"
    if "/catalog" in p or "/item-categor" in p or "/category-types" in p:
        return "Inventory"
    if "/exports" in p:
        return "Exports"
    if "/operations" in p:
        return "Warehouse"
    if "/realtime" in p:
        return "Internal APIs"
    if "/public/" in p:
        return "Other discovered APIs"
    if "/search" in p:
        return "Utilities"
    if "/media" in p:
        return "Uploads"
    if "dashboard" in mod:
        return "Dashboard"
    return "Other discovered APIs"


by: dict[str, list] = defaultdict(list)
for m, p, mod, n in rows:
    by[domain(p, mod)].append((m, p, mod, n))

auth_status = {
    ("POST", "/v1/auth/refresh"): ("COMPLETED", "Critical", "AUTH-C1 fixed 9d50148"),
    ("POST", "/v1/auth/login"): ("FIXING", "High", "AUTH-H1 next"),
    ("POST", "/v1/auth/register"): ("COMPLETED", "Low", "Prod 403 by design"),
    ("POST", "/v1/auth/google"): ("DISCOVERED", "High", "AUTH-H4 latent"),
    ("POST", "/v1/auth/forgot-password"): (
        "BLOCKED",
        "High",
        "AUTH-H2 needs email product decision",
    ),
    ("POST", "/v1/auth/reset-password"): ("DISCOVERED", "Medium", "Depends AUTH-H2"),
    ("GET", "/v1/me/profile"): ("COMPLETED", "Low", "Working prod"),
    ("PATCH", "/v1/me/profile"): ("DISCOVERED", "Low", "Unused by Flutter"),
    ("GET", "/v1/me/businesses"): ("COMPLETED", "Low", "Working prod"),
    ("POST", "/v1/me/bootstrap-workspace"): ("COMPLETED", "Medium", "Working; slow"),
    ("PATCH", "/v1/me/businesses/{business_id}/branding"): (
        "DISCOVERED",
        "Medium",
        "",
    ),
    ("POST", "/v1/me/businesses/{business_id}/branding/logo"): (
        "BLOCKED",
        "High",
        "AUTH-H3 ephemeral disk",
    ),
}
health_done = {("/", "GET"), ("/health", "GET"), ("/health/ready", "GET"), ("/health/live", "GET")}

sections_order = [
    "Authentication",
    "Dashboard",
    "Home",
    "Stock",
    "Purchase",
    "Purchase Orders",
    "Sales",
    "Inventory",
    "Warehouse",
    "Supplier",
    "Customer",
    "Reports",
    "Notifications",
    "Settings",
    "Users",
    "Admin",
    "Uploads",
    "Images",
    "Exports",
    "Imports",
    "Webhooks",
    "Background Jobs",
    "Cron Jobs",
    "Utilities",
    "Internal APIs",
    "Health APIs",
    "Other discovered APIs",
]

completed = 0
for m, p, mod, n in rows:
    d = domain(p, mod)
    if d == "Authentication" and auth_status.get((m, p), ("x",))[0] == "COMPLETED":
        completed += 1
    elif d == "Health APIs" and (p, m) in health_done:
        completed += 1

out: list[str] = []
out.append("# PROJECT API AUDIT — Master Tracker")
out.append("")
out.append("**Generated:** 2026-07-28")
out.append(
    f"**Discovered HTTP routes (excl. HEAD/OPTIONS):** {len(rows)}"
)
out.append(
    f"**Note:** ~380 was an estimate; FastAPI currently exposes **{len(rows)}** "
    "method+path pairs. Tracker uses discovered count as 100%."
)
out.append(
    "**Hosts:** API https://my-purchases-api.onrender.com · "
    "Web https://purchase-assiastant.vercel.app"
)
out.append("**Detail audit (Auth):** `docs/debug/API_AUDIT_AUTH.md`")
out.append("")
out.append("## Progress")
out.append("")
out.append("| Metric | Value |")
out.append("|--------|-------|")
out.append(f"| Total endpoints | {len(rows)} |")
out.append(f"| Completed | {completed} / {len(rows)} |")
out.append("| Current focus | AUTH-H1 login commit |")
out.append("")
out.append("## Status legend")
out.append("")
out.append(
    "`NOT_STARTED` · `DISCOVERED` · `AUDITING` · `TESTING` · `FIXING` · "
    "`VERIFYING` · `DEPLOYED` · `COMPLETED` · `BLOCKED`"
)
out.append("")
out.append("## Issue log")
out.append("")
out.append("| ID | Severity | Status | Summary | Commit |")
out.append("|----|----------|--------|---------|--------|")
out.append(
    "| AUTH-C1 | Critical | COMPLETED | Refresh gates blocked/inactive | 9d50148 |"
)
out.append("| AUTH-H1 | High | IN_PROGRESS | Login missing db.commit | — |")
out.append(
    "| AUTH-H2 | High | BLOCKED | Forgot-password no email delivery | needs approval |"
)
out.append(
    "| AUTH-H3 | High | BLOCKED | Logo on ephemeral Render disk | needs approval/infra |"
)
out.append(
    "| AUTH-H4 | High | QUEUED | Google bypasses ALLOW_PUBLIC_REGISTRATION | — |"
)
out.append(
    "| STOCK/HOME isce | Critical | COMPLETED | Shared-session gather sequentialized | a52dd46, 772bdc0 |"
)
out.append("")
out.append("## Work rules")
out.append("")
out.append("- One issue at a time; no unrelated file churn.")
out.append("- AUTH-H2 / AUTH-H3 require user approval (email provider / object storage).")
out.append("- Stock bundle + home-overview isce already fixed; mark those Stock/Reports rows when audited.")
out.append("")

for sec in sections_order:
    items = by.get(sec, [])
    out.append(f"## {sec}")
    out.append("")
    if not items:
        out.append("_No routes discovered in this category (N/A for this codebase)._")
        out.append("")
        continue
    out.append(
        "| Method | Endpoint | Controller | Frontend | Status | Priority | Notes | Done |"
    )
    out.append(
        "|--------|----------|------------|----------|--------|----------|-------|------|"
    )
    for m, p, mod, n in items:
        st = "DISCOVERED"
        pri = "Medium"
        note = ""
        ctrl = f"{mod.split('.')[-1]}.{n}" if mod else n
        if sec == "Authentication":
            if (m, p) in auth_status:
                st, pri, note = auth_status[(m, p)]
        if sec == "Health APIs" and (p, m) in health_done:
            st = "COMPLETED"
            pri = "Low"
            note = "Live verified"
        # Known prior isce fixes
        if p.endswith("/stock/{item_id}/bundle") or p.endswith("/stock/shell-bundle"):
            st = "COMPLETED"
            pri = "Critical"
            note = "isce sequential a52dd46"
        if p.endswith("/reports/home-overview") or p.endswith(
            "/reports/trade-dashboard-snapshot"
        ):
            st = "COMPLETED"
            pri = "Critical"
            note = "isce sequential 772bdc0"
        if p.endswith("/stock/barcode/lookup"):
            st = "COMPLETED"
            pri = "High"
            note = "isce sequential a52dd46"
        if st == "COMPLETED":
            done = "☑"
        elif st == "BLOCKED":
            done = "⛔"
        else:
            done = "☐"
        fe = "—"
        if "/auth/login" in p:
            fe = "login_page"
        elif "/auth/refresh" in p:
            fe = "session_notifier"
        elif "/me/businesses" in p and "branding" not in p:
            fe = "session bootstrap"
        elif "/me/profile" in p and m == "GET":
            fe = "session bootstrap"
        elif "bootstrap" in p:
            fe = "session bootstrap"
        elif "forgot" in p or "reset-password" in p:
            fe = "forgot/reset pages"
        elif "/stock/" in p:
            fe = "stock_page / item detail"
        elif "home-overview" in p:
            fe = "home_dashboard"
        note_cell = note.replace("|", "/") if note else "—"
        out.append(
            f"| {m} | `{p}` | `{ctrl}` | {fe} | {st} | {pri} | {note_cell} | {done} |"
        )
    out.append("")

# recount completed including stock/home marks
completed2 = 0
for m, p, mod, n in rows:
    d = domain(p, mod)
    st = "DISCOVERED"
    if d == "Authentication" and (m, p) in auth_status:
        st = auth_status[(m, p)][0]
    elif d == "Health APIs" and (p, m) in health_done:
        st = "COMPLETED"
    if p.endswith("/stock/{item_id}/bundle") or p.endswith("/stock/shell-bundle"):
        st = "COMPLETED"
    if p.endswith("/reports/home-overview") or p.endswith(
        "/reports/trade-dashboard-snapshot"
    ):
        st = "COMPLETED"
    if p.endswith("/stock/barcode/lookup"):
        st = "COMPLETED"
    if st == "COMPLETED":
        completed2 += 1

text = "\n".join(out)
text = text.replace(
    f"| Completed | {completed} / {len(rows)} |",
    f"| Completed | {completed2} / {len(rows)} |",
)

dest = Path(__file__).resolve().parents[2] / "docs" / "debug" / "API_ENDPOINT_MASTER.md"
root_alias = Path(__file__).resolve().parents[2] / "PROJECT_API_AUDIT.md"
dest.parent.mkdir(parents=True, exist_ok=True)
payload = text + "\n"
dest.write_text(payload, encoding="utf-8")
root_alias.write_text(payload, encoding="utf-8")
print(f"Wrote {dest} and {root_alias} completed={completed2} total={len(rows)}")
