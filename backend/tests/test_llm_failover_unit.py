"""Unit tests for LLM failover gateway and loose JSON parsing."""

import asyncio

from app.services.llm_failover import run_ordered_failover
from app.services.llm_intent import _parse_json_loose


def test_run_ordered_failover_skips_no_key():
    async def boom() -> str:
        raise AssertionError("should not run")

    async def _run():
        return await run_ordered_failover(
            runners=[
                ("a", None, boom),
            ]
        )

    out, meta = asyncio.run(_run())
    assert out is None
    assert meta.get("provider_used") is None


def test_run_ordered_failover_gemini_fails_groq_succeeds():
    calls: list[str] = []

    async def bad() -> None:
        calls.append("gemini")
        return None

    async def good() -> str:
        calls.append("groq")
        return "ok"

    async def _run():
        return await run_ordered_failover(
            runners=[
                ("gemini", "gk", bad),
                ("groq", "qk", good),
                ("openai", None, good),
            ]
        )

    out, meta = asyncio.run(_run())
    assert out == "ok"
    assert meta.get("provider_used") == "groq"
    assert meta.get("failover_used") is True
    assert calls == ["gemini", "groq"]


def test_run_ordered_failover_all_three():
    async def fail() -> None:
        return None

    async def third() -> str:
        return "x"

    async def _run():
        return await run_ordered_failover(
            runners=[
                ("gemini", "a", fail),
                ("groq", "b", fail),
                ("openai", "c", third),
            ]
        )

    out, meta = asyncio.run(_run())
    assert out == "x"
    assert meta.get("provider_used") == "openai"
    assert meta.get("failover_used") is True


def test_parse_json_loose_markdown_fence():
    raw = """```json
{"intent": "query_summary", "data": {}, "missing_fields": [], "reply_text": ""}
```"""
    out = _parse_json_loose(raw)
    assert isinstance(out, dict)
    assert out.get("intent") == "query_summary"


def test_parse_json_loose_extra_text():
    raw = 'Here is JSON:\n{"a": 1}\nThanks.'
    out = _parse_json_loose(raw)
    assert out == {"a": 1}
