"""Media endpoints: OCR/plain-text preview only; no auto-save."""

import uuid
from typing import Annotated

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field

from app.config import Settings, get_settings
from app.database import get_db
from app.deps import require_membership
from app.models import Membership
from app.services.bill_line_extract import extract_purchase_lines_from_text
from sqlalchemy.ext.asyncio import AsyncSession

router = APIRouter(prefix="/v1/businesses/{business_id}/media", tags=["media"])


class OcrRequest(BaseModel):
    image_base64: str = Field(default="", description="Base64 image data (optional when paste_text set)")
    paste_text: str | None = Field(
        default=None,
        max_length=20000,
        description="Optional pasted invoice lines for local extraction when OCR is unavailable",
    )


class OcrLineOut(BaseModel):
    item_name: str
    qty: float
    unit: str
    landing_cost: float


class OcrResponse(BaseModel):
    text: str = ""
    confidence: float = 0.0
    items: list[OcrLineOut] = Field(default_factory=list)
    missing_fields: list[str] = Field(default_factory=list)
    requires_user_confirmation: bool = True
    auto_save_allowed: bool = False
    note: str = "OCR provider not configured. Set OCR_API_KEY and ENABLE_OCR."


@router.post("/ocr", response_model=OcrResponse)
async def ocr_image(
    business_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
    settings: Annotated[Settings, Depends(get_settings)],
    body: OcrRequest,
):
    del business_id, _m, db
    paste = (body.paste_text or "").strip()
    raw_text = paste
    if not raw_text and body.image_base64:
        try:
            import base64

            raw = base64.b64decode(body.image_base64, validate=False)
            raw_text = raw.decode("utf-8", errors="ignore").strip()[:20000]
        except Exception:  # noqa: BLE001
            raw_text = ""
    extracted = extract_purchase_lines_from_text(raw_text)
    items = [
        OcrLineOut(
            item_name=e["item_name"],
            qty=float(e["qty"]),
            unit=str(e["unit"]),
            landing_cost=float(e["landing_cost"]),
        )
        for e in extracted
    ]
    ocr_on = settings.enable_ocr
    if not ocr_on:
        return OcrResponse(
            text=raw_text[:5000],
            confidence=0.35 if items else 0.0,
            items=items,
            missing_fields=[] if items else ["item_name", "qty", "unit", "rate"],
            requires_user_confirmation=True,
            auto_save_allowed=False,
            note="Cloud OCR off — parsed pasted/plain text only. Confirm lines before save.",
        )
    return OcrResponse(
        text=raw_text[:5000] or "Stub OCR — wire provider; user must confirm before save.",
        confidence=0.45 if items else 0.0,
        items=items,
        missing_fields=[] if items else ["item_name", "qty", "unit", "buy_price", "landing_cost"],
        requires_user_confirmation=True,
        auto_save_allowed=False,
        note="OCR flag on — user must confirm extracted lines before save.",
    )
