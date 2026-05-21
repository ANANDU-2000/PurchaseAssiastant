import uuid
from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field, field_validator


class UserCreateIn(BaseModel):
    full_name: str = Field(min_length=1, max_length=255)
    email: str = Field(min_length=5, max_length=320)
    phone: str = Field(min_length=6, max_length=32)
    role: str = Field(pattern="^(admin|manager|staff)$")
    password: str | None = None
    notes: str | None = Field(default=None, max_length=2000)
    is_active: bool = True

    @field_validator("email")
    @classmethod
    def email_lower(cls, v: str) -> str:
        return v.strip().lower()


class UserPatchIn(BaseModel):
    full_name: str | None = None
    email: str | None = None
    phone: str | None = None
    role: str | None = Field(default=None, pattern="^(admin|manager|staff|owner)$")
    is_active: bool | None = None
    is_blocked: bool | None = None
    notes: str | None = Field(default=None, max_length=2000)

    @field_validator("email")
    @classmethod
    def email_lower(cls, v: str | None) -> str | None:
        if v is None:
            return None
        return v.strip().lower()


class UserBulkIn(BaseModel):
    user_ids: list[uuid.UUID] = Field(min_length=1, max_length=100)
    action: Literal["activate", "deactivate", "block", "unblock", "delete", "set_role"]
    role: str | None = Field(default=None, pattern="^(admin|manager|staff)$")


class TodayStatsOut(BaseModel):
    scans: int = 0
    stock_updates: int = 0
    items_created: int = 0


class UserListOut(BaseModel):
    id: uuid.UUID
    name: str | None
    phone: str | None
    email: str
    username: str | None = None
    role: str
    is_active: bool
    is_blocked: bool = False
    last_login_at: datetime | None
    last_active_at: datetime | None
    today_stats: TodayStatsOut
    warehouse_name: str | None = None
    activity_count_7d: int = 0
    notes: str | None = None
    created_at: datetime | None = None


class ProfileStatsOut(BaseModel):
    stock_edits_total: int = 0
    purchases_total: int = 0
    scans_total: int = 0
    items_created_total: int = 0


class UserProfileOut(UserListOut):
    login_email: str | None = None
    purchases_7d: int = 0
    stock_updates_7d: int = 0
    stats: ProfileStatsOut | None = None


class UserCreateOut(BaseModel):
    user: UserListOut
    generated_password: str | None = None
    login_email: str | None = None


class ResetPasswordOut(BaseModel):
    new_password: str
    login_email: str | None = None


class ActivityLogIn(BaseModel):
    action_type: str
    item_id: uuid.UUID | None = None
    item_name: str | None = None
    details: dict | None = None


class ActivityLogOut(BaseModel):
    id: uuid.UUID
    user_name: str | None = None
    action_type: str
    item_id: uuid.UUID | None
    item_name: str | None
    details: dict | None
    created_at: datetime

    model_config = {"from_attributes": True}


class StockAdjustmentOut(BaseModel):
    id: uuid.UUID
    item_id: uuid.UUID
    item_name: str | None = None
    old_qty: float
    new_qty: float
    adjustment_type: str
    reason: str | None = None
    updated_at: datetime

    model_config = {"from_attributes": True}


class UserPurchaseBrief(BaseModel):
    id: uuid.UUID
    human_id: str | None = None
    purchase_date: datetime | None = None
    status: str | None = None
    total_amount: float | None = None
    supplier_name: str | None = None
    item_count: int | None = None


class CreatedItemOut(BaseModel):
    id: uuid.UUID
    name: str | None = None
    barcode: str | None = None
    category: str | None = None
    reorder_level: float | None = None
    updated_at: datetime | None = None


class LedgerEntryOut(BaseModel):
    kind: str
    at: datetime
    title: str
    subtitle: str | None = None
    details: dict | None = None


class LedgerGroupedOut(BaseModel):
    today: list[LedgerEntryOut] = Field(default_factory=list)
    yesterday: list[LedgerEntryOut] = Field(default_factory=list)
    this_week: list[LedgerEntryOut] = Field(default_factory=list)


class PermissionsOut(BaseModel):
    role: str
    permissions: dict[str, bool]


class PermissionsPatchIn(BaseModel):
    permissions: dict[str, bool] = Field(default_factory=dict)


class UserBulkOut(BaseModel):
    updated: int
    failed: list[str] = Field(default_factory=list)
