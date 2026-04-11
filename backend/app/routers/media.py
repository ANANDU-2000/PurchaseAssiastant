"""Media endpoints: OCR and voice/STT — return structured preview only; no auto-save."""

import uuid
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field

from app.config import Settings, get_settings
from app.deps import require_membership
from app.models import Membership

router = APIRouter(prefix="/v1/businesses/{business_id}/media", tags=["media"])


class OcrRequest(BaseModel):
    image_base64: str = Field(..., description="Base64 image data (dev stub)")


class OcrResponse(BaseModel):
    text: str = ""
    confidence: float = 0.0
    missing_fields: list[str] = Field(default_factory=list)
    requires_user_confirmation: bool = True
    auto_save_allowed: bool = False
    note: str = "OCR provider not configured. Set OCR_API_KEY and ENABLE_OCR."


@router.post("/ocr", response_model=OcrResponse)
async def ocr_image(
    business_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    _body: OcrRequest,
    settings: Annotated[Settings, Depends(get_settings)],
):
    del business_id, _m, _body
    if not settings.enable_ocr:
        raise HTTPException(status.HTTP_403_FORBIDDEN, detail="OCR is disabled for this deployment")
    return OcrResponse(
        confidence=0.0,
        missing_fields=["item_name", "qty", "unit", "buy_price", "landing_cost"],
        requires_user_confirmation=True,
        auto_save_allowed=False,
        note="Stub OCR — wire provider + parsing; user must confirm before save.",
    )


class VoiceRequest(BaseModel):
    audio_base64: str = Field(..., description="Base64 audio (dev stub)")


class VoiceResponse(BaseModel):
    transcript: str = ""
    confidence: float = 0.0
    requires_user_confirmation: bool = True
    auto_save_allowed: bool = False
    note: str = "STT provider not configured. Set STT_API_KEY and ENABLE_VOICE."


@router.post("/voice", response_model=VoiceResponse)
async def voice_transcribe(
    business_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    _body: VoiceRequest,
    settings: Annotated[Settings, Depends(get_settings)],
):
    del business_id, _m, _body
    if not settings.enable_voice:
        raise HTTPException(status.HTTP_403_FORBIDDEN, detail="Voice is disabled for this deployment")
    return VoiceResponse(
        confidence=0.0,
        requires_user_confirmation=True,
        auto_save_allowed=False,
        note="Stub STT — wire provider + parse; user must confirm before save.",
    )
