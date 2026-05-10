#!/usr/bin/env python3
"""Sprint 1 / program audit: emit JSON inventory of API routers + grep hints (run from repo root).

Usage:
  python backend/scripts/sprint1_audit_collect.py > audit_signals.json
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]


def _routers_from_main() -> list[str]:
    main_py = REPO / "backend" / "app" / "main.py"
    text = main_py.read_text(encoding="utf-8")
    m = re.search(r"from app\.routers import \(([^)]+)\)", text, re.S)
    if not m:
        return []
    block = m.group(1)
    return sorted({line.strip().rstrip(",") for line in block.splitlines() if line.strip() and not line.strip().startswith("#")})


def _go_routes_hints() -> list[dict[str, object]]:
    """Collect GoRoute path strings from app_router / router dart files."""
    out: list[dict[str, object]] = []
    lib = REPO / "flutter_app" / "lib"
    if not lib.is_dir():
        return out
    rx = re.compile(r"(?:path|name)\s*:\s*['\"]([^'\"]+)['\"]")
    for path in lib.rglob("*.dart"):
        s = str(path)
        if "router" not in s.lower() and "routes" not in s.lower():
            continue
        if ".dart_tool" in s or "/build/" in s or "\\build\\" in s:
            continue
        try:
            text = path.read_text(encoding="utf-8", errors="ignore")
        except OSError:
            continue
        for i, line in enumerate(text.splitlines(), 1):
            if "GoRoute" not in line and "path:" not in line:
                continue
            m = rx.search(line)
            if not m:
                continue
            try:
                rel = path.relative_to(REPO)
            except ValueError:
                rel = path
            out.append({"file": str(rel).replace("\\", "/"), "line": i, "path_or_name": m.group(1)[:120]})
            if len(out) >= 200:
                return out
    return out


def _provider_files() -> list[str]:
    """List dart files under lib/**/providers (NotifierProvider inventory)."""
    lib = REPO / "flutter_app" / "lib"
    if not lib.is_dir():
        return []
    out: list[str] = []
    for path in lib.rglob("*.dart"):
        s = str(path).replace("\\", "/")
        if "/providers/" not in s:
            continue
        if ".dart_tool" in s or "/build/" in s:
            continue
        try:
            rel = path.relative_to(REPO)
        except ValueError:
            continue
        out.append(str(rel).replace("\\", "/"))
    return sorted(out)[:400]


def _setstate_large_widgets(*, min_lines: int = 600) -> list[dict[str, object]]:
    """Files with setState( in widgets that exceed min_lines (rebuild risk)."""
    lib = REPO / "flutter_app" / "lib"
    out: list[dict[str, object]] = []
    if not lib.is_dir():
        return out
    for path in lib.rglob("*.dart"):
        s = path.as_posix()
        if "/widgets/" not in s and "/presentation/" not in s:
            continue
        if ".dart_tool" in s or "/build/" in s or "\\build\\" in s:
            continue
        try:
            text = path.read_text(encoding="utf-8", errors="ignore")
        except OSError:
            continue
        n = text.count("\n") + 1
        if n < min_lines:
            continue
        if "setState(" not in text:
            continue
        try:
            rel = path.relative_to(REPO)
        except ValueError:
            rel = path
        hits = text.count("setState(")
        out.append({"file": str(rel).replace("\\", "/"), "lines": n, "setState_calls": hits})
    return sorted(out, key=lambda x: -int(x["lines"]))[:40]


def _walk_grep(root: Path, pattern: str, ext: str, *, limit: int = 120) -> list[dict[str, object]]:
    rx = re.compile(pattern)
    out: list[dict[str, object]] = []
    if not root.is_dir():
        return out
    for path in root.rglob("**/*.dart" if ext == ".dart" else "**/*.py"):
        if path.suffix != ext:
            continue
        s = str(path)
        if ".dart_tool" in s or "/build/" in s or "\\build\\" in s:
            continue
        try:
            text = path.read_text(encoding="utf-8", errors="ignore")
        except OSError:
            continue
        for i, line in enumerate(text.splitlines(), 1):
            if rx.search(line):
                try:
                    rel = path.relative_to(REPO)
                except ValueError:
                    rel = path
                out.append({"file": str(rel).replace("\\", "/"), "line": i, "text": line.strip()[:180]})
                if len(out) >= limit:
                    return out
    return out


def main() -> None:
    flutter_lib = REPO / "flutter_app" / "lib"
    backend_app = REPO / "backend" / "app"
    doc: dict = {
        "repo": str(REPO),
        "backend_routers_from_main": _routers_from_main(),
        "flutter_go_route_hints": _go_routes_hints(),
        "flutter_provider_files": _provider_files(),
        "flutter_setstate_large_widgets": _setstate_large_widgets(),
        "flutter_hints": {
            "kg_slash_ui": _walk_grep(flutter_lib, r"/kg|₹/kg", ".dart"),
            "line_money_client": _walk_grep(flutter_lib, r"lineMoney\(", ".dart"),
            "compute_purchase_totals": _walk_grep(flutter_lib, r"computePurchaseTotals", ".dart"),
            "notifier_provider": _walk_grep(flutter_lib, r"NotifierProvider|AsyncNotifierProvider", ".dart", limit=80),
        },
        "backend_hints": {
            "line_money": _walk_grep(backend_app, r"line_money", ".py"),
            "compute_totals": _walk_grep(backend_app, r"compute_totals", ".py"),
            "trade_query_reports": _walk_grep(
                backend_app / "services",
                r"trade_query|trade_line_amount|trade_purchase",
                ".py",
                limit=80,
            ),
            "reports_trade_router": _walk_grep(
                backend_app / "routers",
                r"reports_trade|trade_purchase",
                ".py",
                limit=60,
            ),
        },
    }
    json.dump(doc, sys.stdout, indent=2)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
