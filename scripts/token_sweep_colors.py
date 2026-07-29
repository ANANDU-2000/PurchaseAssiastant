#!/usr/bin/env python3
"""Replace common Color(0xFF…) literals with HexaColors / HexaDsColors in feature modules."""
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "flutter_app" / "lib" / "features"

# Prefer HexaColors for brand/semantic; HexaDsColors for DS-only.
REPLACEMENTS: list[tuple[str, str, str]] = [
    # (regex pattern, replacement, which import: "colors" | "ds" | "both")
    (r"Color\(0xFF64748[Bb]\)", "HexaColors.neutral", "colors"),
    (r"const Color\(0xFF64748[Bb]\)", "HexaColors.neutral", "colors"),
    (r"Color\(0xFF475569\)", "HexaColors.textBody", "colors"),
    (r"const Color\(0xFF475569\)", "HexaColors.textBody", "colors"),
    (r"Color\(0xFF0[Ff]172[Aa]\)", "HexaColors.textOnLightSurface", "colors"),
    (r"const Color\(0xFF0[Ff]172[Aa]\)", "HexaColors.textOnLightSurface", "colors"),
    (r"Color\(0xFF334155\)", "HexaColors.slate700", "colors"),
    (r"const Color\(0xFF334155\)", "HexaColors.slate700", "colors"),
    (r"Color\(0xFF2563[Ee][Bb]\)", "HexaDsColors.blue", "ds"),
    (r"const Color\(0xFF2563[Ee][Bb]\)", "HexaDsColors.blue", "ds"),
    (r"Color\(0xFFDC2626\)", "HexaDsColors.error", "ds"),
    (r"const Color\(0xFFDC2626\)", "HexaDsColors.error", "ds"),
    (r"Color\(0xFFB91[Cc]1[Cc]\)", "HexaDsColors.error", "ds"),
    (r"const Color\(0xFFB91[Cc]1[Cc]\)", "HexaDsColors.error", "ds"),
    (r"Color\(0xFF059669\)", "HexaDsColors.success", "ds"),
    (r"const Color\(0xFF059669\)", "HexaDsColors.success", "ds"),
    (r"Color\(0xFF16[Aa]34[Aa]\)", "HexaColors.profit", "colors"),
    (r"const Color\(0xFF16[Aa]34[Aa]\)", "HexaColors.profit", "colors"),
    (r"Color\(0xFF0[Ee]4[Ff]46\)", "HexaColors.brandPrimary", "colors"),
    (r"const Color\(0xFF0[Ee]4[Ff]46\)", "HexaColors.brandPrimary", "colors"),
    (r"Color\(0xFF065[Ff]4[Ff]\)", "HexaColors.brandSecondary", "colors"),
    (r"const Color\(0xFF065[Ff]4[Ff]\)", "HexaColors.brandSecondary", "colors"),
    (r"Color\(0xFF159[Aa]8[Aa]\)", "HexaColors.brandAccent", "colors"),
    (r"const Color\(0xFF159[Aa]8[Aa]\)", "HexaColors.brandAccent", "colors"),
    (r"Color\(0xFF[Dd]4[Aa][Ff]37\)", "HexaColors.brandGold", "colors"),
    (r"const Color\(0xFF[Dd]4[Aa][Ff]37\)", "HexaColors.brandGold", "colors"),
    (r"Color\(0xFF[Ff]7[Ff]9[Ff]6\)", "HexaColors.brandBackground", "colors"),
    (r"const Color\(0xFF[Ff]7[Ff]9[Ff]6\)", "HexaColors.brandBackground", "colors"),
    (r"Color\(0xFF[Ff]5[Ff]3[Ee]{2}\)", "HexaColors.scaffoldWarm", "colors"),
    (r"const Color\(0xFF[Ff]5[Ff]3[Ee]{2}\)", "HexaColors.scaffoldWarm", "colors"),
    (r"Color\(0xFF[Ff][Aa][Ff][Aa][Ff]8\)", "HexaColors.panelWarm", "colors"),
    (r"const Color\(0xFF[Ff][Aa][Ff][Aa][Ff]8\)", "HexaColors.panelWarm", "colors"),
    (r"Color\(0xFF0[Dd]6[Bb]5[Ee]\)", "HexaColors.brandTealDeep", "colors"),
    (r"const Color\(0xFF0[Dd]6[Bb]5[Ee]\)", "HexaColors.brandTealDeep", "colors"),
    (r"Color\(0xFF0[Ff]766[Ee]\)", "HexaColors.brandTealMid", "colors"),
    (r"const Color\(0xFF0[Ff]766[Ee]\)", "HexaColors.brandTealMid", "colors"),
    (r"Color\(0xFF1[Aa]1[Aa]1[Aa]\)", "HexaColors.textOnLightSurface", "colors"),
    (r"const Color\(0xFF1[Aa]1[Aa]1[Aa]\)", "HexaColors.textOnLightSurface", "colors"),
    (r"Color\(0xFFE2E8E6\)", "HexaColors.brandBorder", "colors"),
    (r"const Color\(0xFFE2E8E6\)", "HexaColors.brandBorder", "colors"),
    (r"Color\(0xFFF0A500\)", "HexaColors.warning", "colors"),
    (r"const Color\(0xFFF0A500\)", "HexaColors.warning", "colors"),
    (r"Color\(0xFFE53935\)", "HexaColors.loss", "colors"),
    (r"const Color\(0xFFE53935\)", "HexaColors.loss", "colors"),
    (r"Color\(0xFF94A3B8\)", "HexaColors.cost", "colors"),
    (r"const Color\(0xFF94A3B8\)", "HexaColors.cost", "colors"),
    (r"Color\(0xFFE2E8F0\)", "HexaColors.slateBorder", "colors"),
    (r"const Color\(0xFFE2E8F0\)", "HexaColors.slateBorder", "colors"),
    (r"Color\(0xFF0D9488\)", "HexaColors.brandTealBright", "colors"),
    (r"const Color\(0xFF0D9488\)", "HexaColors.brandTealBright", "colors"),
    (r"Color\(0xFFE65100\)", "HexaColors.accentOrange", "colors"),
    (r"const Color\(0xFFE65100\)", "HexaColors.accentOrange", "colors"),
    (r"Color\(0xFF1565C0\)", "HexaColors.materialBlue", "colors"),
    (r"const Color\(0xFF1565C0\)", "HexaColors.materialBlue", "colors"),
    (r"Color\(0xFF2E7D32\)", "HexaColors.materialGreen", "colors"),
    (r"const Color\(0xFF2E7D32\)", "HexaColors.materialGreen", "colors"),
    (r"Color\(0xFFC62828\)", "HexaColors.materialRed", "colors"),
    (r"const Color\(0xFFC62828\)", "HexaColors.materialRed", "colors"),
    (r"Color\(0xFFF8FAFC\)", "HexaColors.slate50", "colors"),
    (r"const Color\(0xFFF8FAFC\)", "HexaColors.slate50", "colors"),
    (r"Color\(0xFFEA580C\)", "HexaColors.accentOrangeMid", "colors"),
    (r"const Color\(0xFFEA580C\)", "HexaColors.accentOrangeMid", "colors"),
    (r"Color\(0xFFA32D2D\)", "HexaColors.dangerDeep", "colors"),
    (r"const Color\(0xFFA32D2D\)", "HexaColors.dangerDeep", "colors"),
    (r"Color\(0xFF7C3AED\)", "HexaDsColors.violet", "ds"),
    (r"const Color\(0xFF7C3AED\)", "HexaDsColors.violet", "ds"),
    (r"Color\(0xFF17A8A7\)", "HexaColors.brandTealSoft", "colors"),
    (r"const Color\(0xFF17A8A7\)", "HexaColors.brandTealSoft", "colors"),
    (r"Color\(0xFFFFF7ED\)", "HexaColors.accentOrangeSoft", "colors"),
    (r"const Color\(0xFFFFF7ED\)", "HexaColors.accentOrangeSoft", "colors"),
    (r"Color\(0xFFF1F5F9\)", "HexaColors.slate100", "colors"),
    (r"const Color\(0xFFF1F5F9\)", "HexaColors.slate100", "colors"),
    (r"Color\(0xFF6B7280\)", "HexaColors.gray500", "colors"),
    (r"const Color\(0xFF6B7280\)", "HexaColors.gray500", "colors"),
    (r"Color\(0xFF9A3412\)", "HexaColors.accentOrangeDeep", "colors"),
    (r"const Color\(0xFF9A3412\)", "HexaColors.accentOrangeDeep", "colors"),
    (r"Color\(0xFF6366F1\)", "HexaDsColors.indigo", "ds"),
    (r"const Color\(0xFF6366F1\)", "HexaDsColors.indigo", "ds"),
    (r"Color\(0xFFE5E7EB\)", "HexaColors.inputBorderGrey", "colors"),
    (r"const Color\(0xFFE5E7EB\)", "HexaColors.inputBorderGrey", "colors"),
    (r"Color\(0xFF065F46\)", "HexaDsColors.successForeground", "ds"),
    (r"const Color\(0xFF065F46\)", "HexaDsColors.successForeground", "ds"),
    (r"Color\(0xFFF59E0B\)", "HexaColors.accentAmber", "colors"),
    (r"const Color\(0xFFF59E0B\)", "HexaColors.accentAmber", "colors"),
    (r"Color\(0xFFECFDF5\)", "HexaDsColors.successSurface", "ds"),
    (r"const Color\(0xFFECFDF5\)", "HexaDsColors.successSurface", "ds"),
    (r"Color\(0xFF1E293B\)", "HexaColors.slate800", "colors"),
    (r"const Color\(0xFF1E293B\)", "HexaColors.slate800", "colors"),
    (r"Color\(0xFFD97706\)", "HexaDsWarehouse.warningAmber", "ds"),
    (r"const Color\(0xFFD97706\)", "HexaDsWarehouse.warningAmber", "ds"),
]

