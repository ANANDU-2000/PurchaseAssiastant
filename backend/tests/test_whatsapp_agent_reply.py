"""Grounded WhatsApp agent reply — stub / flag paths (no external LLM calls)."""

import asyncio
from unittest.mock import AsyncMock

from app.config import Settings
from app.services.whatsapp_agent_reply import maybe_polish_whatsapp_reply
from app.services.whatsapp_rules import rule_parse_whatsapp


def test_maybe_polish_stub_returns_none():
    s = Settings()
    s.ai_provider = "stub"

    async def _run():
        return await maybe_polish_whatsapp_reply(
            scene="query",
            user_text="profit today",
            server_message="₹100",
            settings=s,
            db=AsyncMock(),
        )

    assert asyncio.run(_run()) is None


def test_maybe_polish_query_without_flags_returns_none():
    s = Settings()
    s.ai_provider = "openai"
    s.openai_api_key = "sk-test"
    s.whatsapp_llm_reply = False
    s.whatsapp_llm_agent = False

    async def _run():
        return await maybe_polish_whatsapp_reply(
            scene="query",
            user_text="hi",
            server_message="facts",
            settings=s,
            db=AsyncMock(),
        )

    assert asyncio.run(_run()) is None


def test_maybe_polish_preview_without_agent_returns_none():
    s = Settings()
    s.ai_provider = "openai"
    s.openai_api_key = "sk-test"
    s.whatsapp_llm_agent = False

    async def _run():
        return await maybe_polish_whatsapp_reply(
            scene="preview",
            user_text="draft",
            server_message="Preview line",
            settings=s,
            db=AsyncMock(),
        )

    assert asyncio.run(_run()) is None


def test_rule_parse_help_menu():
    r = rule_parse_whatsapp("help")
    assert r is not None
    assert r["intent"] == "query"
    assert r["data"].get("query_kind") == "help_menu"
