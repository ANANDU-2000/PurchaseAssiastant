"""Non-mutating trade purchase preview totals (SSOT: line + aggregate services)."""

from __future__ import annotations

import uuid
from typing import Any

from app.schemas.trade_purchases import (
    TradePurchaseCreateRequest,
    TradePurchasePreviewLineOut,
    TradePurchasePreviewOut,
    TradePurchaseValidateOut,
)
from app.services import trade_purchase_service as tps
from app.services.aggregate_totals_service import aggregate_landing_selling_profit
from app.services.line_totals_service import (
    line_gross_base,
    line_money,
    line_profit,
    line_total_weight,
)
from app.services.unit_resolution_service import resolve_from_text

# Wire-time placeholder only (preview/validate never persist). Avoids forcing a
# supplier UUID while the wizard is still on party step.
_PREVIEW_PLACEHOLDER_SUPPLIER = uuid.UUID("00000000-0000-0000-0000-000000000001")


def coerce_raw_to_trade_purchase_create(raw: dict[str, Any]) -> TradePurchaseCreateRequest:
    """Normalize client JSON into [TradePurchaseCreateRequest] for SSOT helpers."""
    d = dict(raw)
    if not d.get("supplier_id"):
        d["supplier_id"] = str(_PREVIEW_PLACEHOLDER_SUPPLIER)
    return TradePurchaseCreateRequest.model_validate(d)


def build_trade_purchase_preview(body: TradePurchaseCreateRequest) -> TradePurchasePreviewOut:
    """Compute per-line + header totals using the same primitives as create/persist.

    Per-line amounts use BOX/TIN wholesale stripping (same rows as persist). Header
    ``total_amount`` / aggregate subtotals follow ``create_trade_purchase``, which
    runs ``compute_totals`` / ``aggregate_landing_selling_profit`` on the **wire**
    body before per-line strip.
    """
    norm_lines = [tps.normalize_trade_line_for_preview(li) for li in body.lines]

    lines_out: list[TradePurchasePreviewLineOut] = []
    for i, li in enumerate(norm_lines):
        ur = resolve_from_text(li.item_name or "")
        body_for_line = body.model_copy(update={"lines": norm_lines})
        lines_out.append(
            TradePurchasePreviewLineOut(
                index=i,
                line_total=line_money(li),
                line_landing_gross=line_gross_base(li),
                line_profit=line_profit(li, body_for_line),
                line_total_weight_kg=line_total_weight(li),
                resolved_labels=ur.as_dict(),
            )
        )

    qty_sum, amt_sum = tps.compute_totals(body)
    land_s, sell_s, prof = aggregate_landing_selling_profit(body)
    return TradePurchasePreviewOut(
        lines=lines_out,
        total_qty=qty_sum,
        total_amount=amt_sum,
        total_landing_subtotal=land_s,
        total_selling_subtotal=sell_s,
        total_line_profit=prof,
    )


def build_trade_purchase_validate(body: TradePurchaseCreateRequest) -> TradePurchaseValidateOut:
    """Structured validation result for UI (non-mutating); same rules as create."""
    errs = tps.collect_trade_purchase_validation_errors(body)
    return TradePurchaseValidateOut(ok=len(errs) == 0, errors=errs, warnings=[])