IMPORT_COLORS = "import 'package:harisree_warehouse/core/theme/hexa_colors.dart';"
# Relative imports vary by depth — detect and insert package or relative.
COLORS_REL_HINTS = (
    "core/theme/hexa_colors.dart",
    "theme/hexa_colors.dart",
)
DS_REL_HINTS = (
    "core/design_system/hexa_ds_tokens.dart",
    "design_system/hexa_ds_tokens.dart",
)


def depth_import(path: Path, target: str) -> str:
    """Build relative import from features/... file to lib/core/..."""
    # path: .../lib/features/stock/presentation/foo.dart
    # target: core/theme/hexa_colors.dart
    lib = path
    while lib.name != "lib" and lib.parent != lib:
        lib = lib.parent
    rel = Path(target)
    # from path.parent to lib
    ups = 0
    cur = path.parent
    while cur != lib and cur.parent != cur:
        ups += 1
        cur = cur.parent
    return "import '" + ("../" * ups) + target.replace("\\", "/") + "';"


def ensure_import(text: str, path: Path, kind: str) -> str:
    if kind in ("colors", "both"):
        if "hexa_colors.dart" not in text:
            line = depth_import(path, "core/theme/hexa_colors.dart") + "\n"
            text = _insert_import(text, line)
    if kind in ("ds", "both"):
        if "hexa_ds_tokens.dart" not in text:
            line = depth_import(path, "core/design_system/hexa_ds_tokens.dart") + "\n"
            text = _insert_import(text, line)
    return text


