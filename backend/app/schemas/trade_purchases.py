"""Pydantic contracts for wholesale trade purchases (new tables)."""

from __future__ import annotations

import uuid
from datetime import date, datetime
from typing import Any

from pydantic import BaseModel, Field, model_validator


class TradePurchaseLineIn(BaseModel):
    """Catalog-linked purchase line.

    Phase 6 contract: every line must reference a `catalog_item_id`. This
    matches the strict client-side rule in `purchaseLineIsValidForSave` so
    server-only callers cannot slip free-typed items past the Flutter
    validation and break category/item analytics.
    """

    catalog_item_id: uuid.UUID
    item_name: str = Field(..., min_length=1, max_length=512)
    qty: float = Field(..., gt=0)
    unit: str = Field(..., min_length=1, max_length=32)
    landing_cost: float = Field(..., gt=0)
    """For bag/sack + per-kg pricing: weight per line unit (e.g. 50 for a 50 kg bag)."""
    kg_per_unit: float | None = Field(None, gt=0)
    """Rupee cost per kilogram; line gross = qty * kg_per_unit * landing_cost_per_kg when both set."""
    landing_cost_per_kg: float | None = Field(None, gt=0)
    selling_cost: float | None = Field(None, ge=0)
    discount: float | None = Field(None, ge=0)
    tax_percent: float | None = Field(None, ge=0)
    payment_days: int | None = Field(None, ge=0, le=3650)
    hsn_code: str | None = Field(None, max_length=32)
    item_code: str | None = Field(None, max_length=64)
    description: str | None = Field(None, max_length=512)

    @model_validator(mode="after")
    def _kg_fields_together(self) -> "TradePurchaseLineIn":
        a, b = self.kg_per_unit, self.landing_cost_per_kg
        if (a is None) != (b is None):
            raise ValueError("kg_per_unit and landing_cost_per_kg must both be set or both omitted")
        return self


class TradePurchaseCreateRequest(BaseModel):
    purchase_date: date
    invoice_number: str | None = Field(None, max_length=64)
    supplier_id: uuid.UUID
    broker_id: uuid.UUID | None = None
    status: str = Field(default="confirmed", pattern="^(draft|saved|confirmed)$")
    payment_days: int | None = Field(None, ge=0, le=3650)
    discount: float | None = Field(None, ge=0)
    commission_percent: float | None = Field(None, ge=0)
    delivered_rate: float | None = Field(None, ge=0)
    billty_rate: float | None = Field(None, ge=0)
    freight_amount: float | None = Field(None, ge=0)
    freight_type: str | None = Field(default=None, pattern="^(included|separate)$")
    lines: list[TradePurchaseLineIn] = Field(default_factory=list)


class TradePurchaseLineOut(BaseModel):
    id: uuid.UUID
    catalog_item_id: uuid.UUID
    item_name: str
    qty: float
    unit: str
    landing_cost: float
    kg_per_unit: float | None = None
    landing_cost_per_kg: float | None = None
    selling_cost: float | None
    discount: float | None
    tax_percent: float | None
    payment_days: int | None = None
    hsn_code: str | None = None
    item_code: str | None = None
    description: str | None = None
    # From linked catalog item (for BAG/kg math in clients; omitted when no catalog row).
    default_unit: str | None = None
    default_kg_per_bag: float | None = None
    default_purchase_unit: str | None = None
    line_landing_gross: float = 0
    line_selling_gross: float = 0
    line_profit: float | None = None


class TradePurchaseOut(BaseModel):
    id: uuid.UUID
    human_id: str
    invoice_number: str | None = None
    purchase_date: date
    supplier_id: uuid.UUID
    broker_id: uuid.UUID | None
    payment_days: int | None
    due_date: date | None = None
    paid_amount: float = 0
    paid_at: datetime | None = None
    discount: float | None
    commission_percent: float | None
    delivered_rate: float | None
    billty_rate: float | None
    freight_amount: float | None
    freight_type: str | None = None
    total_qty: float | None
    total_amount: float
    total_landing_subtotal: float | None = None
    total_selling_subtotal: float | None = None
    total_line_profit: float | None = None
    status: str
    remaining: float = 0
    derived_status: str = "confirmed"
    items_count: int = 0
    supplier_name: str | None = None
    broker_name: str | None = None
    supplier_gst: str | None = None
    supplier_address: str | None = None
    supplier_phone: str | None = None
    supplier_whatsapp: str | None = None
    broker_phone: str | None = None
    broker_location: str | None = None
    created_at: datetime
    updated_at: datetime | None = None
    lines: list[TradePurchaseLineOut]


class TradePurchaseUpdateRequest(TradePurchaseCreateRequest):
    """Full replace of header + lines (wizard edit)."""


class TradePurchasePaymentPatch(BaseModel):
    paid_amount: float = Field(..., ge=0)
    paid_at: datetime | None = None


class TradeMarkPaidRequest(BaseModel):
    """Optional partial payment; default pays remaining balance."""

    paid_amount: float | None = Field(None, ge=0)
    paid_at: datetime | None = None


class TradeDuplicateCheckRequest(BaseModel):
    supplier_id: uuid.UUID | None = None
    purchase_date: date
    total_amount: float = Field(..., ge=0)
    lines: list[TradePurchaseLineIn] = Field(default_factory=list)


class TradeDuplicateCheckResponse(BaseModel):
    duplicate: bool
    message: str | None = None
    existing_id: uuid.UUID | None = None
    existing_human_id: str | None = None


class TradeNextHumanIdOut(BaseModel):
    human_id: str


class TradeDraftUpsertRequest(BaseModel):
    step: int = Field(0, ge=0, le=3)
    payload: dict[str, Any] = Field(default_factory=dict)


class TradeDraftOut(BaseModel):
    step: int
    payload: dict[str, Any]
    updated_at: datetime
