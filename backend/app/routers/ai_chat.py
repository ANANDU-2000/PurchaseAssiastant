"""HEXA AI assistant — stub responder with strict system prompt (wire to OpenAI later)."""

import uuid
from typing import Annotated, Literal

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field

from app.deps import require_membership
from app.models import Membership

router = APIRouter(prefix="/v1/businesses/{business_id}/ai", tags=["ai"])

HEXA_SYSTEM_PROMPT = """You are HEXA, a purchase assistant for a wholesale business owner.
Language: Respond in the same language the user uses (Malayalam/English/Manglish).
Data: Use ONLY the user's purchase history database. Never guess or use external data.
Format: Keep replies short. Use emoji for visual clarity. Never write long paragraphs.
Actions: For entries — always show preview and ask confirmation before saving.
Numbers: Always show ₹ symbol. Show comparisons (vs last, vs avg).
Decisions: End with a clear recommendation (Buy / Wait / Negotiate).
Unknown: If query is unrelated to purchases, say: "I only help with purchase decisions 🛒"
"""


class ChatMessage(BaseModel):
    role: Literal["user", "assistant", "system"]
    content: str = Field(min_length=1, max_length=8000)


class ChatRequest(BaseModel):
    messages: list[ChatMessage] = Field(min_length=1, max_length=40)


class ChatResponse(BaseModel):
    reply: str
    model: str = "stub"


@router.post("/chat", response_model=ChatResponse)
async def ai_chat(
    business_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    body: ChatRequest,
):
    del business_id, _m
    last = body.messages[-1].content.strip()
    # Stub: deterministic echo so the app can be tested without API keys.
    reply = (
        "🛒 HEXA (preview mode)\n\n"
        f"You: {last}\n\n"
        "When connected to your data + LLM, I'll answer from purchase history only, "
        "with ₹ comparisons and a Buy / Wait / Negotiate line.\n\n"
        "—\n"
        + HEXA_SYSTEM_PROMPT.split("\n")[0]
    )
    return ChatResponse(reply=reply, model="stub")