def _insert_import(text: str, line: str) -> str:
    # After last import
    matches = list(re.finditer(r"^import .+;\s*\n", text, re.M))
    if not matches:
        return line + text
    last = matches[-1]
    return text[: last.end()] + line + text[last.end() :]


def process_file(path: Path) -> bool:
    original = path.read_text(encoding="utf-8")
    text = original
    needed: set[str] = set()
    for pattern, repl, kind in REPLACEMENTS:
        new_text, n = re.subn(pattern, repl, text)
        if n:
            text = new_text
            needed.add(kind)
    if text == original:
        return False
    # Fix double const: const HexaColors.x is invalid if already const context —
    # HexaColors fields are const, so `const Color(...)` became `const HexaColors.x` which is OK in Dart
    # for const constructors expecting Color. Actually `const HexaColors.brandPrimary` works.
    for kind in needed:
        if kind == "both":
            text = ensure_import(text, path, "colors")
            text = ensure_import(text, path, "ds")
        else:
            text = ensure_import(text, path, kind)
    # Deduplicate imports
    lines = text.splitlines(keepends=True)
    seen = set()
    out = []
    for ln in lines:
        if ln.startswith("import ") and ln in seen:
            continue
        if ln.startswith("import "):
            seen.add(ln)
        out.append(ln)
    path.write_text("".join(out), encoding="utf-8")
    return True


def main() -> None:
    modules = [
        "stock",
        "purchase",
        "reports",
        "home",
        "catalog",
        "auth",
        "contacts",
        "barcode",
        "staff",
    ]
    changed = []
    for mod in modules:
        d = ROOT / mod
        if not d.is_dir():
            continue
        for path in d.rglob("*.dart"):
            if process_file(path):
                changed.append(str(path.relative_to(ROOT)))
    print(f"Updated {len(changed)} files")
    for c in changed[:40]:
        print(" ", c)
    if len(changed) > 40:
        print(f"  ... +{len(changed) - 40} more")


if __name__ == "__main__":
    main()
