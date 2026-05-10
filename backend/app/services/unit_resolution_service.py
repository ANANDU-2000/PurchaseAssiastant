"""Canonical wholesale unit + package-size resolution (backend SSOT).

Package tokens such as ``50KG`` / ``850GM`` / ``15LTR`` are **sizes**, not selling units.
"""

from __future__ import annotations

import json
import re
from dataclasses import asdict, dataclass
from decimal import Decimal
from functools import lru_cache
from pathlib import Path
from typing import Any

from app.models.catalog import CatalogItem
from app.services.trade_unit_type import parse_kg_per_bag_from_name

_SIZE_KG = re.compile(r"(\d+)\s*KG", re.IGNORECASE)
_SIZE_GM = re.compile(r"(\d+)\s*GM", re.IGNORECASE)
_SIZE_LTR = re.compile(r"(\d+)\s*LTR", re.IGNORECASE)
_SIZE_ML = re.compile(r"(\d+)\s*ML", re.IGNORECASE)


@dataclass(frozen=True)
class UnitResolution:
    selling_unit: str
    stock_unit: str | None = None
    display_unit: str | None = None
    package_type: str | None = None
    package_size: Decimal | None = None
    package_measurement: str | None = None
    conversion_factor: Decimal = Decimal("1")
    confidence: Decimal = Decimal("0")
    rule_id: str | None = None

    def as_dict(self) -> dict[str, Any]:
        d = asdict(self)
        for k in ("package_size", "conversion_factor", "confidence"):
            v = d.get(k)
            if isinstance(v, Decimal):
                d[k] = float(v) if v is not None else None
        return d


@lru_cache(maxsize=1)
def _rules() -> dict[str, Any]:
    path = Path(__file__).with_name("unit_rules_master.json")
    return json.loads(path.read_text(encoding="utf-8"))


def _parse_size_tokens(upper_name: str) -> tuple[Decimal | None, str | None]:
    if m := _SIZE_KG.search(upper_name):
        return Decimal(m.group(1)), "KG"
    if m := _SIZE_GM.search(upper_name):
        return Decimal(m.group(1)), "GM"
    if m := _SIZE_LTR.search(upper_name):
        return Decimal(m.group(1)), "LTR"
    if m := _SIZE_ML.search(upper_name):
        return Decimal(m.group(1)), "ML"
    return None, None


def _apply_result(
    upper_name: str,
    result: dict[str, Any],
    rule_id: str,
) -> UnitResolution:
    su = str(result.get("selling_unit") or "").upper()
    size, meas = _parse_size_tokens(upper_name)
    raw_pt = result.get("package_type")
    pt = str(raw_pt).upper() if raw_pt else None
    if isinstance(pt, str) and not pt.strip():
        pt = None
    cf_raw = result.get("conversion_factor")
    cf_explicit = Decimal(str(cf_raw)) if cf_raw is not None else None
    st = result.get("stock_unit")
    stock = str(st).upper() if st else None
    parsed_pt, stock2, cf2 = _infer_stock_and_conversion(su, size, meas, pt)
    conv_final = cf_explicit if cf_explicit is not None else cf2
    return UnitResolution(
        selling_unit=su,
        stock_unit=stock or stock2,
        display_unit=None,
        package_type=parsed_pt,
        package_size=size,
        package_measurement=meas,
        conversion_factor=conv_final,
        confidence=Decimal("85"),
        rule_id=rule_id,
    )


def _infer_stock_and_conversion(
    selling_unit: str,
    size: Decimal | None,
    meas: str | None,
    package_type: str | None,
) -> tuple[str | None, str | None, Decimal]:
    stock = "PCS"
    conv = Decimal("1")
    pt = package_type
    if selling_unit == "BAG" and size is not None and meas == "KG":
        stock = "KG"
        conv = size
        pt = pt or "SACK"
    elif selling_unit == "TIN" and size is not None and meas in ("LTR", "ML"):
        stock = "TIN"
        conv = Decimal("1")
        pt = pt or "TIN"
    elif selling_unit == "BOX" and size is not None:
        stock = "PCS"
        conv = Decimal("1")
        pt = pt or "BOX"
    elif selling_unit == "KG":
        stock = "KG"
        conv = Decimal("1")
        pt = pt or "LOOSE"
    return pt, stock, conv


def _match_condition(
    upper_name: str,
    upper_cat: str,
    brand_detected: bool,
    cond: dict[str, Any],
) -> bool:
    any_tokens = [str(x).upper() for x in (cond.get("contains_any") or [])]
    if any_tokens and not any(t in upper_name for t in any_tokens):
        return False
    cats = [str(x).upper() for x in (cond.get("category_any") or [])]
    if cats and not any(c in upper_cat or upper_cat == c for c in cats):
        return False
    if cond.get("brand_detected") is True and not brand_detected:
        return False
    return True


