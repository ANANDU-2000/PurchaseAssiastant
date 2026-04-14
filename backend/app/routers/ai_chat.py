"""Harisree AI — chat stub + structured intent (OpenAI / Groq / Gemini optional; keys stay on server)."""

import uuid
from typing import Annotated, Any, Literal

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import Settings, get_settings
from app.database import get_db
from app.deps import charge_ai_turn_for_business
from app.models import User
from app.services.app_assistant_chat import run_app_assistant_turn
from app.services.intent_stub import stub_intent_from_text
from app.services.llm_intent import extract_intent_json
from app.services.usage_logging import log_usage

router = APIRouter(prefix="/v1/businesses/{business_id}/ai", tags=["ai"])

HARISREE_INTENT_SYSTEM = """You are a purchase assistant for Harisree. Extract a structured JSON for business entries.
Return ONLY JSON.

Supported intents:
- create_entry
- update_entry
- delete_entry
- query_summary

Rules:
- Never guess numbers. If missing, set null.
- Normalize units (bag/kg/pc).
- Recognize items and variants.
- Map broker/supplier names if present.
"""


class ChatMessage(BaseModel):
    role: Literal["user", "assistant", "system"]
    content: str = Field(min_length=1, max_length=8000)


class ChatRequest(BaseModel):
    messages: list[ChatMessage] = Field(min_length=1, max_length=40)
    preview_token: str | None = None
    entry_draft: dict[str, Any] | None = None


class ChatResponse(BaseModel):
    reply: str
    model: str = "assistant"
    tokens_used_month: int = 0
    intent: str = "help"
    preview_token: str | None = None
    entry_draft: dict[str, Any] | None = None
    saved_entry: dict[str, Any] | None = None
    missing_fields: list[str] = Field(default_factory=list)


class IntentRequest(BaseModel):
    text: str = Field(min_length=1, max_length=8000)


class IntentResponse(BaseModel):
    intent: str = "create_entry"
    data: dict[str, Any]
    missing_fields: list[str] = Field(default_factory=list)
    reply_text: str
    tokens_used_month: int = 0


@router.post("/chat", response_model=ChatResponse)
async def ai_chat(
    business_id: uuid.UUID,
    user: Annotated[User, Depends(charge_ai_turn_for_business)],
    db: Annotated[AsyncSession, Depends(get_db)],
    settings: Annotated[Settings, Depends(get_settings)],
    body: ChatRequest,
):
    last = body.messages[-1].content.strip()
    out = await run_app_assistant_turn(
        db=db,
        business_id=business_id,
        user_id=user.id,
        message=last,
        settings=settings,
        preview_token=body.preview_token,
        entry_draft=body.entry_draft,
    )
    await log_usage(
        db,
        provider="ai",
        action="ai_chat",
        business_id=business_id,
        user_id=user.id,
        units=1,
    )
    prov = (settings.ai_provider or "stub").strip().lower()
    return ChatResponse(
        reply=out["reply"],
        model=prov if prov != "stub" else "assistant",
        tokens_used_month=user.ai_tokens_used_month,
        intent=out.get("intent") or "help",
        preview_token=out.get("preview_token"),
        entry_draft=out.get("entry_draft"),
        saved_entry=out.get("saved_entry"),
        missing_fields=out.get("missing_fields") or [],
    )


@router.post("/intent", response_model=IntentResponse)
async def ai_intent(
    business_id: uuid.UUID,
    user: Annotated[User, Depends(charge_ai_turn_for_business)],
    db: Annotated[AsyncSession, Depends(get_db)],
    settings: Annotated[Settings, Depends(get_settings)],
    body: IntentRequest,
):
    llm = await extract_intent_json(user_text=body.text, settings=settings, db=db)
    if llm is not None:
        await log_usage(
            db,
            provider=settings.ai_provider or "stub",
            action="ai_intent_llm",
            business_id=business_id,
            user_id=user.id,
            units=1,
        )
        return IntentResponse(
            intent=llm["intent"],
            data=llm["data"],
            missing_fields=llm["missing_fields"],
            reply_text=llm["reply_text"],
            tokens_used_month=user.ai_tokens_used_month,
        )
    await log_usage(
        db,
        provider="stub",
        action="ai_intent_stub",
        business_id=business_id,
        user_id=user.id,
        units=1,
    )
    data, missing = stub_intent_from_text(body.text)
    reply = (
        "Got a draft from your text. Review numbers — nothing is saved until you confirm in Entries."
        if not missing
        else "I need: " + ", ".join(missing) + ". Tap Entries and fill, or add detail to your message."
    )
    return IntentResponse(
        intent="create_entry",
        data=data,
        missing_fields=missing,
        reply_text=reply,
        tokens_used_month=user.ai_tokens_used_month,
    )
