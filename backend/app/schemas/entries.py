import uuid
from datetime import date
from typing import Any

from pydantic import BaseModel, Field


class EntryLineInput(BaseModel):
    catalog_item_id: uuid.UUID | None = Field(
        default=None,
        description="Optional master catalog row; when set, server fills item_name/category/unit from catalog.",
    )
    item_name: str
    category: str | None = None
    qty: float = Field(gt=0)
    unit: str = Field(pattern="^(kg|box|piece)$")
    buy_price: float = Field(ge=0)
    landing_cost: float = Field(ge=0, description="Manual landing cost per purchase unit")
    selling_price: float | None = Field(default=None, ge=0)


class EntryCreateRequest(BaseModel):
    entry_date: date
    supplier_id: uuid.UUID | None = None
    broker_id: uuid.UUID | None = None
    invoice_no: str | None = None
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
    item_name: str
    category: str | None
    qty: float
    unit: str
    buy_price: float
    landing_cost: float
    selling_price: float | None
    profit: float | None

    model_config = {"from_attributes": True}


class EntryOut(BaseModel):
    id: uuid.UUID
    business_id: uuid.UUID
    entry_date: date
    supplier_id: uuid.UUID | None = None
    broker_id: uuid.UUID | None = None
    invoice_no: str | None = None
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


class DuplicateCheckResponse(BaseModel):
    duplicate: bool
    matching_entry_ids: list[uuid.UUID]


class ParseDraftResponse(BaseModel):
    draft: dict[str, Any] | None = None
    missing_fields: list[str] = Field(default_factory=list)
    confidence: float = 0.0