def resolve_from_text(
    item_name: str,
    *,
    category_name: str | None = None,
    brand_detected: bool = False,
) -> UnitResolution:
    """Resolve units from free text + optional category hint (matches Flutter classifier)."""
    rules = _rules()
    upper = item_name.upper().strip()
    cat = (category_name or "").upper().strip()

    if "LOOSE" in upper:
        return UnitResolution(
            selling_unit="KG",
            package_type="LOOSE",
            stock_unit="KG",
            conversion_factor=Decimal("1"),
            confidence=Decimal("92"),
            rule_id="loose",
        )

    detection = rules.get("smart_detection_rules") or []
    for i, row in enumerate(detection):
        cond = row.get("condition") or {}
        result = row.get("result") or {}
        if not _match_condition(upper, cat, brand_detected, cond):
            continue
        if not result.get("selling_unit"):
            continue
        return _apply_result(upper, result, f"smart_rule_{i}")

    cat_rules = rules.get("category_rules") or {}
    for key, meta in cat_rules.items():
        if key.upper() not in cat and cat != key.upper():
            continue
        du = str((meta or {}).get("default_unit") or "").upper()
        if not du:
            continue
        pt = str((meta or {}).get("package_type") or "").upper() or None
        size, meas = _parse_size_tokens(upper)
        _, stock, conv = _infer_stock_and_conversion(du, size, meas, pt)
        return UnitResolution(
            selling_unit=du,
            stock_unit=stock,
            package_type=pt,
            package_size=size,
            package_measurement=meas,
            conversion_factor=conv,
            confidence=Decimal("70"),
            rule_id=f"category_{key}",
        )

    size, meas = _parse_size_tokens(upper)
    if size is not None and meas == "KG" and ("RICE" in upper or "SUGAR" in upper):
        pt, stock, conv = _infer_stock_and_conversion("BAG", size, meas, "SACK")
        return UnitResolution(
            selling_unit="BAG",
            stock_unit=stock,
            package_type=pt,
            package_size=size,
            package_measurement=meas,
            conversion_factor=conv,
            confidence=Decimal("65"),
            rule_id="fallback_bag_sack",
        )

    return UnitResolution(selling_unit="PCS", confidence=Decimal("40"), rule_id="fallback_pcs")


def resolve_for_catalog_item(
    item: CatalogItem | None,
    *,
    item_name: str,
    category_name: str | None = None,
    brand_detected: bool = False,
) -> UnitResolution:
    """Prefer persisted ``catalog_items`` smart fields; fall back to ``resolve_from_text``."""
    name = (item.name if item is not None else None) or item_name
    cat = category_name
    if item is not None and (item.selling_unit or "").strip():
        su = item.selling_unit.strip().upper()
        size = item.package_size
        meas = (item.package_measurement or "").upper() or None
        pt = (item.package_type or "").upper() if item.package_type else None
        cf = item.conversion_factor or Decimal("1")
        st = (item.stock_unit or "").upper() if item.stock_unit else None
        du = (item.display_unit or "").upper() if item.display_unit else None
        uc = item.unit_confidence or Decimal("95")
        return UnitResolution(
            selling_unit=su,
            stock_unit=st,
            display_unit=du,
            package_type=pt,
            package_size=size,
            package_measurement=meas,
            conversion_factor=cf,
            confidence=uc,
            rule_id="catalog_item_row",
        )

    text_res = resolve_from_text(name, category_name=cat, brand_detected=brand_detected)
    if item is not None and item.default_kg_per_bag and text_res.selling_unit == "BAG":
        kpb = item.default_kg_per_bag
        return UnitResolution(
            selling_unit=text_res.selling_unit,
            stock_unit=text_res.stock_unit or "KG",
            display_unit=text_res.display_unit,
            package_type=text_res.package_type or "SACK",
            package_size=text_res.package_size or kpb,
            package_measurement=text_res.package_measurement or "KG",
            conversion_factor=text_res.conversion_factor if text_res.package_size else kpb,
            confidence=min(text_res.confidence + Decimal("5"), Decimal("99")),
            rule_id=(text_res.rule_id or "") + "+kpb",
        )

    # Name-only kg hint for bags (align with trade line weight fallback)
    if item is not None and (item.default_kg_per_bag or parse_kg_per_bag_from_name(name)):
        kpb = item.default_kg_per_bag or parse_kg_per_bag_from_name(name)
        if kpb:
            return UnitResolution(
                selling_unit="BAG",
                stock_unit="KG",
                package_type="SACK",
                package_size=kpb,
                package_measurement="KG",
                conversion_factor=kpb,
                confidence=Decimal("72"),
                rule_id="default_kg_per_bag",
            )

    return text_res
