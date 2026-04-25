"""Per-business monthly cloud cost reminder."""

from __future__ import annotations

import uuid
from datetime import date, datetime, timezone
from typing import Annotated, Any
from zoneinfo import ZoneInfo

from fastapi import APIRouter, Body, Depends, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.deps import require_membership
from app.models import Membership
from app.services import cloud_expense_service as svc

router = APIRouter(prefix="/v1/businesses/{business_id}/cloud-cost", tags=["cloud-cost"])

def _today() -> date:
    """IST for Indian businesses; fall back to UTC if tz data unavailable (e.g. minimal Windows)."""
    try:
        return datetime.now(ZoneInfo("Asia/Kolkata")).date()
    except Exception:  # noqa: BLE001
        return datetime.now(timezone.utc).date()


class CloudCostPatchBody(BaseModel):
    name: str | None = Field(default=None, max_length=128)
    amount_inr: float | None = Field(default=None, gt=0)
    due_day: int | None = Field(default=None, ge=1, le=31)


class CloudCostPayBody(BaseModel):
    amount_inr: float | None = Field(default=None, description="Override default row amount")
    payment_id: str | None = Field(
        default=None, max_length=256, description="External PSP / UPI reference (optional)"
    )
    provider: str | None = Field(
        default=None, max_length=64, description="e.g. upi, razorpay, manual (optional)"
    )


@router.get("")
async def get_cloud_cost(
    business_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> dict[str, Any]:
    del _m
    today = _today()
    row = await svc.ensure_cloud_expense(db, business_id, today)
    hist = await svc.list_history(db, business_id)
    out = svc.row_to_dict(row, today, hist)
    await db.commit()
    return out


@router.patch("")
async def patch_cloud_cost(
    business_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
    body: CloudCostPatchBody = Body(default=CloudCostPatchBody()),
) -> dict[str, Any]:
    del _m
    today = _today()
    row = await svc.ensure_cloud_expense(db, business_id, today)
    if body.name is not None:
        row.name = body.name.strip() or "Cloud Cost"
    if body.amount_inr is not None:
        svc.validate_config(amount_inr=body.amount_inr, due_day=row.due_day)
        row.amount_inr = body.amount_inr
    if body.due_day is not None:
        svc.validate_config(amount_inr=float(row.amount_inr), due_day=body.due_day)
        row.due_day = body.due_day
        row.next_due_date = svc.first_next_due_from(today, row.due_day)
    await db.flush()
    hist = await svc.list_history(db, business_id)
    out = svc.row_to_dict(row, today, hist)
    await db.commit()
    return out


@router.post("/pay")
async def pay_cloud_cost(
    business_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
    body: CloudCostPayBody | None = Body(default=None),
) -> dict[str, Any]:
    del _m
    today = _today()
    row = await svc.ensure_cloud_expense(db, business_id, today)
    amt = body.amount_inr if body is not None else None
    ext = body.payment_id if body is not None else None
    prov = body.provider if body is not None else None
    try:
        await svc.pay_cloud_expense(
            db, row, today, amt, external_payment_id=ext, payment_provider=prov
        )
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e)) from e
    await db.refresh(row)
    hist = await svc.list_history(db, business_id)
    out = svc.row_to_dict(row, today, hist)
    await db.commit()
    return out
