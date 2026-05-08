"""Best-effort persistence for AI purchase scanner audit traces."""

from __future__ import annotations

import logging
import uuid
from typing import Any

from fastapi.encoders import jsonable_encoder
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import PurchaseScanTrace
from app.services.scanner_v2.types import ScanResult

logger = logging.getLogger(__name__)


async def record_purchase_scan_trace(
    db: AsyncSession,
    *,
    business_id: uuid.UUID,
    user_id: uuid.UUID | None = None,
    scan_token: str | None,
    raw_response: dict[str, Any] | None,
    normalized: ScanResult | dict[str, Any] | None,
    stage: str = "preview",
) -> None:
    """Persist raw + normalized scanner data without ever breaking scanning.

    Scanner traces are audit/debug records. If the insert fails, the scan should
    still return a reviewable preview, so this function catches and rolls back
    its own failures.
    """
    try:
        normalized_json: dict[str, Any] | None
        if isinstance(normalized, ScanResult):
            normalized_json = normalized.model_dump(mode="json")
            meta = dict(normalized_json.get("scan_meta") or {})
            warnings = list(normalized_json.get("warnings") or [])
        elif isinstance(normalized, dict):
            normalized_json = jsonable_encoder(normalized)
            meta = dict(normalized_json.get("scan_meta") or {})
            warnings = list(normalized_json.get("warnings") or [])
        else:
            normalized_json = None
            meta = {}
            warnings = []

        provider = meta.get("provider_used")
        model = meta.get("model_used")
        image_bytes = int(meta.get("image_bytes_in") or 0)
        ocr_chars = int(meta.get("ocr_chars") or 0)

        db.add(
            PurchaseScanTrace(
                business_id=business_id,
                user_id=user_id,
                scan_token=scan_token,
                provider=str(provider) if provider else None,
                model=str(model) if model else None,
                stage=stage,
                raw_response_json=jsonable_encoder(raw_response) if raw_response is not None else None,
                normalized_response_json=normalized_json,
                warnings_json=warnings,
                meta_json=meta,
                image_bytes_in=image_bytes,
                ocr_chars=ocr_chars,
            )
        )
        await db.commit()
    except Exception as exc:  # noqa: BLE001
        await db.rollback()
        logger.warning(
            "purchase_scan_trace_write_failed business_id=%s scan_token=%s error=%s",
            business_id,
            scan_token or "-",
            type(exc).__name__,
        )
