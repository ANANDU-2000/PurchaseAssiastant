"""Pure-Python mirrors of ``trade_query`` SQL expressions for tests and SSOT checks."""

from __future__ import annotations

from decimal import Decimal

from app.schemas.trade_purchases import TradePurchaseLineIn
from app.services import decimal_precision as dp
from app.services.trade_unit_type import derive_trade_unit_type


def _dec(x) -> Decimal:
    return Decimal(str(x))


def _effective_unit_type(unit: str | None, unit_type_db: str | None) -> str:
    """Canonical bucket: prefer persisted ``unit_type`` when present, else derive from ``unit``."""
    raw = (unit_type_db or "").strip().lower() if unit_type_db else ""
    if raw in {"bag", "box", "tin", "kg", "litre", "pcs", "other"}:
        return raw
    return derive_trade_unit_type(unit)


def trade_line_computed_amount_python(
    li: TradePurchaseLineIn,
    *,
    persisted_line_total: Decimal | None = None,
) -> Decimal:
    """``coalesce(line_total, computed)`` without DB — computed matches ``line_gross_base``."""
    if persisted_line_total is not None:
        return dp.total(_dec(persisted_line_total))
    return dp.total(_line_gross_base_trade_query(li))


def _line_gross_base_trade_query(li: TradePurchaseLineIn) -> Decimal:
    qty = _dec(li.qty)
    kpu = li.kg_per_unit
    lcpk = li.landing_cost_per_kg
    landing = _dec(li.purchase_rate) if li.purchase_rate is not None else _dec(li.landing_cost)
    if kpu is not None and lcpk is not None and landing is not None:
        derived = _dec(kpu) * _dec(lcpk)
        if _dec(kpu) > 0 and _dec(lcpk) > 0 and abs(derived - landing) <= Decimal("0.05"):
            return qty * _dec(kpu) * _dec(lcpk)
    return qty * landing


def trade_line_weight_sql_python(
    li: TradePurchaseLineIn,
    *,
    persisted_total_weight_kg: Decimal | None = None,
    unit_type_db: str | None = None,
) -> Decimal:
    """Mirror ``trade_line_weight_expr`` (no name-based kg parse — SQL has none)."""
    ut = _effective_unit_type(li.unit, unit_type_db)
    u_raw = li.unit or ""
    uu = u_raw.strip().upper()
    kpu_src = li.weight_per_unit if li.weight_per_unit is not None else li.kg_per_unit
    kpu = _dec(kpu_src) if kpu_src is not None else None
    weight_ok = kpu is not None and kpu > 0
    # SQL ``is_bag`` / ``kg_fallback`` when unit_type is NULL uses LIKE on unit; derive covers BG/BAG/SACK/KG.
    is_bag = ut == "bag"
    kg_fb = ut == "kg"
    if unit_type_db is None or not str(unit_type_db).strip():
        if not is_bag and ("BAG" in uu or "SACK" in uu or uu in ("BG", "BGS")):
            is_bag = True
        if not kg_fb and ("KG" in uu or "KGS" in uu or "KILO" in uu or "كيلو" in u_raw):
            kg_fb = True
    qty = _dec(li.qty)
    legacy = Decimal("0")
    if weight_ok and is_bag:
        legacy = qty * kpu  # type: ignore[operator]
    elif kg_fb:
        legacy = qty
    if is_bag or kg_fb:
        if persisted_total_weight_kg is not None:
            return dp.total_weight(_dec(persisted_total_weight_kg))
        return dp.total_weight(legacy)
    return Decimal("0")


def trade_line_qty_bags_python(li: TradePurchaseLineIn, *, unit_type_db: str | None = None) -> Decimal:
    ut = _effective_unit_type(li.unit, unit_type_db)
    uu = (li.unit or "").strip().upper()
    if ut == "bag" or (
        (unit_type_db is None or not str(unit_type_db).strip())
        and ("BAG" in uu or "SACK" in uu or uu in ("BG", "BGS"))
    ):
        return _dec(li.qty)
    return Decimal("0")


def trade_line_qty_boxes_python(li: TradePurchaseLineIn, *, unit_type_db: str | None = None) -> Decimal:
    ut = _effective_unit_type(li.unit, unit_type_db)
    uu = (li.unit or "").strip().upper()
    if ut == "box" or ((unit_type_db is None or not str(unit_type_db).strip()) and "BOX" in uu):
        return _dec(li.qty)
    return Decimal("0")


def trade_line_qty_tins_python(li: TradePurchaseLineIn, *, unit_type_db: str | None = None) -> Decimal:
    ut = _effective_unit_type(li.unit, unit_type_db)
    uu = (li.unit or "").strip().upper()
    if ut == "tin" or ((unit_type_db is None or not str(unit_type_db).strip()) and "TIN" in uu):
        return _dec(li.qty)
    return Decimal("0")
