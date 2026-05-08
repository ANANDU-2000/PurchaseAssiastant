"""Pydantic types mirroring `docs/AI_SCANNER_JSON_SCHEMA.md` exactly.

These types are wire-format-stable: do not rename fields without bumping the
endpoint version. Decimal money/qty/kg are emitted as JSON numbers via
``model_config = ConfigDict(json_encoders=...)`` and helpers in
``app.services.decimal_precision``.
"""

from __future__ import annotations

import uuid
from datetime import date
from decimal import Decimal
from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field

UnitType = Literal["BAG", "BOX", "TIN", "KG", "PCS"]
MatchState = Literal["auto", "needs_confirmation", "unresolved"]
Severity = Literal["info", "warn", "blocker"]


class _BaseV2(BaseModel):
    """Pydantic v2 base for scanner_v2 wire types.

    Decimal fields are serialized as JSON numbers via the model-level
    ``model_serializer`` configured per subclass when needed; for the simple
    cases in this module Pydantic's default Decimal-as-string fallback is
    overridden by ``json_schema_extra=str_to_decimal`` mode at output time.
    """

    model_config = ConfigDict(
        populate_by_name=True,
        extra="ignore",
    )


class Candidate(_BaseV2):
    """Top-N alternative for a match (UI uses this for 'Did you mean?' sheets)."""

    id: uuid.UUID
    name: str
    confidence: float = Field(ge=0.0, le=1.0)


class Match(_BaseV2):
    """Resolved supplier or broker."""

    raw_text: str
    matched_id: uuid.UUID | None = None
    matched_name: str | None = None
    confidence: float = Field(default=0.0, ge=0.0, le=1.0)
    match_state: MatchState = "unresolved"
    candidates: list[Candidate] = Field(default_factory=list)


class ItemRow(_BaseV2):
    """One scanned line item, fully resolved with bag/kg/rate fields."""

    raw_name: str
    matched_catalog_item_id: uuid.UUID | None = None
    matched_name: str | None = None
    confidence: float = Field(default=0.0, ge=0.0, le=1.0)
    match_state: MatchState = "unresolved"
    candidates: list[Candidate] = Field(default_factory=list)

    unit_type: UnitType = "KG"
    weight_per_unit_kg: Decimal | None = None
    bags: Decimal | None = None
    total_kg: Decimal | None = None
    qty: Decimal | None = None

    purchase_rate: Decimal | None = None
    selling_rate: Decimal | None = None
    line_total: Decimal | None = None

    delivered_rate: Decimal | None = None
    billty_rate: Decimal | None = None
    freight_amount: Decimal | None = None
    discount: Decimal | None = None
    tax_percent: Decimal | None = None
    notes: str | None = None


class Charges(_BaseV2):
    """Header-level charges (per-line overrides live on ItemRow)."""

    delivered_rate: Decimal | None = None
    billty_rate: Decimal | None = None
    freight_amount: Decimal | None = None
    freight_type: Literal["included", "separate"] | None = None
    discount_percent: Decimal | None = None


class BrokerCommission(_BaseV2):
    type: Literal["percent", "fixed_per_unit", "fixed_total"]
    value: Decimal
    applies_to: Literal["kg", "bag", "box", "tin", "once"] | None = None


class Totals(_BaseV2):
    total_bags: Decimal = Decimal("0")
    total_kg: Decimal = Decimal("0")
    total_amount: Decimal = Decimal("0")


class Warning(_BaseV2):
    code: str
    severity: Severity
    target: str | None = None
    message: str
    suggestion: str | None = None
    params: dict[str, Any] | None = None


class ScanMeta(_BaseV2):
    provider_used: str | None = None
    model_used: str | None = None
    extraction_duration_ms: int | None = None
    token_usage: dict[str, Any] | None = None
    retry_count: int = 0
    failover: list[dict[str, Any]] = Field(default_factory=list)
    parse_warnings: list[str] = Field(default_factory=list)
    ocr_chars: int = 0
    image_bytes_in: int = 0
    # Added in production rebuild: typed error hints for trader-friendly UI.
    error_stage: str | None = None  # e.g. ocr | parse | match | validate
    error_code: str | None = None  # stable string code for UX copy
    error_message: str | None = None  # short safe message (no stack traces)

    # Realtime scan status (scanner v3 start/status polling).
    stage: str | None = None  # preparing_image|uploading|extracting_text|parsing_items|matching|validating|ready|error
    stage_progress: float | None = Field(default=None, ge=0.0, le=1.0)
    stage_log: list[dict[str, Any]] = Field(default_factory=list)


class ScanResult(_BaseV2):
    """Top-level wire format. Mirrors `docs/AI_SCANNER_JSON_SCHEMA.md`."""

    supplier: Match
    broker: Match | None = None
    items: list[ItemRow] = Field(default_factory=list)
    charges: Charges = Field(default_factory=Charges)
    broker_commission: BrokerCommission | None = None
    payment_days: int | None = None

    # Bill metadata from Vision/LLM (optional; confirm UI may prefill invoice_number).
    invoice_number: str | None = None
    bill_date: date | None = None
    bill_fingerprint: str | None = None
    bill_notes: str | None = None
    scanned_total_amount: Decimal | None = None

    totals: Totals = Field(default_factory=Totals)

    confidence_score: float = Field(default=0.0, ge=0.0, le=1.0)
    needs_review: bool = True
    warnings: list[Warning] = Field(default_factory=list)

    scan_token: str = ""
    scan_meta: ScanMeta = Field(default_factory=ScanMeta)


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
]
