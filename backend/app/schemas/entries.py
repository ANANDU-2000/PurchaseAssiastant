from __future__ import annotations

import uuid
from datetime import date
from typing import Any

from pydantic import BaseModel, Field, model_validator

# Units: legacy box maps to piece in UI; bag = wholesale bags × kg_per_bag
UNIT_PATTERN = r"^(kg|box|piece|bag)$"


class EntryLineInput(BaseModel):
    catalog_item_id: uuid.UUID | None = Field(
        default=None,
        description="Optional master catalog row; when set, server fills item_name/category/unit from catalog.",
    )
    catalog_variant_id: uuid.UUID | None = Field(
        default=None,
        description="Optional variant (e.g. Basmati under Rice).",
    )
    item_name: str
    category: str | None = None
    qty: float = Field(gt=0)
    unit: str = Field(pattern=UNIT_PATTERN)
    buy_price: float = Field(ge=0)
    landing_cost: float = Field(ge=0, description="Per purchase unit: per kg, per piece, or per bag when unit=bag")
    selling_price: float | None = Field(default=None, ge=0, description="Per kg when unit=bag; same unit as qty otherwise")
    bags: float | None = Field(default=None, gt=0, description="Redundant with qty when unit=bag")
    kg_per_bag: float | None = Field(default=None, gt=0)
    qty_kg: float | None = Field(default=None, gt=0, description="Total kg; computed for bag lines when possible")
    stock_note: str | None = Field(default=None, max_length=512, description="Optional stock / volume note before this purchase")

    @model_validator(mode="after")
    def validate_bag_fields(self) -> EntryLineInput:
        if self.unit == "bag":
            if self.kg_per_bag is None or self.kg_per_bag <= 0:
                raise ValueError("kg_per_bag is required and must be > 0 when unit is bag")
        return self


class EntryCreateRequest(BaseModel):
    entry_date: date
    supplier_id: uuid.UUID | None = None
    broker_id: uuid.UUID | None = None
    invoice_no: str | None = None
    place: str | None = Field(default=None, max_length=512, description="Purchase location / market / yard (optional)")
    transport_cost: float | None = None
    commission_amount: float | None = Field(default=None, ge=0)
    confirm: bool = False
    preview_token: str | None = Field(
        default=None,
        description="Issued by preview (confirm=false); required when confirm=true.",
    )
    force_duplicate: bool = Field(
        default=False,
        description="Set true after duplicate warning to allow save when server reports duplicates.",
    )
    lines: list[EntryLineInput] = Field(min_length=1)


class EntryLineOut(BaseModel):
    id: uuid.UUID | None = None
    catalog_item_id: uuid.UUID | None = None
    catalog_variant_id: uuid.UUID | None = None
    item_name: str
    category: str | None
    qty: float
    unit: str
    bags: float | None = None
    kg_per_bag: float | None = None
    qty_kg: float | None = None
    buy_price: float
    landing_cost: float
    selling_price: float | None
    profit: float | None
    stock_note: str | None = None

    model_config = {"from_attributes": True}


class EntryOut(BaseModel):
    id: uuid.UUID
    business_id: uuid.UUID
    entry_date: date
    supplier_id: uuid.UUID | None = None
    broker_id: uuid.UUID | None = None
    invoice_no: str | None = None
    place: str | None = None
    transport_cost: float | None = None
    commission_amount: float | None = None
    lines: list[EntryLineOut]

    model_config = {"from_attributes": True}


class EntryListResponse(BaseModel):
    items: list[dict[str, Any]]
    next_cursor: str | None = None


class DuplicateCheckRequest(BaseModel):
    item_name: str
    qty: float
    entry_date: date
    supplier_id: uuid.UUID | None = None
    catalog_variant_id: uuid.UUID | None = None


class DuplicateCheckResponse(BaseModel):
    duplicate: bool
    matching_entry_ids: list[uuid.UUID]


class ParseDraftResponse(BaseModel):
    draft: dict[str, Any] | None = None
    missing_fields: list[str] = Field(default_factory=list)
    confidence: float = 0.0
