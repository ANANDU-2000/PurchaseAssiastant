"""Bridge scanner ``ItemRow`` to ``TradePurchaseLineIn`` for ``line_totals_service`` preview money."""

from __future__ import annotations

import uuid
from decimal import Decimal

from app.schemas.trade_purchases import TradePurchaseLineIn
from app.services.line_totals_service import line_money
from app.services.scanner_v2.types import ItemRow

_ZERO = Decimal("0")


def _base_kwargs(
    *,
    catalog_item_id: uuid.UUID,
    item_name: str,
    qty: Decimal,
    unit: str,
    landing_cost: Decimal,
    purchase_rate: Decimal,
    kg_per_unit: Decimal | None = None,
    landing_cost_per_kg: Decimal | None = None,
) -> dict:
    return {
        "catalog_item_id": catalog_item_id,
        "item_name": item_name,
        "qty": qty,
        "unit": unit,
        "landing_cost": landing_cost,
        "purchase_rate": purchase_rate,
        "selling_rate": None,
        "discount": None,
        "tax_percent": _ZERO,
        "weight_per_unit": kg_per_unit,
        "kg_per_unit": kg_per_unit,
        "landing_cost_per_kg": landing_cost_per_kg,
        "freight_type": None,
        "freight_value": None,
        "delivered_rate": None,
        "billty_rate": None,
        "box_mode": None,
        "items_per_box": None,
        "weight_per_item": None,
        "kg_per_box": None,
        "weight_per_tin": None,
        "hsn_code": None,
        "item_code": None,
        "description": None,
    }


def item_row_to_trade_line_in_or_none(it: ItemRow) -> TradePurchaseLineIn | None:
    """Minimal mapping for SSOT preview; returns None when catalog or qty/rate is unusable."""
    cid = it.matched_catalog_item_id
    r = it.purchase_rate
    if cid is None or r is None or r <= 0:
        return None
    name = (it.matched_name or it.raw_name or "").strip() or "Scanned item"
    rdec = Decimal(r)
    ut = it.unit_type

    if ut == "KG":
        q = it.qty if it.qty is not None and it.qty > 0 else it.total_kg
        if q is None or q <= 0:
            return None
        qd = Decimal(q)
        return TradePurchaseLineIn.model_construct(
            **_base_kwargs(
                catalog_item_id=cid,
                item_name=name,
                qty=qd,
                unit="kg",
                landing_cost=rdec,
                purchase_rate=rdec,
            )
        )

    if ut == "PCS":
        q = it.qty
        if q is None or q <= 0:
            return None
        qd = Decimal(q)
        return TradePurchaseLineIn.model_construct(
            **_base_kwargs(
                catalog_item_id=cid,
                item_name=name,
                qty=qd,
                unit="pcs",
                landing_cost=rdec,
                purchase_rate=rdec,
            )
        )

    if ut == "BAG":
        bags = it.bags if it.bags is not None and it.bags > 0 else it.qty
        if bags is None or bags <= 0:
            return None
        bd = Decimal(bags)
        wpu = it.weight_per_unit_kg
        use_per_kg = it.rate_context == "per_kg" if it.rate_context is not None else rdec < Decimal("500")
        if wpu is not None and wpu > 0 and use_per_kg:
            w = Decimal(wpu)
            unit_cost = w * rdec
            return TradePurchaseLineIn.model_construct(
                **_base_kwargs(
                    catalog_item_id=cid,
                    item_name=name,
                    qty=bd,
                    unit="bag",
                    landing_cost=unit_cost,
                    purchase_rate=unit_cost,
                    kg_per_unit=w,
                    landing_cost_per_kg=rdec,
                )
            )
        if wpu is not None and wpu > 0 and not use_per_kg:
            w = Decimal(wpu)
            lcpk = rdec / w if w != 0 else None
            return TradePurchaseLineIn.model_construct(
                **_base_kwargs(
                    catalog_item_id=cid,
                    item_name=name,
                    qty=bd,
                    unit="bag",
                    landing_cost=rdec,
                    purchase_rate=rdec,
                    kg_per_unit=w,
                    landing_cost_per_kg=lcpk,
                )
            )
        return None

    if ut in ("BOX", "TIN"):
        q = it.qty if it.qty is not None and it.qty > 0 else it.bags
        if q is None or q <= 0:
            return None
        qd = Decimal(q)
        if rdec >= Decimal("500"):
            u = "box" if ut == "BOX" else "tin"
            return TradePurchaseLineIn.model_construct(
                **_base_kwargs(
                    catalog_item_id=cid,
                    item_name=name,
                    qty=qd,
                    unit=u,
                    landing_cost=rdec,
                    purchase_rate=rdec,
                )
            )
        tk = it.total_kg
        if tk is not None and tk > 0:
            tkd = Decimal(tk)
            return TradePurchaseLineIn.model_construct(
                **_base_kwargs(
                    catalog_item_id=cid,
                    item_name=name,
                    qty=tkd,
                    unit="kg",
                    landing_cost=rdec,
                    purchase_rate=rdec,
                )
            )
        wpu = it.weight_per_unit_kg
        if wpu is not None and wpu > 0:
            w = Decimal(wpu)
            unit_cost = qd * w * rdec
            return TradePurchaseLineIn.model_construct(
                **_base_kwargs(
                    catalog_item_id=cid,
                    item_name=name,
                    qty=qd,
                    unit="box" if ut == "BOX" else "tin",
                    landing_cost=unit_cost,
                    purchase_rate=unit_cost,
                    kg_per_unit=w,
                    landing_cost_per_kg=rdec,
                )
            )
        return None

    return None


def preview_line_money_ssot(it: ItemRow) -> Decimal | None:
    """Authoritative preview purchase amount when the row maps cleanly to trade lines."""
    li = item_row_to_trade_line_in_or_none(it)
    if li is None:
        return None
    try:
        return line_money(li)
    except Exception:
        return None
