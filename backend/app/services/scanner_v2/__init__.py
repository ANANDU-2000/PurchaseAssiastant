"""AI Purchase Scanner V2 — hybrid OCR + LLM pipeline.

See `docs/AI_SCANNER_SPEC.md` for the authoritative contract.

Public surface:

- `ScanResult`, `Match`, `ItemRow`, `Charges`, `BrokerCommission`, `Warning`
  (Pydantic models matching the JSON schema in `docs/AI_SCANNER_JSON_SCHEMA.md`).

This package never writes to the database except via the explicit `correct`
endpoint (which upserts into `catalog_aliases`). All other side effects flow
through the canonical `trade_purchase_service.create_trade_purchase`.
"""

from __future__ import annotations

from app.services.scanner_v2.types import (
    BrokerCommission,
    Candidate,
    Charges,
    ItemRow,
    Match,
    MatchState,
    ScanMeta,
    ScanResult,
    Severity,
    Totals,
    UnitType,
    Warning,
)
from app.services.scanner_v2.pipeline import (
    consume_cached_scan_result,
    get_cached_scan_result,
    scan_purchase_v2,
    scan_result_to_trade_purchase_create,
    update_cached_scan_result,
)

__all__ = [
    "BrokerCommission",
    "Candidate",
    "Charges",
    "ItemRow",
    "Match",
    "MatchState",
    "ScanMeta",
    "ScanResult",
    "Severity",
    "Totals",
    "UnitType",
    "Warning",
    "get_cached_scan_result",
    "consume_cached_scan_result",
    "scan_purchase_v2",
    "scan_result_to_trade_purchase_create",
    "update_cached_scan_result",
]
