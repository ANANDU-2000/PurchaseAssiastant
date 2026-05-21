"""Strip financial fields from API payloads for warehouse staff role."""

from __future__ import annotations

from typing import Any

from app.schemas.trade_purchases import TradePurchaseLineOut, TradePurchaseOut

_CATALOG_ITEM_FINANCIAL_KEYS = frozenset(
    {
        "default_landing_cost",
        "default_selling_cost",
        "last_purchase_price",
        "last_selling_rate",
    }
)

_CATALOG_LINE_FINANCIAL_KEYS = frozenset(
    {
        "landing_cost",
        "selling_price",
        "profit",
        "landing_cost_per_kg",
        "purchase_rate",
        "selling_rate",
        "line_total",
        "line_landing_gross",
        "line_selling_gross",
        "line_profit",
    }
)

_ENTRY_LINE_FINANCIAL_KEYS = frozenset(
    {
        "buy_price",
        "landing_cost",
        "selling_price",
        "profit",
    }
)

_PURCHASE_HEADER_FINANCIAL_KEYS = frozenset(
    {
        "paid_amount",
        "discount",
        "commission_percent",
        "commission_money",
        "delivered_rate",
        "billty_rate",
        "freight_amount",
        "total_amount",
        "total_landing_subtotal",
        "total_selling_subtotal",
        "total_line_profit",
        "remaining",
    }
)

_LINE_FINANCIAL_KEYS = frozenset(
    {
        "landing_cost",
        "purchase_rate",
        "landing_cost_per_kg",
        "selling_cost",
        "selling_rate",
        "freight_value",
        "delivered_rate",
        "billty_rate",
        "line_total",
        "profit",
        "line_landing_gross",
        "line_selling_gross",
        "line_profit",
        "discount",
        "tax_percent",
        "rate_context",
    }
)


def should_redact_financials(role: str | None) -> bool:
    return (role or "").strip().lower() == "staff"


def redact_catalog_item_dict(item: dict[str, Any]) -> dict[str, Any]:
    out = dict(item)
    for k in _CATALOG_ITEM_FINANCIAL_KEYS:
        out.pop(k, None)
    return out


def redact_catalog_items(items: list[dict[str, Any]]) -> list[dict[str, Any]]:
    return [redact_catalog_item_dict(m) for m in items]


def redact_entry_line_dict(line: dict[str, Any]) -> dict[str, Any]:
    out = dict(line)
    for k in _ENTRY_LINE_FINANCIAL_KEYS:
        out.pop(k, None)
    return out


def redact_trade_line_dict(line: dict[str, Any]) -> dict[str, Any]:
    out = dict(line)
    for k in _LINE_FINANCIAL_KEYS:
        out.pop(k, None)
    return out


def redact_trade_purchase_dict(purchase: dict[str, Any]) -> dict[str, Any]:
    out = dict(purchase)
    for k in _PURCHASE_HEADER_FINANCIAL_KEYS:
        out.pop(k, None)
    lines = out.get("lines")
    if isinstance(lines, list):
        out["lines"] = [redact_trade_line_dict(li) if isinstance(li, dict) else li for li in lines]
    return out


def trade_purchase_to_staff_dict(purchase: TradePurchaseOut) -> dict[str, Any]:
    """Safe purchase payload for staff (no rates, totals, or payment amounts)."""
    d = purchase.model_dump(mode="json")
    return redact_trade_purchase_dict(d)


def trade_purchases_to_staff_dicts(purchases: list[TradePurchaseOut]) -> list[dict[str, Any]]:
    return [trade_purchase_to_staff_dict(p) for p in purchases]


def redact_catalog_line_row_dict(row: dict[str, Any]) -> dict[str, Any]:
    out = dict(row)
    for k in _CATALOG_LINE_FINANCIAL_KEYS:
        out.pop(k, None)
    return out


def redact_recent_purchase_dict(row: dict[str, Any]) -> dict[str, Any]:
    out = dict(row)
    out.pop("rate", None)
    return out


def redact_catalog_item_out_model(out: Any) -> Any:
    """Null financial fields on CatalogItemOut (Pydantic)."""
    if not hasattr(out, "model_copy"):
        return out
    return out.model_copy(
        update={
            "default_landing_cost": None,
            "default_selling_cost": None,
            "last_purchase_price": None,
            "last_selling_rate": None,
        }
    )


def redact_catalog_line_row_model(row: Any) -> Any:
    if not hasattr(row, "model_copy"):
        return row
    return row.model_copy(
        update={
            "landing_cost": None,
            "selling_price": None,
            "profit": None,
            "landing_cost_per_kg": None,
        }
    )


def redact_trade_line_out(line: TradePurchaseLineOut) -> dict[str, Any]:
    d = line.model_dump(mode="json")
    return redact_trade_line_dict(d)
