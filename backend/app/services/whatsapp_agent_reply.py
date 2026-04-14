"""
Grounded WhatsApp reply polish: optional LLM rephrasing of server-authored text only.

Scenes:
- query: rephrase DB report facts (WHATSAPP_LLM_REPLY or WHATSAPP_LLM_AGENT)
- preview / action / clarify / help: only when WHATSAPP_LLM_AGENT and AI parsing enabled

Never invent numbers; on any failure returns None so callers keep deterministic text.
"""

from __future__ import annotations

import logging
from typing import Literal

from sqlalchemy.ext.asyncio import AsyncSession

from app.config import Settings
from app.services.feature_flags import is_ai_parsing_enabled
from app.services.llm_intent import (
    STRICT_WHATSAPP_LLM_PREFIX,
    synthesize_whatsapp_facts_reply,
    synthesize_whatsapp_plain_chat,
)

logger = logging.getLogger(__name__)

WhatsAppReplyScene = Literal["query", "preview", "action", "clarify", "help"]

_PREVIEW_SYSTEM = (
    STRICT_WHATSAPP_LLM_PREFIX
    + """You are Harisree Purchase Assistant on WhatsApp.
The SERVER_PREVIEW block is the only source of truth for purchase line items, quantities, and prices (computed by Harisree).
Write a short WhatsApp message (max ~700 characters). Preserve all numbers and rupee amounts exactly as in SERVER_PREVIEW.
Do not add items or prices not shown. Remind the user to reply YES to save or NO to cancel if the preview says so.
Plain text only; optional *bold* for labels if already implied. English or short Malayalam mix if the user's message used it."""
)

_ACTION_SYSTEM = (
    STRICT_WHATSAPP_LLM_PREFIX
    + """You are Harisree Purchase Assistant on WhatsApp.
The SERVER_RESULT block is authoritative (save/update/master record outcome from Harisree).
Write a brief friendly confirmation (max ~400 characters). Do not invent details. Plain text."""
)

_CLARIFY_SYSTEM = (
    STRICT_WHATSAPP_LLM_PREFIX
    + """You are Harisree Purchase Assistant on WhatsApp.
The SERVER_HINT block tells the user what to do next. Rephrase slightly for clarity (max ~500 characters).
Do not add new business facts or numbers. Plain text."""
)

_HELP_SYSTEM = (
    STRICT_WHATSAPP_LLM_PREFIX
    + """You are Harisree Purchase Assistant on WhatsApp.
The SERVER_HELP block lists what the bot can do. Keep the same constraints and commands; tighten wording only (max ~600 characters).
Do not promise features not mentioned in SERVER_HELP. Plain text."""
)


async def maybe_polish_whatsapp_reply(
    *,
    scene: WhatsAppReplyScene,
    user_text: str,
    server_message: str,
    settings: Settings,
    db: AsyncSession,
) -> str | None:
    """
    Returns polished text, or None to keep ``server_message`` unchanged.
    """
    if (settings.ai_provider or "stub").strip().lower() == "stub":
        return None

    if scene == "query":
        if not (settings.whatsapp_llm_reply or settings.whatsapp_llm_agent):
            return None
        if not await is_ai_parsing_enabled(db, settings):
            return None
        try:
            return await synthesize_whatsapp_facts_reply(
                user_text=user_text,
                facts_text=server_message,
                settings=settings,
                db=db,
            )
        except Exception as e:  # noqa: BLE001
            logger.warning("WhatsApp query polish failed: %s", e)
            return None

    if not settings.whatsapp_llm_agent:
        return None
    if not await is_ai_parsing_enabled(db, settings):
        return None

    sm = (server_message or "").strip()
    if not sm:
        return None
    ut = (user_text or "").strip()[:2000]
    block = f"USER_MESSAGE:\n{ut}\n\nSERVER_BLOCK:\n{sm[:6000]}"

    system = _HELP_SYSTEM
    if scene == "preview":
        system = _PREVIEW_SYSTEM
        block = f"USER_MESSAGE:\n{ut}\n\nSERVER_PREVIEW:\n{sm[:6000]}"
    elif scene == "action":
        system = _ACTION_SYSTEM
        block = f"USER_MESSAGE:\n{ut}\n\nSERVER_RESULT:\n{sm[:4000]}"
    elif scene == "clarify":
        system = _CLARIFY_SYSTEM
        block = f"USER_MESSAGE:\n{ut}\n\nSERVER_HINT:\n{sm[:4000]}"
    elif scene == "help":
        system = _HELP_SYSTEM
        block = f"USER_MESSAGE:\n{ut}\n\nSERVER_HELP:\n{sm[:5000]}"

    try:
        return await synthesize_whatsapp_plain_chat(
            system_prompt=system,
            user_content=block,
            settings=settings,
            db=db,
        )
    except Exception as e:  # noqa: BLE001
        logger.warning("WhatsApp %s polish failed: %s", scene, e)
        return None
