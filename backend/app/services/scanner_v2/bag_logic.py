"""Deterministic unit-type / bag / kg derivation for scanner_v2.

Implements the rules in `docs/AI_SCANNER_MATCHING_ENGINE.md` §"Unit type detection"
and §"Bag↔kg back-fill". Pure: no DB, no IO. Catalog metadata is passed in.

Public API:
- ``detect_unit_type``
- ``infer_weight_per_unit_kg``
- ``normalize_bag_kg``  (mutates an ``ItemRow`` in place; returns a list of
  warning codes the caller may surface)

These rules are the single source of truth for the report-critical bag/kg math.
Wrong here = wrong everywhere downstream.
"""

from __future__ import annotations

import re
from decimal import Decimal
from typing import TypedDict

from app.services.decimal_precision import dec, qty as q_qty, weight as q_weight

# --------------------------------------------------------------------------- #
# unit type detection                                                         #
# --------------------------------------------------------------------------- #

# Recognised bag weights inside the item name.
# Includes trader-standard packs like sugar 50kg, rice 26kg, atta 30kg.
ALLOWED_BAG_WEIGHTS_KG: tuple[int, ...] = (5, 10, 15, 25, 26, 30, 50)

_TIN_RE = re.compile(r"\btins?\b", re.IGNORECASE)
_LTR_TIN_RE = re.compile(r"\d+\s*(ltr|liter|litre)s?\s*tins?\b", re.IGNORECASE)
_BOX_RE = re.compile(r"\b(box(?:es)?|pkts?|packets?)\b", re.IGNORECASE)
_BAG_RE = re.compile(r"\b(bags?)\b", re.IGNORECASE)
_PCS_RE = re.compile(r"\b(pcs|pieces?|pc)\b", re.IGNORECASE)
_LTR_RE = re.compile(r"\b(ltr|liter|litre)s?\b", re.IGNORECASE)
_KG_RE = re.compile(r"\bkgs?\b", re.IGNORECASE)
_KG_TOKEN_RE = re.compile(r"(\d{1,3}(?:\.\d{1,2})?)\s*kg\b", re.IGNORECASE)


class CatalogHint(TypedDict, total=False):
    """Subset of catalog_items metadata needed by bag_logic."""

    default_unit: str | None
    default_kg_per_bag: Decimal | None
    default_items_per_box: Decimal | None
    default_weight_per_tin: Decimal | None


def _norm_unit(s: str | None) -> str | None:
    if not s:
        return None
    u = s.strip().upper()
    if u in {"BAG", "BAGS"}:
        return "BAG"
    if u in {"TIN", "TINS"}:
        return "TIN"
    if u in {"BOX", "BOXES", "PKT", "PKTS", "PACKET", "PACKETS"}:
        return "BOX"
    if u in {"PCS", "PC", "PIECE", "PIECES"}:
        return "PCS"
    if u in {"KG", "KGS"}:
        return "KG"
    return u


def detect_unit_type(
    raw_name: str,
    *,
    explicit_unit: str | None = None,
    catalog: CatalogHint | None = None,
) -> str:
    """Return one of BAG/BOX/TIN/KG/PCS applying the spec's rules.

    Precedence:
      1. ltr-tin pattern (e.g. "Oil 15 ltr tin") → TIN
      2. tin keyword → TIN
      3. box / pkt / packet → BOX
      4. explicit_unit normalized (BAG/KG/PCS) wins when not overridden
         by a clearer suffix in the name
      5. catalog.default_unit when provided
      6. KG-token bag rule: catalog.default_unit==BAG AND name contains
         5/10/15/25/26/30/50 KG → BAG
      7. fallback: KG
    """

    name = raw_name or ""

    if _LTR_TIN_RE.search(name) or _TIN_RE.search(name):
        return "TIN"
    if _BOX_RE.search(name):
        return "BOX"

    expl = _norm_unit(explicit_unit)
    if expl in {"BAG", "TIN", "BOX", "PCS"}:
        return expl
    if expl == "KG":
        return "KG"

    cat_default = _norm_unit((catalog or {}).get("default_unit"))
    if cat_default == "BAG":
        m = _KG_TOKEN_RE.search(name)
        if m and int(float(m.group(1))) in ALLOWED_BAG_WEIGHTS_KG:
            return "BAG"
        return "BAG"
    if cat_default in {"BOX", "TIN", "PCS"}:
        return cat_default

    if _BAG_RE.search(name):
        return "BAG"
    if _PCS_RE.search(name):
        return "PCS"
    if _KG_RE.search(name):
        return "KG"

    return "KG"


