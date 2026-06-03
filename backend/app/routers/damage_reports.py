"""Business-level purchase damage report workflow (owner PATCH, pending count)."""

from __future__ import annotations

import uuid
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.deps import get_current_user, require_membership, require_role
from app.models import Membership, User
from app.schemas.purchase_damage import (
    PendingDamageReportsCountOut,
    PurchaseDamageReportOut,
    PurchaseDamageReportStatusPatch,
)
from app.services import purchase_damage_service as pds

router = APIRouter(prefix="/v1/businesses/{business_id}/damage-reports", tags=["damage-reports"])


@router.get("/pending-count", response_model=PendingDamageReportsCountOut)
async def pending_damage_reports_count(
    business_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
):
    del _m
    count = await pds.count_pending_damage_reports(db, business_id=business_id)
    return PendingDamageReportsCountOut(count=count)


@router.patch("/{report_id}", response_model=PurchaseDamageReportOut)
async def patch_damage_report_status(
    business_id: uuid.UUID,
    report_id: uuid.UUID,
    body: PurchaseDamageReportStatusPatch,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_role("owner", "manager", "super_admin"))],
):
    del user, _m
    try:
        row = await pds.update_damage_report_status(
            db,
            business_id=business_id,
            report_id=report_id,
            status=body.status,
            notes=body.notes,
        )
    except LookupError:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Damage report not found")
    except ValueError as e:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail=str(e)) from e
    return PurchaseDamageReportOut(**pds.damage_report_to_out(row))
