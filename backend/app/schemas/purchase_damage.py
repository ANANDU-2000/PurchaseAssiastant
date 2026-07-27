import uuid
from datetime import datetime
from decimal import Decimal
from typing import Literal

from pydantic import BaseModel, Field, model_validator

DamageType = Literal["damaged", "short", "missing", "returned"]
DamageReason = Literal["torn_bag", "wet_damage", "wrong_item", "short_weight", "other"]
DamageStatus = Literal["pending", "approved", "returned", "rejected"]
DamageStatusPatch = Literal["approved", "returned", "rejected"]


class PurchaseDamageReportIn(BaseModel):
    item_name: str | None = Field(default=None, max_length=500)
    qty_damaged: Decimal = Field(gt=0)
    damage_type: DamageType | None = None
    catalog_item_id: uuid.UUID | None = None
    unit: str | None = Field(default=None, max_length=32)
    reason: DamageReason | None = None
    photo_url: str | None = Field(default=None, max_length=2000)
    notes: str | None = Field(default=None, max_length=4000)
    emit_notification: bool = True
    damaged_items_in_batch: int | None = Field(default=None, ge=1, le=500)

    @model_validator(mode="after")
    def _require_item_or_type(self) -> "PurchaseDamageReportIn":
        if not (self.item_name or "").strip() and self.catalog_item_id is None:
            raise ValueError("item_name or catalog_item_id is required")
        if self.damage_type is None and self.reason is None:
            raise ValueError("damage_type or reason is required")
        return self


class PurchaseDamageReportStatusPatch(BaseModel):
    status: DamageStatusPatch
    notes: str | None = Field(default=None, max_length=4000)


class PurchaseDamageReportOut(BaseModel):
    id: uuid.UUID
    created_at: datetime
    reported_by: str | None = None
    purchase_id: uuid.UUID | None = None
    catalog_item_id: uuid.UUID | None = None
    item_name: str
    qty_damaged: Decimal
    unit: str | None = None
    damage_type: str
    reason: str | None = None
    status: str = "pending"
    photo_url: str | None = None
    notes: str | None = None

    model_config = {"from_attributes": True}


class PendingDamageReportsCountOut(BaseModel):
    count: int