def infer_weight_per_unit_kg(name: str) -> Decimal | None:
    """Extract first 'NN KG' from name, validated to a sane band [0.1, 200].

    Returns None when no token or out of band.
    """
    m = _KG_TOKEN_RE.search(name or "")
    if not m:
        return None
    v = dec(m.group(1))
    if v <= 0 or v > 200:
        return None
    return q_weight(v)


# --------------------------------------------------------------------------- #
# bag <-> kg back-fill                                                        #
# --------------------------------------------------------------------------- #


class _MutableItem:
    """Duck-typed mutable view used by ``normalize_bag_kg``.

    Allows passing either a Pydantic model (we ``model_copy(update=...)``-style
    set attributes) or a plain mutable mapping. ItemRow inherits from BaseModel
    which permits setattr because we did not freeze the model.
    """


def normalize_bag_kg(
    item,  # ItemRow-like object (mutable)
    *,
    catalog: CatalogHint | None = None,
) -> list[str]:
    """Mutate ``item`` to fill bags/total_kg/qty/weight_per_unit_kg consistently.

    Returns a list of warning *codes* (no severity, no message) the caller can
    convert into ``Warning`` records. Codes used:

    - ``WEIGHT_FROM_NAME``        — derived weight_per_unit_kg from the name
    - ``WEIGHT_FROM_CATALOG``     — used catalog default_kg_per_bag
    - ``BAG_KG_REMAINDER``        — total_kg not divisible by weight_per_unit_kg
    - ``KG_UNIT_BAGS_DROPPED``    — unit is KG, bags forced to None
    - ``WEIGHT_OVERRIDDEN_FROM_NAME`` — name weight differs from catalog default
    """
    warnings: list[str] = []
    catalog = catalog or {}

    unit = item.unit_type or "KG"

    # 1) weight_per_unit_kg: prefer existing → catalog default → name
    wpu = item.weight_per_unit_kg
    if wpu is None:
        cat_w = catalog.get("default_kg_per_bag")
        if unit == "TIN":
            cat_w = catalog.get("default_weight_per_tin") or cat_w
        if cat_w is not None:
            wpu = q_weight(cat_w)
            warnings.append("WEIGHT_FROM_CATALOG")
        else:
            inferred = infer_weight_per_unit_kg(item.raw_name or "")
            if inferred is not None and unit in {"BAG", "TIN", "BOX"}:
                wpu = inferred
                warnings.append("WEIGHT_FROM_NAME")
    else:
        # If the name disagrees with the supplied weight, flag it.
        inferred = infer_weight_per_unit_kg(item.raw_name or "")
        if inferred is not None and inferred != wpu:
            warnings.append("WEIGHT_OVERRIDDEN_FROM_NAME")

    # KG unit: never carry a per-bag weight or a bag count.
    if unit == "KG":
        if item.bags not in (None, Decimal("0")):
            warnings.append("KG_UNIT_BAGS_DROPPED")
        item.bags = None
        item.weight_per_unit_kg = None
        # qty == total_kg for KG units. Whichever is present, mirror.
        if item.total_kg is None and item.qty is not None:
            item.total_kg = q_weight(item.qty)
        elif item.qty is None and item.total_kg is not None:
            item.qty = q_qty(item.total_kg)
        return warnings

    # PCS: leave qty as-is, no derivation.
    if unit in {"PCS"}:
        item.weight_per_unit_kg = wpu
        return warnings

    # BAG / BOX / TIN: bags <-> total_kg derivation.
    item.weight_per_unit_kg = wpu

    bags = item.bags
    total_kg = item.total_kg
    qty = item.qty

    # If qty is set without bags for a bag-style unit, treat qty as bag count.
    if bags is None and qty is not None and total_kg is None:
        bags = q_qty(qty)
        item.bags = bags

    if bags is not None and wpu is not None and total_kg is None:
        item.total_kg = q_weight(bags * wpu)
    elif total_kg is not None and wpu is not None and bags is None:
        derived_bags = (total_kg / wpu).quantize(Decimal("1"))
        item.bags = derived_bags
        if derived_bags * wpu != total_kg:
            warnings.append("BAG_KG_REMAINDER")
    elif total_kg is not None and bags is not None and wpu is not None:
        if abs(bags * wpu - total_kg) > 1:
            # caller's validators will turn this into a blocker
            warnings.append("BAG_KG_REMAINDER")

    # qty mirrors bags for unit_type=BAG/BOX/TIN (number of containers).
    if item.bags is not None and item.qty is None:
        item.qty = q_qty(item.bags)

    return warnings


__all__ = [
    "ALLOWED_BAG_WEIGHTS_KG",
    "CatalogHint",
    "detect_unit_type",
    "infer_weight_per_unit_kg",
    "normalize_bag_kg",
]
