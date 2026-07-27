"""Append api_usage_logs rows."""

from __future__ import annotations

import uuid
from typing import Any

from sqlalchemy.ext.asyncio import AsyncSession

from app.models import ApiUsageLog


async def log_usage(
    db: AsyncSession,
    *,
    provider: str,
    action: str,
    business_id: uuid.UUID | None = None,
    user_id: uuid.UUID | None = None,
    units: int = 1,
    cost_estimate_inr_paise: int | None = None,
    meta: dict[str, Any] | None = None,
) -> None:
    db.add(
        ApiUsageLog(
            business_id=business_id,
            user_id=user_id,
            provider=provider,
            action=action,
            units=units,
            cost_estimate_inr_paise=cost_estimate_inr_paise,
            meta=meta,
        )
    )
    await db.commit()
