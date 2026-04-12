"""HEXA AI — chat stub + structured intent (OpenAI / Groq / Gemini optional; keys stay on server)."""

import re
import uuid
from typing import Annotated, Any, Literal

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import Settings, get_settings
from app.database import get_db
from app.deps import charge_ai_turn_for_business
from app.models import User
from app.services.llm_intent import extract_intent_json
from app.services.usage_logging import log_usage

router = APIRouter(prefix="/v1/businesses/{business_id}/ai", tags=["ai"])

HEXA_INTENT_SYSTEM = """You are a purchase assistant. Extract a structured JSON for business entries.
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


class ChatResponse(BaseModel):
    reply: str
    model: str = "stub"
    tokens_used_month: int = 0


class IntentRequest(BaseModel):
    text: str = Field(min_length=1, max_length=8000)


class IntentResponse(BaseModel):
    intent: str = "create_entry"
    data: dict[str, Any]
    missing_fields: list[str] = Field(default_factory=list)
    reply_text: str
    tokens_used_month: int = 0


def _stub_intent_from_text(text: str) -> tuple[dict[str, Any], list[str]]:
    """Very small heuristic until LLM is wired — keeps preview→confirm flow testable."""
    t = text.lower().strip()
    data: dict[str, Any] = {
        "item": None,
        "variant": None,
        "unit_type": None,
        "bags": None,
        "kg_per_bag": None,
        "qty_kg": None,
        "purchase_price_per_bag": None,
        "landed_cost_per_bag": None,
        "selling_price_per_kg": None,
        "transport": None,
        "loading": None,
        "broker": None,
        "broker_percent": None,
        "supplier": None,
        "location": None,
    }
    missing: list[str] = []

    m = re.search(r"(\d+)\s*bags?", t)
    if m:
        data["bags"] = float(m.group(1))
        data["unit_type"] = "bag"
    m2 = re.search(r"(\d+)\s*kg(?:/|\s*per\s*)?bag", t)
    if m2:
        data["kg_per_bag"] = float(m2.group(1))
    m3 = re.search(r"(?:rs\.?|₹|rupees?)\s*(\d{3,6})", t)
    if m3:
        data["landed_cost_per_bag"] = float(m3.group(1))
    m4 = re.search(r"sell(?:ing)?\s*(?:₹|rs\.?)?\s*(\d+)", t)
    if m4:
        data["selling_price_per_kg"] = float(m4.group(1))

    for word in ("rice", "oil", "atta", "dal"):
        if word in t:
            data["item"] = word
            break

    if data["bags"] is None and data["qty_kg"] is None:
        missing.append("quantity")
    if data["landed_cost_per_bag"] is None and data["purchase_price_per_bag"] is None:
        missing.append("landed_cost_per_bag or purchase_price")

    return data, missing


@router.post("/chat", response_model=ChatResponse)
async def ai_chat(
    business_id: uuid.UUID,
    user: Annotated[User, Depends(charge_ai_turn_for_business)],
    db: Annotated[AsyncSession, Depends(get_db)],
    body: ChatRequest,
):
    last = body.messages[-1].content.strip()
    reply = (
        "🛒 HEXA\n\n"
        f"You: {last}\n\n"
        "Preview → confirm → save is required before writing entries.\n"
        "Use **AI → Intent** for structured extraction, or type a line in **Entries**.\n\n"
        f"{HEXA_INTENT_SYSTEM.splitlines()[0]}"
    )
    await log_usage(
        db,
        provider="ai",
        action="ai_chat_stub",
        business_id=business_id,
        user_id=user.id,
        units=1,
    )
    return ChatResponse(reply=reply, model="stub", tokens_used_month=user.ai_tokens_used_month)


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
    data, missing = _stub_intent_from_text(body.text)
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
