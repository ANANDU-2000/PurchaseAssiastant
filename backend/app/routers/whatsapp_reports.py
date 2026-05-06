from __future__ import annotations

import uuid
from datetime import datetime
from typing import Annotated

from fastapi import APIRouter, Depends, Header, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import Settings, get_settings
from app.database import get_db
from app.deps import get_current_user, require_membership
from app.models import Membership, User, WhatsAppReportSchedule
from app.services.whatsapp_auto_reports import send_due_whatsapp_reports

router = APIRouter(prefix="/v1/businesses/{business_id}/whatsapp-reports", tags=["whatsapp-reports"])


class WhatsAppReportSchedulePatch(BaseModel):
    enabled: bool | None = None
    schedule_type: str | None = Field(None, max_length=16)  # daily|weekly|monthly
    hour: int | None = Field(None, ge=0, le=23)
    minute: int | None = Field(None, ge=0, le=59)
    timezone: str | None = Field(None, max_length=64)
    to_e164: str | None = Field(None, max_length=32)


@router.get("/schedule")
async def get_schedule(
    business_id: uuid.UUID,
    _user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
):
    q = select(WhatsAppReportSchedule).where(WhatsAppReportSchedule.business_id == business_id)
    row = (await db.execute(q)).scalars().first()
    if row is None:
        return {
            "enabled": False,
            "schedule_type": "weekly",
            "hour": 8,
            "minute": 0,
            "timezone": "Asia/Kolkata",
            "to_e164": "",
            "last_sent_at": None,
        }
    return {
        "enabled": bool(row.enabled),
        "schedule_type": row.schedule_type,
        "hour": int(row.hour),
        "minute": int(row.minute),
        "timezone": row.timezone,
        "to_e164": row.to_e164,
        "last_sent_at": row.last_sent_at.isoformat() if row.last_sent_at else None,
    }


@router.patch("/schedule")
async def patch_schedule(
    business_id: uuid.UUID,
    body: WhatsAppReportSchedulePatch,
    _user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
):
    q = select(WhatsAppReportSchedule).where(WhatsAppReportSchedule.business_id == business_id)
    row = (await db.execute(q)).scalars().first()
    if row is None:
        row = WhatsAppReportSchedule(
            business_id=business_id,
            enabled=False,
            schedule_type="weekly",
            hour=8,
            minute=0,
            timezone="Asia/Kolkata",
            to_e164="",
        )
        db.add(row)
        await db.flush()

    data = body.model_dump(exclude_unset=True)
    if "schedule_type" in data:
        t = (data["schedule_type"] or "").strip().lower()
        if t not in {"daily", "weekly", "monthly"}:
            raise HTTPException(status.HTTP_400_BAD_REQUEST, detail="Invalid schedule_type")
        row.schedule_type = t
    if "enabled" in data:
        row.enabled = bool(data["enabled"])
    if "hour" in data:
        row.hour = int(data["hour"])
    if "minute" in data:
        row.minute = int(data["minute"])
    if "timezone" in data:
        row.timezone = (data["timezone"] or "").strip() or "Asia/Kolkata"
    if "to_e164" in data:
        row.to_e164 = (data["to_e164"] or "").strip()
        if row.enabled and not row.to_e164:
            raise HTTPException(status.HTTP_400_BAD_REQUEST, detail="Phone is required when enabled")

    await db.commit()
    return {"ok": True}


# Internal cron hook (Render Cron Job). Not exposed via CORS.
internal_router = APIRouter(prefix="/internal", tags=["internal"])


@internal_router.post("/whatsapp-reports/send-due")
async def send_due(
    db: Annotated[AsyncSession, Depends(get_db)],
    settings: Annotated[Settings, Depends(get_settings)],
    x_cron_secret: Annotated[str | None, Header()] = None,
):
    secret = (settings.whatsapp_reports_cron_secret or "").strip()
    if not secret:
        raise HTTPException(status.HTTP_503_SERVICE_UNAVAILABLE, detail="Cron secret not configured")
    if (x_cron_secret or "").strip() != secret:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, detail="Unauthorized")
    if not (settings.whatsapp_cloud_access_token or "").strip():
        raise HTTPException(status.HTTP_503_SERVICE_UNAVAILABLE, detail="WhatsApp Cloud not configured")
    return await send_due_whatsapp_reports(settings, db)

