"""Server-side hints for Flutter ``DynamicUnitLabelEngine`` (display basis, not money)."""

from __future__ import annotations

from decimal import Decimal
from typing import Any

from app.schemas.trade_purchases import TradePurchaseLineIn
from app.services import decimal_precision as dp
from app.services.trade_unit_type import derive_trade_unit_type


def _dec(x) -> Decimal:
    return Decimal(str(x))


def line_uses_weight_priced_gross(li: TradePurchaseLineIn) -> bool:
    """Same basis as ``line_totals_service.line_gross_base`` weight path."""
    kpu = li.kg_per_unit
    lcpk = li.landing_cost_per_kg
    landing = _dec(li.purchase_rate) if li.purchase_rate is not None else _dec(li.landing_cost)
    if kpu is not None and lcpk is not None and landing is not None:
        derived = _dec(kpu) * _dec(lcpk)
        if _dec(kpu) > 0 and _dec(lcpk) > 0 and abs(derived - landing) <= Decimal("0.05"):
            return True
    return False


def _dim_for_trade_unit(ut: str) -> str:
    u = ut.strip().lower()
    if u in ("bag", "sack"):
        return "bag"
    if u == "kg" or u == "kgs":
        return "kg"
    if u == "box":
        return "box"
    if u == "tin":
        return "tin"
    if u in ("pcs", "piece", "pkt", "packet"):
        return "pcs"
    return u if u else "unit"


def build_rate_context(
    li: TradePurchaseLineIn,
    *,
    resolved_labels: dict[str, Any] | None = None,
) -> dict[str, Any]:
    """Per-line display context; money still from ``line_money`` / persisted totals."""
    rl = dict(resolved_labels or {})
    utype = derive_trade_unit_type(li.unit)
    weight_gross = line_uses_weight_priced_gross(li)
    purchase_dim = _dim_for_trade_unit(li.unit)
    selling_dim = purchase_dim
    if utype == "bag" and weight_gross:
        purchase_dim = "bag"
        selling_dim = "bag"
    elif utype == "kg":
        purchase_dim = "kg"
        selling_dim = "kg"
    pur = li.purchase_rate if li.purchase_rate is not None else li.landing_cost
    sell = li.selling_rate if li.selling_rate is not None else li.selling_cost
    out: dict[str, Any] = {
        "line_unit": (li.unit or "").strip(),
        "unit_type": utype,
        "weight_priced_gross": weight_gross,
        "purchase_rate_dim": purchase_dim,
        "selling_rate_dim": selling_dim,
        "qty_dim": purchase_dim,
        "display_purchase_rate": float(dp.rate(pur)) if pur is not None else None,
        "display_selling_rate": float(dp.rate(sell)) if sell is not None else None,
        "canonical_unit_type": rl.get("canonical_unit_type"),
        "resolved_labels": rl,
    }
    if weight_gross and utype == "bag" and li.kg_per_unit and li.landing_cost_per_kg:
        out["per_kg_landing"] = float(dp.rate(li.landing_cost_per_kg))
        if sell is not None and li.kg_per_unit:
            try:
                out["per_kg_selling"] = float(dp.rate(_dec(sell) / _dec(li.kg_per_unit)))
            except Exception:  # noqa: BLE001
                out["per_kg_selling"] = None
    return out


def validate_rate_label_consistency(li: TradePurchaseLineIn, ctx: dict[str, Any]) -> list[dict[str, Any]]:
    """Return blocker dicts when bag trade unit would still be shown as kg-only."""
    issues: list[dict[str, Any]] = []
    ut = derive_trade_unit_type(li.unit)
    if ut == "bag" and ctx.get("purchase_rate_dim") == "kg":
        issues.append(
            {
                "code": "rate_dim_bag_mismatch",
                "severity": "blocker",
                "message": "Bag line must not use kg-only purchase rate labels",
            }
        )
    return issues
