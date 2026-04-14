"""Rules-first parse: skip LLM when regex/rules confidence is high enough."""

import asyncio
from unittest.mock import AsyncMock, patch

import pytest

from app.config import Settings
from app.services.whatsapp_transaction_engine import merge_parse_async


@pytest.fixture
def settings_openai() -> Settings:
    s = Settings()
    s.ai_provider = "openai"
    s.openai_api_key = "sk-test"
    return s


def test_merge_parse_skips_llm_for_help_rule(settings_openai: Settings):
    async def run():
        db = AsyncMock()

        async def should_not_call_llm(*_a, **_k):
            raise AssertionError("extract_whatsapp_transactional_json must not run when rules win")

        with patch(
            "app.services.whatsapp_transaction_engine.extract_whatsapp_transactional_json",
            side_effect=should_not_call_llm,
        ):
            out = await merge_parse_async(user_text="help", settings=settings_openai, db=db)
        assert out.get("intent") == "query"
        assert out.get("data", {}).get("query_kind") == "help_menu"

    asyncio.run(run())
