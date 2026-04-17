"""Pydantic contracts for wholesale trade purchases (new tables)."""

from __future__ import annotations

import uuid
from datetime import date, datetime
from typing import Any

from pydantic import BaseModel, Field


class TradePurchaseLineIn(BaseModel):
    catalog_item_id: uuid.UUID | None = None
    item_name: str = Field(..., max_length=512)
    qty: float = Field(..., gt=0)
    unit: str = Field(..., max_length=32)
    landing_cost: float = Field(..., ge=0)
    selling_cost: float | None = Field(None, ge=0)
    discount: float | None = Field(None, ge=0)
    tax_percent: float | None = Field(None, ge=0)


class TradePurchaseCreateRequest(BaseModel):
    purchase_date: date
    supplier_id: uuid.UUID | None = None
    broker_id: uuid.UUID | None = None
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
    catalog_item_id: uuid.UUID | None
    item_name: str
    qty: float
    unit: str
    landing_cost: float
    selling_cost: float | None
    discount: float | None
    tax_percent: float | None


class TradePurchaseOut(BaseModel):
    id: uuid.UUID
    human_id: str
    purchase_date: date
    supplier_id: uuid.UUID | None
    broker_id: uuid.UUID | None
    payment_days: int | None
    discount: float | None
    commission_percent: float | None
    delivered_rate: float | None
    billty_rate: float | None
    freight_amount: float | None
    freight_type: str | None = None
    total_qty: float | None
    total_amount: float
    status: str
    created_at: datetime
    lines: list[TradePurchaseLineOut]


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
